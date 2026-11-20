import AVFoundation
import Foundation
import SwiftUI
import MediaToolbox

struct MusicEnergyFrame: Equatable, Sendable {
    var level: Double = 0
    var bass: Double = 0
    var pulse: Double = 0
    static let silence = MusicEnergyFrame()
    static func combined(_ a: Self, _ b: Self) -> Self {
        Self(level: max(a.level, b.level), bass: max(a.bass, b.bass), pulse: max(a.pulse, b.pulse))
    }
    func applyingGain(_ value: Float) -> Self {
        let gain = value.isFinite ? Double(min(1, max(0, value))) : 0
        return Self(level: level * gain, bass: bass * gain, pulse: pulse * gain)
    }
}

/// Analysis only: never writes to the PCM buffer or changes the audio graph's gain.
/// All storage is allocated before rendering. A failed try-lock drops analysis,
/// not audio; the render callback never waits on the UI.
final class MusicEnergyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var lowpass = [Double](repeating: 0, count: 8)
    private var rate = 0.0
    private var smoothLevel = 0.0
    private var smoothBass = 0.0
    private var bassReference = 0.0
    private var pulse = 0.0
    private var cooldown = 0.0
    private var latest = MusicEnergyFrame.silence
    private var updatedAt = -Double.infinity
    private var enabled = true

    @discardableResult func consume(_ buffer: AVAudioPCMBuffer, now: Double = ProcessInfo.processInfo.systemUptime) -> MusicEnergyFrame? {
        consume(buffer.audioBufferList, format: buffer.format.streamDescription.pointee, frames: Int(buffer.frameLength), now: now)
    }
    /// Reads both AVAudioEngine buffers and AVPlayer's real decoded PCM, including
    /// interleaved output. Never replaces or writes to the source AudioBufferList.
    @discardableResult func consume(_ bufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription, frames: Int,
                 offset: Int = 0, now: Double = ProcessInfo.processInfo.systemUptime) -> MusicEnergyFrame? {
        let channels = Int(format.mChannelsPerFrame), sampleRate = format.mSampleRate
        let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bits = Int(format.mBitsPerChannel), bytes = bits / 8
        guard format.mFormatID == kAudioFormatLinearPCM, (1...8).contains(channels), (1...262144).contains(frames),
              sampleRate.isFinite, (8000...192000).contains(sampleRate), format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              offset >= 0, offset <= 262144 - frames,
              (floating && (bits == 32 || bits == 64)) || (!floating && format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && (bits == 16 || bits == 32)) else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard buffers.count >= (planar ? channels : 1), Int(format.mBytesPerFrame) == bytes * (planar ? 1 : channels) else { return nil }
        for c in 0..<(planar ? channels : 1) {
            guard buffers[c].mData != nil, Int(buffers[c].mDataByteSize) >= (frames + offset) * bytes * (planar ? 1 : channels) else { return nil }
        }
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        guard enabled else { return nil }
        if rate != sampleRate {
            rate = sampleRate
            for c in 0..<lowpass.count { lowpass[c] = 0 }
        }
        let alpha = 1 - exp(-2 * .pi * 160 / sampleRate)
        var energy = 0.0, bassEnergy = 0.0
        for c in 0..<channels {
            let data = buffers[planar ? c : 0].mData!
            var low = lowpass[c]
            for i in 0..<frames {
                let index = planar ? i + offset : (i + offset) * channels + c
                let x: Double
                if floating && bits == 32 { x = Double(data.assumingMemoryBound(to: Float.self)[index]) }
                else if floating { x = data.assumingMemoryBound(to: Double.self)[index] }
                else if bits == 16 { x = Double(data.assumingMemoryBound(to: Int16.self)[index]) / 32768 }
                else { x = Double(data.assumingMemoryBound(to: Int32.self)[index]) / 2147483648 }
                guard x.isFinite else { continue }
                low += alpha * (x - low)
                energy += x * x; bassEnergy += low * low
            }
            lowpass[c] = low
        }
        let count = Double(frames) * Double(channels)
        let rms = sqrt(energy / count), bassRMS = sqrt(bassEnergy / count)
        let seconds = Double(frames) / sampleRate
        func normalized(_ value: Double) -> Double {
            guard value.isFinite, value > 0.00001 else { return 0 }
            return min(1, max(0, (20 * log10(value) + 55) / 43))
        }
        func follow(_ old: Double, _ new: Double) -> Double {
            let time = new > old ? 0.045 : 0.28
            return old + (new - old) * (1 - exp(-seconds / time))
        }
        smoothLevel = follow(smoothLevel, normalized(rms))
        smoothBass = follow(smoothBass, normalized(bassRMS))
        cooldown = max(0, cooldown - seconds)
        pulse *= exp(-seconds / 0.22)
        if bassRMS > 0.008, bassRMS > max(0.004, bassReference * 1.45), cooldown == 0 {
            pulse = min(1, normalized(bassRMS)); cooldown = 0.2
        }
        bassReference += (bassRMS - bassReference) * (1 - exp(-seconds / 0.22))
        latest = MusicEnergyFrame(level: smoothLevel, bass: smoothBass, pulse: pulse)
        updatedAt = now
        return latest
    }
    func snapshot(now: Double = ProcessInfo.processInfo.systemUptime) -> MusicEnergyFrame {
        lock.lock(); defer { lock.unlock() }
        guard now.isFinite, now >= updatedAt, now - updatedAt <= 0.3 else { return .silence }
        return latest
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        resetLocked()
    }
    func setEnabled(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        if enabled != value { enabled = value; resetLocked() }
    }
    private func resetLocked() {
        for c in 0..<lowpass.count { lowpass[c] = 0 }
        rate = 0; smoothLevel = 0; smoothBass = 0; bassReference = 0; pulse = 0; cooldown = 0
        latest = .silence; updatedAt = -.infinity
    }
}

