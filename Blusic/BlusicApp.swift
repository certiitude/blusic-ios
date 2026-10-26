import SwiftUI

@main
struct BlusicApp: App {
    @State private var library: LibraryStore
    @State private var player: AudioPlayer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = LibraryStore()
        do { try BundledRelayConfiguration.load()?.install(in: store) }
        catch { store.notice = "La configuration du relais n’a pas pu être enregistrée dans le trousseau. \(error.localizedDescription)" }
        _library = State(initialValue: store)
        _player = State(initialValue: AudioPlayer(library: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .tint(library.settings.color)
                .preferredColorScheme(library.settings.appearance == "system" ? nil : library.settings.appearance == "light" ? .light : .dark)
                .onChange(of: library.settings) { _, settings in player.apply(settings) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { library.save() }
                }
        }
    }
}
