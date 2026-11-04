import SwiftUI

struct SorynAccountView: View {
    @Environment(LibraryStore.self) private var library
    @State private var username = ""
    @State private var password = ""
    @State private var creating = false
    @State private var deleting = false
    var body: some View {
        Form {
            Section {
                Label("Ta musique. Avec ou sans compte.", systemImage: "person.crop.circle").font(.headline)
                Text("Le compte est facultatif et sert uniquement à synchroniser ta bibliothèque entre iPhone et PC, même sur des réseaux différents. Aucune connexion n’est nécessaire pour écouter, importer ou télécharger.")
            }
            Section(library.account.signedIn ? "Connecté : \(library.account.displayName)" : "Connexion facultative") {
                if library.account.signedIn {
                    Text(library.account.status).font(.subheadline).foregroundStyle(.secondary)
                    if let date = library.account.lastSync { LabeledContent("Dernier échange", value: date.formatted(date: .omitted, time: .standard)) }
                    Button("Synchroniser maintenant") { Task { await library.account.sync() } }.disabled(library.account.busy)
                    Button("Se déconnecter") { Task { await library.account.logout() } }.disabled(library.account.busy)
                } else {
                    Picker("Action", selection: $creating) { Text("Se connecter").tag(false); Text("Créer un compte").tag(true) }.pickerStyle(.segmented)
                    TextField("Pseudo", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Mot de passe · 12 caractères minimum", text: $password).textContentType(creating ? .newPassword : .password)
                    Button(creating ? "Créer et synchroniser" : "Se connecter et synchroniser") {
                        let name = username, secret = password; password = ""
                        Task { await library.account.authenticate(username: name, password: secret, create: creating) }
                    }.disabled(username.isEmpty || password.count < 12 || library.account.busy)
                    Text(library.account.status).font(.caption).foregroundStyle(.secondary)
                }
                if library.account.busy { ProgressView("Échange en cours…") }
            }
            Section("Ton choix, tes données") {
                Text("La connexion fusionne les références des titres, playlists, favoris, artistes suivis, paroles enregistrées et historique avec le compte. Elle n’efface pas la bibliothèque locale. Les fichiers audio, téléchargements, réglages et lecture en cours restent sur chaque appareil.")
                Text("HTTPS pour les échanges, mots de passe hachés côté serveur, jeton de session dans le trousseau. Le serveur conserve les métadonnées : ce n’est pas du chiffrement de bout en bout. Sans e-mail, il n’y a pas de récupération automatique du mot de passe.")
                Text("Le service nécessite une base persistante configurée. S’il est indisponible, l’écoute et la bibliothèque locales restent utilisables. La synchronisation fonctionne toutes les 30 secondes tant que l’app est au premier plan.")
                NavigationLink { SorynSyncView() } label: { Label("Autre choix : même Wi-Fi, sans compte", systemImage: "wifi") }
            }.font(.footnote)
            if library.account.signedIn {
                Section("Supprimer le compte") {
                    SecureField("Confirmer avec ton mot de passe", text: $password).textContentType(.password)
                    Button("Supprimer mes données du serveur", role: .destructive) { deleting = true }.disabled(password.isEmpty || library.account.busy)
                    Text("Les sessions et données du compte seront supprimées du serveur. Les fichiers et la bibliothèque sur cet iPhone seront conservés.").font(.caption)
                }
            }
        }
        .navigationTitle("Compte facultatif").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Supprimer définitivement le compte et ses données serveur ?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Supprimer le compte", role: .destructive) { let secret = password; password = ""; Task { await library.account.deleteAccount(password: secret) } }
            Button("Annuler", role: .cancel) { password = "" }
        }
    }
}

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