private final class ProgressiveEnergyContext {
    let probe: MusicEnergyProbe
    let timeline: PresentationEnergyBuffer
    var format = AudioStreamBasicDescription()
    init(probe: MusicEnergyProbe, timeline: PresentationEnergyBuffer) { self.probe = probe; self.timeline = timeline }
}

/// AVPlayer may decode ahead. Select energy by the presentation clock, never by
/// the time a decode callback happened. Fixed storage; the audio thread never waits.
final class PresentationEnergyBuffer: @unchecked Sendable {
    private struct Entry { var start = -Double.infinity; var end = -Double.infinity; var frame = MusicEnergyFrame.silence }
    private let lock = NSLock()
    private var entries = [Entry](repeating: Entry(), count: 1024)
    private var cursor = 0
    func record(_ frame: MusicEnergyFrame, start: Double, duration: Double) {
        guard start.isFinite, duration.isFinite, duration > 0, lock.try() else { return }
        defer { lock.unlock() }
        entries[cursor] = Entry(start: start, end: start + duration, frame: frame)
        cursor = (cursor + 1) % entries.count
    }
    func snapshot(at seconds: Double) -> MusicEnergyFrame {
        lock.lock(); defer { lock.unlock() }
        guard seconds.isFinite else { return .silence }
        for distance in 1...entries.count {
            let entry = entries[(cursor + entries.count - distance) % entries.count]
            if entry.start <= seconds, seconds < entry.end { return entry.frame }
        }
        return .silence
    }
}

/// AVPlayer progressive M4A/MP3 assets expose decoded PCM through an audio mix.
/// The tap always returns Apple's original source buffers unchanged. It stays
/// installed for the item's lifetime; hiding the UI gates analysis, not audio.
@MainActor
final class ProgressiveMusicEnergyTap {
    let probe = MusicEnergyProbe()
    private let timeline = PresentationEnergyBuffer()
    private weak var item: AVPlayerItem?
    private var mix: AVAudioMix?
    var attached: Bool { mix != nil }
    init() { probe.setEnabled(false) }
    func attach(to item: AVPlayerItem) async throws -> Bool {
        guard !attached, item.audioMix == nil else { return false }
        guard let track = try await item.asset.loadTracks(withMediaType: .audio).first else { return false }
        try Task.checkCancellation()
        guard !attached, item.audioMix == nil else { return false }
        let context = ProgressiveEnergyContext(probe: probe, timeline: timeline)
        let storage = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: storage,
            init: { _, info, output in output.pointee = info },
            finalize: { tap in Unmanaged<ProgressiveEnergyContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in
                let context = Unmanaged<ProgressiveEnergyContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.format = format.pointee; context.probe.reset()
            },
            unprepare: { tap in
                Unmanaged<ProgressiveEnergyContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().probe.reset()
            },
            process: { tap, requested, _, buffers, frames, flags in
                var range = CMTimeRange.invalid
                let status = MTAudioProcessingTapGetSourceAudio(tap, requested, buffers, flags, &range, frames)
                guard status == noErr else { frames.pointee = 0; return }
                let context = Unmanaged<ProgressiveEnergyContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                guard range.start.isNumeric, context.format.mSampleRate > 0, frames.pointee > 0 else { return }
                let secondsPerFrame = range.duration.isNumeric && range.duration.seconds > 0
                    ? range.duration.seconds / Double(frames.pointee) : 1 / context.format.mSampleRate
                var offset = 0
                while offset < frames.pointee {
                    let count = min(1024, frames.pointee - offset)
                    if let frame = context.probe.consume(UnsafePointer(buffers), format: context.format, frames: count, offset: offset) {
                        context.timeline.record(frame, start: range.start.seconds + Double(offset) * secondsPerFrame,
                                                duration: Double(count) * secondsPerFrame)
                    }
                    offset += count
                }
            })
        var unmanaged: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &unmanaged)
        guard status == noErr, let unmanaged else { Unmanaged<ProgressiveEnergyContext>.fromOpaque(storage).release(); return false }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = unmanaged.takeRetainedValue()
        let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]
        self.item = item; self.mix = mix; item.audioMix = mix
        return true
    }
    func detach() {
        probe.setEnabled(false)
        if let item, item.audioMix === mix { item.audioMix = nil }
        item = nil; mix = nil
    }
    func snapshot(at seconds: Double) -> MusicEnergyFrame { timeline.snapshot(at: seconds) }
}

