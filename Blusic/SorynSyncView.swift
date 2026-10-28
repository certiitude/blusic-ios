import SwiftUI

struct SorynSyncView: View {
    @Environment(LibraryStore.self) private var library
    @State private var pairing = ""
    var body: some View {
        Form {
            Section {
                Label("Ton univers, sur les deux écrans.", systemImage: "desktopcomputer.and.iphone").font(.headline)
                Text("Ouvre Soryn sur Windows → Synchroniser, puis copie son lien d’appairage ici. Les deux appareils doivent être sur le même Wi-Fi privé.")
                SecureField("soryn://pair?…", text: $pairing).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Associer ce PC") { Task { await library.sync.pair(pairing); pairing = "" } }
                    .disabled(pairing.isEmpty || library.sync.busy)
            } header: { Text("Appairage Windows") }
            Section("Synchronisation") {
                if library.sync.paired { LabeledContent("PC", value: library.sync.address) }
                Text(library.sync.status).font(.subheadline).foregroundStyle(.secondary)
                if let date = library.sync.lastSync { LabeledContent("Dernier échange", value: date.formatted(date: .omitted, time: .standard)) }
                if library.sync.busy { ProgressView("Synchronisation…") }
                Button("Synchroniser maintenant") { Task { await library.sync.sync() } }.disabled(!library.sync.paired || library.sync.busy)
                if library.sync.paired { Button("Oublier ce PC", role: .destructive) { library.sync.forget() }.disabled(library.sync.busy) }
            }
            Section("Ce qui est partagé") {
                Text("Titres du catalogue, playlists, favoris, artistes suivis, paroles enregistrées et historique. Les ajouts et retraits sont fusionnés ; en cas de conflit simultané, la version du PC est prioritaire, sauf une modification en cours sur l’iPhone.")
                Text("Les fichiers personnels et les téléchargements audio ne sont pas transférés. Leurs références peuvent apparaître, mais un fichier absent doit être importé sur l’autre appareil. Les préférences audio et la file de lecture restent propres à chaque appareil.")
                Text("Échanges chiffrés AES-GCM sur le réseau local, sans serveur cloud. Synchronisation toutes les 15 secondes quand Soryn est ouvert au premier plan sur l’iPhone et la synchronisation activée sur le PC. L’écoute hors ligne reste indépendante du PC.")
            }.font(.footnote)
        }.navigationTitle("Soryn Windows").navigationBarTitleDisplayMode(.inline)
    }
}
