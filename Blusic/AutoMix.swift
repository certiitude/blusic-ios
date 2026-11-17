import Foundation
import AVFoundation
import CryptoKit

struct MixAudioProfile: Codable, Sendable, Equatable {
    var duration: Double
    var activeStart: Double
    var activeEnd: Double
    var bpm: Double?
    var beatOffset: Double
    var confidence: Double
    var valid: Bool {
        duration.isFinite && duration > 0 && activeStart.isFinite && activeEnd.isFinite &&
        activeStart >= 0 && activeEnd >= activeStart && activeEnd <= duration + 0.1 &&
        beatOffset.isFinite && beatOffset >= 0 && confidence.isFinite && (0...1).contains(confidence) &&
        (bpm.map { $0.isFinite && (55...200).contains($0) } ?? true)
    }
}

struct AutoMixPlan: Sendable, Equatable {
    var outgoingStart: Double
    var incomingStart: Double
    var seconds: Double
    var tempoMultiplier: Float
    var beatMatched: Bool
    var explanation: String
}

enum AutoMixPlanner {
    static func plan(outgoing: MixAudioProfile, incoming: MixAudioProfile, allowTempo: Bool = true) -> AutoMixPlan {
        guard outgoing.valid, incoming.valid else {
            return AutoMixPlan(outgoingStart: 0, incomingStart: 0, seconds: 0, tempoMultiplier: 1, beatMatched: false, explanation: "AutoMix · analyse indisponible")
        }
        let end = min(outgoing.duration, max(outgoing.duration - 10, outgoing.activeEnd))
        let entry = min(6, max(0, incoming.activeStart))
        guard outgoing.duration >= 25, incoming.duration >= 25,
              allowTempo, outgoing.confidence >= 0.55, incoming.confidence >= 0.55,
              let left = outgoing.bpm, let right = incoming.bpm, left.isFinite, right.isFinite,
              (55...200).contains(left), (55...200).contains(right) else {
            let seconds = min(3, end / 3)
            return AutoMixPlan(outgoingStart: max(0, end - seconds), incomingStart: entry, seconds: seconds,
                               tempoMultiplier: 1, beatMatched: false, explanation: "AutoMix · fondu doux, rythme non fiable ou réglage manuel")
        }
        let variants = [right / 2, right, right * 2]
        let matched = variants.min { abs(left / $0 - 1) < abs(left / $1 - 1) } ?? right
        let ratio = left / matched
        guard (0.96...1.04).contains(ratio) else {
            return AutoMixPlan(outgoingStart: max(0, end - 4), incomingStart: entry, seconds: 4,
                               tempoMultiplier: 1, beatMatched: false, explanation: "AutoMix · fondus sans étirement, tempos trop éloignés")
        }
        let beat = 60 / left, overlap = min(8, max(3, 8 * beat))
        func nextBeat(_ time: Double, offset: Double, period: Double) -> Double {
            offset + ceil(max(0, time - offset) / period) * period
        }
        let start = max(0, outgoing.beatOffset + floor((end - overlap - outgoing.beatOffset) / beat) * beat)
        let incomingBeat = nextBeat(entry, offset: incoming.beatOffset, period: 60 / matched)
        return AutoMixPlan(outgoingStart: start, incomingStart: min(8, incomingBeat), seconds: overlap,
                           tempoMultiplier: Float(ratio), beatMatched: true,
                           explanation: String(format: "AutoMix · %.0f → %.0f BPM · tempo %+.1f %%", left, matched, (ratio - 1) * 100))
    }
    // Normalized equal-power curve: smooth perceptual overlap with no gain sum
    // above 1, even for identical/correlated recordings (no mixer clipping boost).
    static func gains(at fraction: Double) -> (incoming: Float, outgoing: Float) {
        let t = min(1, max(0, fraction)), a = sin(t * .pi / 2), b = cos(t * .pi / 2)
        let scale = max(1, a + b)
        return (Float(a / scale), Float(b / scale))
    }
}

