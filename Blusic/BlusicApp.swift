import SwiftUI

@main
struct BlusicApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var player: AudioPlayer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = LibraryStore()
        _library = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: AudioPlayer(library: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .tint(library.settings.color)
                .preferredColorScheme(library.settings.appearance == "system" ? nil : library.settings.appearance == "light" ? .light : .dark)
                .onChange(of: library.settings) { _, settings in player.apply(settings) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { library.save() }
                }
        }
    }
}