@MainActor
final class NativeMusicEnergyTap {
    let probe = MusicEnergyProbe()
    private var node: AVAudioNode?
    var attached: Bool { node != nil }
    func attach(to node: AVAudioNode) {
        if self.node === node { return }
        detach()
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        let probe = self.probe
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in _ = probe.consume(buffer) }
        self.node = node
    }
    func detach() {
        node?.removeTap(onBus: 0); node = nil; probe.reset()
    }
}

struct ReactiveBackgroundStyle: Equatable {
    var scale: Double
    var x: Double
    var y: Double
    var glow: Double
    var rotation: Double
    static func make(_ energy: MusicEnergyFrame, intensity: Double) -> Self {
        let strength = intensity.isFinite ? min(1, max(0, intensity)) : 0
        func bound(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        let bass = bound(energy.bass) * strength, pulse = bound(energy.pulse) * strength
        let level = bound(energy.level) * strength
        return Self(scale: 1 + bass * 0.06 + pulse * 0.04,
                    x: (bass - level) * 18 + pulse * 16, y: -bass * 8 - pulse * 18,
                    glow: level * 0.03 + pulse * 0.05, rotation: (bass - level) * 2)
    }
}

enum ReactiveBackgroundPolicy {
    static func shouldAnimate(enabled: Bool, reduceMotion: Bool, sceneActive: Bool, hasAudio: Bool,
                              volume: Float, intensity: Double) -> Bool {
        enabled && !reduceMotion && sceneActive && hasAudio && volume.isFinite && volume > 0.001 && intensity.isFinite && intensity > 0
    }
}

/// The 24 Hz clock invalidates only this background, never the transport,
/// lyrics, library or artwork request identity. No timer/random beat simulation.
struct ReactivePlayerBackground: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var enabled: Bool {
        ReactiveBackgroundPolicy.shouldAnimate(enabled: library.settings.usesReactiveBackground, reduceMotion: reduceMotion,
            sceneActive: scenePhase == .active, hasAudio: true,
            volume: library.settings.volume, intensity: library.settings.reactiveBackgroundStrength)
    }
    private var animating: Bool { enabled && player.hasReactiveAudioSource }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animating)) { _ in
            let frame = animating ? player.backgroundEnergy : .silence
            let style = ReactiveBackgroundStyle.make(frame, intensity: library.settings.reactiveBackgroundStrength)
            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.04, green: 0.09, blue: 0.14)
                    ArtworkView(track: player.current, size: 192, radius: 0, maximumPixels: 256)
                        .blur(radius: 18, opaque: true)
                        .scaleEffect(max(geometry.size.width, geometry.size.height) / 192 * 1.2 * style.scale)
                        .rotationEffect(.degrees(style.rotation))
                        .offset(x: style.x, y: style.y)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.55 + style.glow)
                    LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                }.clipped()
                 .animation(enabled ? .easeOut(duration: 0.07) : nil, value: style)
            }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { player.setReactiveBackgroundVisible(enabled) }
        .onChange(of: enabled) { _, value in player.setReactiveBackgroundVisible(value) }
        .onDisappear { player.setReactiveBackgroundVisible(false) }
    }
}

struct ReactiveBackgroundControls: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        Toggle("Fond animé au rythme de la musique", isOn: Binding(get: { library.settings.usesReactiveBackground }, set: { library.settings.reactiveBackgroundEnabled = $0 }))
            .accessibilityIdentifier("reactive-background")
        if library.settings.usesReactiveBackground {
            VStack(alignment: .leading, spacing: 7) {
                LabeledContent("Intensité du mouvement", value: "\(Int(library.settings.reactiveBackgroundStrength * 100)) %")
                Slider(value: Binding(get: { library.settings.reactiveBackgroundStrength }, set: { library.settings.reactiveBackgroundIntensity = $0 }), in: 0...1, step: 0.05)
                    .accessibilityLabel("Intensité du fond rythmé")
            }
        }
        Text("Les basses et les attaques du son déplacent les couleurs de la pochette, y compris sur les fichiers AAC progressifs compatibles. Aucun micro ni battement simulé. Respecte « Réduire les animations » et s’arrête lorsque le lecteur est fermé ou l’app en arrière-plan. Le lecteur vidéo officiel et HLS ne sont pas analysés.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