/// 10ms energy/onset envelope. This estimates a beat grid, not vocal stems,
/// musical key, a guaranteed downbeat or Apple's proprietary phrase model.
enum MixRhythmEstimator {
    static func profile(energy: [Double], step: Double = 0.01) -> MixAudioProfile {
        let duration = Double(energy.count) * step
        guard step > 0, step.isFinite, energy.count > 40, let peak = energy.max(), peak > 1e-10,
              energy.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return MixAudioProfile(duration: max(0, duration.isFinite ? duration : 0), activeStart: 0,
                                   activeEnd: max(0, duration.isFinite ? duration : 0), bpm: nil, beatOffset: 0, confidence: 0)
        }
        let threshold = peak * 0.0001
        let first = energy.firstIndex { $0 >= threshold } ?? 0
        let last = energy.lastIndex { $0 >= threshold } ?? energy.count - 1
        var onset = [Double](repeating: 0, count: energy.count)
        var smoothed = energy[0]
        for i in 1..<energy.count {
            let previous = smoothed
            smoothed = 0.7 * energy[i] + 0.3 * smoothed
            onset[i] = max(0, sqrt(smoothed) - sqrt(previous))
        }
        let square = onset.reduce(0) { $0 + $1 * $1 }
        let base = MixAudioProfile(duration: duration, activeStart: Double(first) * step,
                                   activeEnd: Double(last + 1) * step, bpm: nil, beatOffset: 0, confidence: 0)
        guard duration >= 8, square > 1e-8 else { return base }
        let lower = max(2, Int((60 / 180 / step).rounded())), upper = min(onset.count / 3, Int((60 / 65 / step).rounded()))
        guard lower < upper else { return base }
        var bestLag = lower, best = 0.0
        for lag in lower...upper {
            if Task.isCancelled { return base }
            var dot = 0.0, left = 0.0, right = 0.0
            for i in lag..<onset.count {
                dot += onset[i] * onset[i - lag]; left += onset[i] * onset[i]; right += onset[i - lag] * onset[i - lag]
            }
            let score = dot / max(1e-12, sqrt(left * right))
            if score > best { best = score; bestLag = lag }
        }
        // Ignore periodicity caused by too few transients or a flat sine tone.
        let strong = onset.filter { $0 > sqrt(square / Double(onset.count)) }.count
        guard best >= 0.35, strong >= max(8, Int(duration * 0.5)) else { return base }
        var bestPhase = 0, phaseEnergy = 0.0
        for phase in 0..<bestLag {
            var total = 0.0
            for i in stride(from: phase, to: onset.count, by: bestLag) {
                total += onset[i]
                if i + 1 < onset.count { total += onset[i + 1] * 0.5 }
            }
            if total > phaseEnergy { phaseEnergy = total; bestPhase = phase }
        }
        var result = base
        result.bpm = 60 / (Double(bestLag) * step); result.beatOffset = Double(bestPhase) * step
        result.confidence = min(1, best)
        return result
    }
}

actor AutoMixAnalyzer {
    static let shared = AutoMixAnalyzer()
    private var memory: [String: MixAudioProfile] = [:]
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BlusicAutoMix-v1", isDirectory: true)
    }
    func analyze(_ url: URL) async throws -> MixAudioProfile {
        try Task.checkCancellation()
        guard url.isFileURL else { throw BlusicError.message("AutoMix nécessite un fichier audio complet.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let identity = "mix-v1|\(url.path)|\(attributes[.size] ?? 0)|\(modified)|\(attributes[.systemFileNumber] ?? 0)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        if let value = memory[key] { return value }
        let target = directory.appendingPathComponent(key).appendingPathExtension("json")
        if let data = try? Data(contentsOf: target), let value = try? JSONDecoder().decode(MixAudioProfile.self, from: data),
           value.valid { return value }
        let worker = Task.detached(priority: .utility) { try Self.measure(url) }
        let result = try await withTaskCancellationHandler {
            let value = try await worker.value; try Task.checkCancellation(); return value
        } onCancel: { worker.cancel() }
        if memory.count > 64 { memory.removeAll(keepingCapacity: true) }
        memory[key] = result
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: target, options: .atomic) }
        return result
    }
    private nonisolated static func measure(_ url: URL) throws -> MixAudioProfile {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = file.processingFormat.sampleRate, channels = Int(file.processingFormat.channelCount)
        guard (8000...192000).contains(rate), (1...2).contains(channels), file.length > 0, Double(file.length) / rate <= 7200,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else {
            throw BlusicError.message("Analyse AutoMix indisponible pour ce format ou cette durée.")
        }
        let hop = max(1, Int((rate * 0.01).rounded()))
        var energies: [Double] = [], sum = 0.0, count = 0, read: AVAudioFramePosition = 0
        while read < file.length {
            try Task.checkCancellation(); try file.read(into: buffer)
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            for i in 0..<Int(buffer.frameLength) {
                for c in 0..<channels {
                    let x = Double(data[c][i]); guard x.isFinite else { throw BlusicError.message("Signal audio invalide.") }
                    sum += x * x / Double(channels)
                }
                count += 1
                if count == hop { energies.append(sum / Double(count)); sum = 0; count = 0 }
            }
            read += AVAudioFramePosition(buffer.frameLength)
        }
        guard read == file.length else { throw BlusicError.message("Fichier incomplet pour AutoMix.") }
        if count > 0 { energies.append(sum / Double(count)) }
        var result = MixRhythmEstimator.profile(energy: energies, step: Double(hop) / rate)
        result.duration = Double(file.length) / rate
        return result
    }
}
