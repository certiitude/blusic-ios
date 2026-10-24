import SwiftUI

struct SoundSettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var preset = "Personnel"
    private let presets: [String: [Float]] = [
        "Neutre": Array(repeating: 0, count: 10),
        "Basses": [6, 5, 3, 1, 0, 0, 0, 1, 1, 0],
        "Voix": [-2, -1, 0, 2, 4, 4, 3, 2, 0, -1],
        "Doux": [2, 2, 1, 0, -1, -1, 0, -2, -3, -4],
        "Électronique": [4, 3, 1, -1, -2, 0, 2, 3, 4, 3]
    ]
    var body: some View {
        Form {
            if player.isStreaming {
                Section {
                    Text("La musique démarre en lecture progressive. La vitesse est déjà réglable ; l’égaliseur et la tonalité utilisent le moteur complet une fois l’audio préparé.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { player.prepareNativeEffects() } label: {
                        HStack { Text(player.preparingEffects ? "Préparation des effets…" : "Préparer les effets audio"); if player.preparingEffects { Spacer(); ProgressView() } }
                    }.disabled(player.preparingEffects)
                    if let message = player.effectsMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Label("Vitesse", systemImage: "speedometer"); Spacer(); Text(String(format: "%.2f×", library.settings.playbackRate)).monospacedDigit().foregroundStyle(library.settings.color) }
                    Slider(value: Binding(get: { Double(library.settings.playbackRate) }, set: { library.settings.playbackRate = Float($0) }), in: 0.5...2, step: 0.05).accessibilityLabel("Vitesse")
                    HStack { ForEach([0.75, 1, 1.25, 1.5], id: \.self) { rate in Button(String(format: "%g×", rate)) { library.settings.playbackRate = Float(rate) }.buttonStyle(.bordered).frame(maxWidth: .infinity) } }.font(.caption)
                }.padding(.vertical, 8)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Label("Tonalité", systemImage: "pianokeys"); Spacer(); Text(String(format: "%+.0f demi-tons", library.settings.pitch)).font(.subheadline.monospacedDigit()).foregroundStyle(library.settings.color) }
                    Slider(value: Binding(get: { Double(library.settings.pitch) }, set: { library.settings.pitch = Float($0) }), in: -12...12, step: 1).accessibilityLabel("Tonalité en demi-tons")
                }.padding(.vertical, 8)
                Button("Réinitialiser la vitesse et la tonalité") { library.settings.playbackRate = 1; library.settings.pitch = 0 }
            } header: { Text("À ta façon") } footer: { Text("Vitesse et hauteur indépendantes, appliquées au moteur audio natif. Ces réglages ne s’appliquent pas au lecteur YouTube.") }

            Section {
                Toggle("Égaliseur 10 bandes", isOn: $library.settings.equalizerEnabled)
                Picker("Préréglage", selection: $preset) {
                    Text("Personnel").tag("Personnel")
                    ForEach(presets.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }.onChange(of: preset) { _, name in if let gains = presets[name] { library.settings.equalizer = gains; library.settings.equalizerEnabled = true } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(0..<10) { index in
                            VStack(spacing: 10) {
                                Text(String(format: "%+.0f", gain(index))).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                Slider(value: Binding(get: { Double(gain(index)) }, set: {
                                    if library.settings.equalizer.count != 10 { library.settings.equalizer = Array(repeating: 0, count: 10) }
                                    library.settings.equalizer[index] = Float($0); preset = "Personnel"
                                }), in: -12...12, step: 1)
                                .frame(width: 125).rotationEffect(.degrees(-90)).frame(width: 23, height: 125)
                                .accessibilityLabel("Égaliseur \(label(index)) hertz")
                                Text(label(index)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            }.frame(width: 25)
                        }
                    }.padding(.vertical, 16)
                }.disabled(!library.settings.equalizerEnabled)
            } header: { Text("Sculpte le son") } footer: { Text("Une réserve de niveau automatique limite la saturation quand tu renforces les fréquences. Le format affiché indique celui du fichier, pas la qualité de la liaison Bluetooth.") }
            Section("Boucle A–B") {
                Button(player.loopA == nil ? "Définir A à la position actuelle" : "A : \((player.loopA ?? 0).clock)") { player.loopA = player.position; player.loopB = nil }
                Button(player.loopB == nil ? "Définir B à la position actuelle" : "B : \((player.loopB ?? 0).clock)") { if let a = player.loopA, player.position > a { player.loopB = player.position } }.disabled(player.loopA == nil)
                Button("Effacer la boucle") { player.loopA = nil; player.loopB = nil }.disabled(player.loopA == nil)
            }
        }
        .navigationTitle("Le son, à ta mesure").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { dismiss() } } }
    }
    private func gain(_ i: Int) -> Float { library.settings.equalizer.indices.contains(i) ? library.settings.equalizer[i] : 0 }
    private func label(_ i: Int) -> String { let value = player.equalizerFrequencies[i]; return value >= 1000 ? "\(Int(value / 1000))k" : "\(Int(value))" }
}
