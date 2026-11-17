import AVFoundation
import Foundation
import SwiftUI

struct MusicEnergyFrame: Equatable, Sendable {
    var level: Double = 0
    var bass: Double = 0
    var pulse: Double = 0
    static let silence = MusicEnergyFrame()
    static func combined(_ a: Self, _ b: Self) -> Self {
        Self(level: max(a.level, b.level), bass: max(a.bass, b.bass), pulse: max(a.pulse, b.pulse))
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

    func consume(_ buffer: AVAudioPCMBuffer, now: Double = ProcessInfo.processInfo.systemUptime) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        let sampleRate = buffer.format.sampleRate, channels = Int(buffer.format.channelCount)
        guard buffer.frameLength > 0, sampleRate.isFinite, (8000...192000).contains(sampleRate),
              (1...8).contains(channels), !buffer.format.isInterleaved, let data = buffer.floatChannelData else { return }
        if rate != sampleRate {
            rate = sampleRate
            for c in 0..<lowpass.count { lowpass[c] = 0 }
        }
        let alpha = 1 - exp(-2 * .pi * 160 / sampleRate)
        var energy = 0.0, bassEnergy = 0.0
        for c in 0..<channels {
            var low = lowpass[c]
            for i in 0..<Int(buffer.frameLength) {
                let x = Double(data[c][i])
                guard x.isFinite else { continue }
                low += alpha * (x - low)
                energy += x * x; bassEnergy += low * low
            }
            lowpass[c] = low
        }
        let count = Double(buffer.frameLength) * Double(channels)
        let rms = sqrt(energy / count), bassRMS = sqrt(bassEnergy / count)
        let seconds = Double(buffer.frameLength) / sampleRate
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
    }
    func snapshot(now: Double = ProcessInfo.processInfo.systemUptime) -> MusicEnergyFrame {
        lock.lock(); defer { lock.unlock() }
        guard now.isFinite, now >= updatedAt, now - updatedAt <= 0.3 else { return .silence }
        return latest
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        for c in 0..<lowpass.count { lowpass[c] = 0 }
        rate = 0; smoothLevel = 0; smoothBass = 0; bassReference = 0; pulse = 0; cooldown = 0
        latest = .silence; updatedAt = -.infinity
    }
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
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in probe.consume(buffer) }
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
    static func make(_ energy: MusicEnergyFrame, intensity: Double) -> Self {
        let strength = intensity.isFinite ? min(1, max(0, intensity)) : 0
        func bound(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        let bass = bound(energy.bass) * strength, pulse = bound(energy.pulse) * strength
        let level = bound(energy.level) * strength
        return Self(scale: 1 + bass * 0.035 + pulse * 0.015,
                    x: (bass - level) * 16, y: -pulse * 10,
                    glow: level * 0.025 + pulse * 0.015)
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
            sceneActive: scenePhase == .active, hasAudio: player.hasReactiveAudioSource,
            volume: library.settings.volume, intensity: library.settings.reactiveBackgroundStrength)
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !enabled)) { _ in
            let frame = enabled && library.settings.volume > 0.001 ? player.backgroundEnergy : .silence
            let style = ReactiveBackgroundStyle.make(frame, intensity: library.settings.reactiveBackgroundStrength)
            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.04, green: 0.09, blue: 0.14)
                    ArtworkView(track: player.current, size: 192, radius: 0, maximumPixels: 256)
                        .blur(radius: 18, opaque: true)
                        .scaleEffect(max(geometry.size.width, geometry.size.height) / 192 * 1.2 * style.scale)
                        .offset(x: style.x, y: style.y)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.5)
                    library.settings.color.opacity(style.glow)
                    LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                }.clipped()
                 .animation(enabled ? .easeOut(duration: 0.12) : nil, value: style)
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
        Text("Les basses et l’intensité du son natif font respirer le fond du lecteur, sans modifier l’audio ni utiliser le micro. Fond fixe sur un flux progressif non préparé. Respecte « Réduire les animations » et s’arrête lorsque le lecteur est fermé ou l’app en arrière-plan.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
