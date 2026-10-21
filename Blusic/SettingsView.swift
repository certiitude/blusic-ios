import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var exportURL: URL?
    @State private var sharing = false
    @State private var keyStatus: String?
    private let accents = ["blue", "violet", "rose", "mint", "orange", "white"]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    ZStack { RoundedRectangle(cornerRadius: 18).fill(.black).frame(width: 68, height: 68); BlusicMark().fill(.white, style: FillStyle(eoFill: true)).frame(width: 48, height: 48) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("blusic").font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-1)
                        Text("Ta musique, simplement.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }.listRowBackground(Color.clear)
            Section("Ton univers") {
                Picker("Apparence", selection: $library.settings.appearance) {
                    Text("Sombre").tag("dark"); Text("Claire").tag("light"); Text("Système").tag("system")
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Couleur d’accent")
                    HStack(spacing: 15) {
                        ForEach(accents, id: \.self) { accent in
                            Button { library.settings.accent = accent; library.haptic() } label: {
                                Circle().fill(color(accent)).frame(width: 32, height: 32)
                                    .overlay { if library.settings.accent == accent { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(accent == "white" ? Palette.background : .black.opacity(0.65)) } }
                            }.buttonStyle(.plain).accessibilityLabel("Accent \(accent)").accessibilityAddTraits(library.settings.accent == accent ? .isSelected : [])
                        }
                    }
                }.padding(.vertical, 7)
                VStack(alignment: .leading) {
                    Text("Arrondi des pochettes")
                    Slider(value: $library.settings.artworkRadius, in: 0...36, step: 1).accessibilityLabel("Arrondi des pochettes")
                }
                Toggle("Animations des pochettes", isOn: $library.settings.animateArtwork)
                Toggle("Retours haptiques", isOn: $library.settings.haptics)
                Toggle("Listes compactes", isOn: $library.settings.compactRows)
            }
            Section("Écoute") {
                NavigationLink { SoundSettingsView() } label: { Label("Égaliseur, vitesse et tonalité", systemImage: "slider.horizontal.3") }
                Toggle("Retrouver la file au lancement", isOn: $library.settings.restoreQueue)
                Text("Lecture native en arrière-plan, commandes sur l’écran verrouillé, Bluetooth et AirPlay. Import WAV, ALAC, FLAC, AIFF, AAC et MP3 non protégés, selon le décodage pris en charge par iOS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Group {
                    if showKey { TextField("Clé YouTube Data API v3", text: $apiKey) }
                    else { SecureField("Clé YouTube Data API v3", text: $apiKey) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Afficher la clé", isOn: $showKey)
                Button("Enregistrer la clé") {
                    do { try SecureStore.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "youtube-api-key"); keyStatus = "Clé enregistrée dans le trousseau de cet iPhone." }
                    catch { keyStatus = error.localizedDescription }
                }
                if let keyStatus { Text(keyStatus).font(.caption).foregroundStyle(.secondary) }
                Link("Créer une clé dans Google Cloud", destination: URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!)
                Text("Recherche et playlists publiques via l’API officielle. La vidéo reste visible et ses publicités éventuelles restent gérées par YouTube. Pas de lecture audio YouTube seule, de téléchargement YouTube ni de garantie de lecture en arrière-plan. Le catalogue YouTube Music personnel n’est pas synchronisé.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("YouTube") } footer: { Text("La clé reste dans le trousseau et n’est jamais incluse dans les sauvegardes. Google applique ses quotas et restrictions de clé.") }
            Section("Ta bibliothèque") {
                NavigationLink { ManageFilesView() } label: { Label("Gérer les fichiers importés", systemImage: "internaldrive") }
                Button {
                    do { exportURL = try library.exportBackup(); sharing = true }
                    catch { library.error = error.localizedDescription }
                } label: { Label("Exporter la bibliothèque JSON", systemImage: "square.and.arrow.up") }
                Text("La sauvegarde contient les playlists, favoris, paroles et statistiques. Conserve séparément les fichiers audio. Restauration via Bibliothèque → + → Importer une playlist → Choisir un fichier.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("À propos") {
                NavigationLink("Confidentialité et sources") { privacy }
                LabeledContent("Version", value: "1.0.0")
                Text("Fait pour écouter. Pas pour te distraire.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("À ton image").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { dismiss() } } }
        .onAppear { apiKey = SecureStore.read("youtube-api-key") }
        .sheet(isPresented: $sharing) { if let exportURL { ShareSheet(items: [exportURL]) } }
    }
    private func color(_ accent: String) -> Color { var settings = AppSettings(); settings.accent = accent; return settings.color }
    private var privacy: some View {
        List {
            Section("Sur ton iPhone") { Text("Aucun compte Blusic, aucune publicité ajoutée, aucun outil de mesure d’audience. Fichiers, favoris, réglages, paroles et historique sont enregistrés dans le conteneur de l’application. Les sauvegardes iCloud de l’iPhone peuvent les inclure selon tes réglages système.") }
            Section("Connexions externes") {
                Text("Une recherche ou un import YouTube transmet ta requête et ta clé à Google. Le lecteur intégré et les pochettes YouTube contactent Google et sont soumis à ses règles de confidentialité et à ses publicités. Une recherche de paroles transmet le titre et l’artiste à LRCLIB. Les URL audio importées contactent leur hébergeur et sont mises en cache.")
                Link("Confidentialité Google", destination: URL(string: "https://policies.google.com/privacy")!)
                Link("Conditions YouTube", destination: URL(string: "https://www.youtube.com/t/terms")!)
                Link("LRCLIB", destination: URL(string: "https://lrclib.net")!)
            }
            Section("Crédits") {
                Text("Identité visuelle Blusic adaptée de l’icône fournie. Pochettes et quatre instrumentaux de démonstration créés pour ce projet. Ils sont explicitement présentés comme des originaux Blusic Studio. Les paroles obtenues via LRCLIB et les contenus YouTube appartiennent à leurs titulaires respectifs.")
                Text("Les fichiers lossless restent sans réencodage avec les effets désactivés et la vitesse normale. Les effets, le mixage iOS et la sortie audio peuvent convertir le signal. Aucune conversion MP3 → lossless et aucune garantie bit-perfect.")
            }
        }.font(.subheadline).navigationTitle("En toute transparence").navigationBarTitleDisplayMode(.inline)
    }
}

struct ManageFilesView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @State private var removing: Track?
    private var imported: [Track] { library.tracks.filter { $0.source == .local } }
    var body: some View {
        List {
            if imported.isEmpty { EmptyState(symbol: "internaldrive", title: "Rien à ranger", message: "Les fichiers que tu importes apparaîtront ici.") }
            ForEach(imported) { track in
                VStack(alignment: .leading, spacing: 5) { Text(track.title).font(.headline); Text(track.subtitle).font(.caption).foregroundStyle(.secondary) }
                    .swipeActions { Button("Supprimer", role: .destructive) { removing = track } }
            }
        }
        .navigationTitle("Fichiers importés")
        .confirmationDialog("Supprimer ce fichier de Blusic ?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Supprimer le fichier et ses références", role: .destructive) {
                if let removing { player.forget(removing.id); library.remove(removing) }
                removing = nil
            }
        } message: { Text("Le fichier original dans Fichiers n’est pas supprimé.") }
    }
}
