import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var instanceAddress = ""
    @State private var exportURL: URL?
    @State private var sharing = false
    @State private var instanceStatus: String?
    @State private var checkingInstance = false
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
                TextField("https://ton-instance.example", text: $instanceAddress)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Adresse de l’instance Invidious")
                Toggle("Instances de secours automatiques", isOn: Binding(get: { library.settings.usesInvidiousFallback }, set: { library.settings.invidiousAutomaticFallback = $0 }))
                Button("Enregistrer l’instance") {
                    do {
                        let url = try InvidiousService.instanceURL(instanceAddress)
                        library.settings.invidiousInstance = url.absoluteString
                        instanceStatus = "Instance enregistrée : \(url.host ?? url.absoluteString)"
                    } catch { instanceStatus = error.localizedDescription }
                }
                Button {
                    Task {
                        checkingInstance = true
                        defer { checkingInstance = false }
                        do {
                            let service = try InvidiousService(address: instanceAddress, automaticFallback: false)
                            instanceStatus = try await service.checkConnection()
                        } catch { instanceStatus = error.localizedDescription }
                    }
                } label: { HStack { Text("Tester cette instance"); if checkingInstance { Spacer(); ProgressView() } } }.disabled(checkingInstance)
                Button("Revenir à l’instance par défaut") {
                    library.settings.invidiousInstance = nil
                    instanceAddress = InvidiousService.defaultInstance
                    instanceStatus = nil
                }
                if let instanceStatus { Text(instanceStatus).font(.caption).foregroundStyle(.secondary) }
                Link("Instances publiques Invidious", destination: URL(string: "https://docs.invidious.io/instances/")!)
                Text("Catalogue YouTube public sans clé Google. Blusic sélectionne le meilleur flux AAC/M4A compatible et utilise le moteur audio natif : arrière-plan, égaliseur, vitesse et tonalité. Les URL temporaires sont résolues à chaque lecture et un relais est essayé si l’accès direct échoue.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Invidious") } footer: { Text("Service communautaire non officiel : certaines instances bloquent l’API et certains titres sont indisponibles. La qualité AAC est compressée, pas lossless. Les serveurs de secours proviennent de l’annuaire public du projet et doivent annoncer leur API comme active.") }
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
                LabeledContent("Version", value: "1.1.0")
                Text("Fait pour écouter. Pas pour te distraire.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("À ton image").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { dismiss() } } }
        .onAppear { instanceAddress = library.settings.invidiousAddress }
        .sheet(isPresented: $sharing) { if let exportURL { ShareSheet(items: [exportURL]) } }
    }
    private func color(_ accent: String) -> Color { var settings = AppSettings(); settings.accent = accent; return settings.color }
    private var privacy: some View {
        List {
            Section("Sur ton iPhone") { Text("Aucun compte Blusic, aucune publicité ajoutée, aucun outil de mesure d’audience. Fichiers, favoris, réglages, paroles et historique sont enregistrés dans le conteneur de l’application. Les sauvegardes iCloud de l’iPhone peuvent les inclure selon tes réglages système.") }
            Section("Connexions externes") {
                Text("Les recherches, imports de playlists et identifiants vidéo sont transmis à l’instance Invidious choisie. En cas de panne, le secours automatique consulte api.invidious.io et peut contacter d’autres instances publiques. Les flux audio directs et certaines pochettes contactent Google ; les relais passent par l’instance. Les fichiers audio sont mis en cache dans le conteneur de Blusic. Une recherche de paroles transmet le titre et l’artiste à LRCLIB. Le lecteur vidéo officiel n’est ouvert que sur demande depuis le menu d’un titre ; il reste soumis aux règles et publicités YouTube.")
                Link("Documentation Invidious", destination: URL(string: "https://docs.invidious.io/")!)
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
