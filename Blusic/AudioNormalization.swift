import Foundation
import AVFoundation
import CryptoKit

/// A playback-only gain: the compressed source and explicit downloads never change.
struct AudioLoudnessProfile: Codable, Equatable, Sendable {
    var integratedLUFS: Double?
    var samplePeak: Double
    var duration: Double

    // Sample-peak headroom, not a claim of certified oversampled true-peak limiting.
    static let targetLUFS = -16.0
    static let peakCeilingDB = -2.0
    var gainDecibels: Float {
        guard let loudness = integratedLUFS, loudness.isFinite, samplePeak.isFinite, samplePeak > 0 else { return 0 }
        let peakDB = 20 * log10(samplePeak)
        return Float(max(-96, min(12, min(Self.targetLUFS - loudness, Self.peakCeilingDB - peakDB))))
    }
}

/// ITU-R BS.1770 K weighting, 400 ms blocks/100 ms hops, -70 LUFS absolute
/// and -10 LU relative gates. Mono/stereo only: never invent surround weights.
struct AudioLoudnessMeter {
    private struct Biquad {
        var b0: Double; var b1: Double; var b2: Double
        var a1: Double; var a2: Double
        var z1 = 0.0; var z2 = 0.0
        mutating func process(_ input: Double) -> Double {
            let output = b0 * input + z1
            z1 = b1 * input - a1 * output + z2
            z2 = b2 * input - a2 * output
            return output
        }
        static func shelf(rate: Double) -> Self {
            let k = tan(.pi * 1681.974450955533 / rate), q = 0.7071752369554196
            let vh = pow(10, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416)
            let a0 = 1 + k / q + k * k
            return Self(b0: (vh + vb * k / q + k * k) / a0, b1: 2 * (k * k - vh) / a0,
                        b2: (vh - vb * k / q + k * k) / a0, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        }
        static func highpass(rate: Double) -> Self {
            let k = tan(.pi * 38.13547087602444 / rate), q = 0.5003270373238773
            let a0 = 1 + k / q + k * k
            return Self(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        }
    }
    private let sampleRate: Double
    private let channels: Int
    private let hop: Int
    private var shelves: [Biquad]
    private var highpasses: [Biquad]
    private var hopEnergy = 0.0
    private var hopFrames = 0
    private var recent: [Double] = []
    private var blocks: [Double] = []
    private var totalEnergy = 0.0
    private var frames: Int64 = 0
    private var peak = 0.0

    init(sampleRate: Double, channels: Int) throws {
        guard sampleRate.isFinite, (8000...192000).contains(sampleRate), (1...2).contains(channels) else {
            throw BlusicError.message("Normalisation disponible pour l’audio mono et stéréo de 8 à 192 kHz.")
        }
        self.sampleRate = sampleRate; self.channels = channels; hop = max(1, Int((sampleRate * 0.1).rounded()))
        shelves = Array(repeating: .shelf(rate: sampleRate), count: channels)
        highpasses = Array(repeating: .highpass(rate: sampleRate), count: channels)
    }
    mutating func consume(_ buffer: AVAudioPCMBuffer) throws {
        guard Int(buffer.format.channelCount) == channels, buffer.format.sampleRate == sampleRate,
              let data = buffer.floatChannelData, !buffer.format.isInterleaved else { throw BlusicError.message("Format PCM d’analyse incompatible.") }
        for frame in 0..<Int(buffer.frameLength) {
            var energy = 0.0
            for channel in 0..<channels {
                let sample = Double(data[channel][frame])
                guard sample.isFinite else { throw BlusicError.message("Échantillon audio invalide.") }
                peak = max(peak, abs(sample))
                let weighted = highpasses[channel].process(shelves[channel].process(sample))
                energy += weighted * weighted
            }
            hopEnergy += energy; totalEnergy += energy; hopFrames += 1; frames += 1
            if hopFrames == hop {
                recent.append(hopEnergy / Double(hop))
                if recent.count > 4 { recent.removeFirst() }
                if recent.count == 4 { blocks.append(recent.reduce(0, +) / 4) }
                hopFrames = 0; hopEnergy = 0
            }
        }
    }
    func finish() throws -> AudioLoudnessProfile {
        guard frames > 0, peak.isFinite else { throw BlusicError.message("Aucun audio à analyser.") }
        // Sub-400 ms files use their complete energy rather than padding with silence.
        let energies = blocks.isEmpty ? [totalEnergy / Double(frames)] : blocks
        let absoluteThreshold = pow(10, (-70 + 0.691) / 10)
        let absolute = energies.filter { $0.isFinite && $0 >= absoluteThreshold }
        guard !absolute.isEmpty else { return AudioLoudnessProfile(integratedLUFS: nil, samplePeak: peak, duration: Double(frames) / sampleRate) }
        let relativeThreshold = absolute.reduce(0, +) / Double(absolute.count) / 10
        let gated = absolute.filter { $0 >= relativeThreshold }
        let mean = gated.reduce(0, +) / Double(gated.count)
        return AudioLoudnessProfile(integratedLUFS: -0.691 + 10 * log10(mean), samplePeak: peak, duration: Double(frames) / sampleRate)
    }
}

actor AudioNormalizationAnalyzer {
    static let shared = AudioNormalizationAnalyzer()
    private let directory: URL
    private var memory: [String: AudioLoudnessProfile] = [:]
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BlusicLoudness-v1", isDirectory: true)
    }
    func analyze(_ url: URL) async throws -> AudioLoudnessProfile {
        try Task.checkCancellation()
        guard url.isFileURL else { throw BlusicError.message("La normalisation nécessite un fichier audio complet.") }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let identity = "bs1770-v1|\(url.standardizedFileURL.path)|\(values.fileSize ?? -1)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        if let profile = memory[key] { return profile }
        let path = directory.appendingPathComponent(key).appendingPathExtension("json")
        if let data = try? Data(contentsOf: path), let profile = try? JSONDecoder().decode(AudioLoudnessProfile.self, from: data),
           profile.duration > 0, profile.duration.isFinite, profile.samplePeak >= 0, profile.samplePeak.isFinite,
           profile.integratedLUFS?.isFinite != false { return profile }
        // Decoding/filtering never runs on the UI or audio render thread. Chunked,
        // bounded memory; cancellation propagates to the independent worker.
        let worker = Task.detached(priority: .utility) { try Self.measure(url) }
        let profile = try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
        if memory.count >= 128 { memory.removeAll(keepingCapacity: true) }
        memory[key] = profile
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(profile) { try? data.write(to: path, options: .atomic) }
        return profile
    }
    private nonisolated static func measure(_ url: URL) throws -> AudioLoudnessProfile {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        var meter = try AudioLoudnessMeter(sampleRate: file.processingFormat.sampleRate, channels: Int(file.processingFormat.channelCount))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw BlusicError.message("Analyse audio impossible.") }
        var count: AVAudioFramePosition = 0
        while count < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try meter.consume(buffer); count += AVAudioFramePosition(buffer.frameLength)
        }
        guard count == file.length else { throw BlusicError.message("L’analyse du morceau est incomplète.") }
        return try meter.finish()
    }
}
