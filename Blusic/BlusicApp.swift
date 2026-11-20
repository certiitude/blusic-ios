import SwiftUI

@main
struct BlusicApp: App {
    @State private var library: LibraryStore
    @State private var player: AudioPlayer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        let fixture = ProcessInfo.processInfo.arguments.contains("--blusic-fixture") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let store = LibraryStore(inMemory: fixture)
        if fixture { store.settings.offlinePlaybackOnly = true }
        if fixture && ProcessInfo.processInfo.arguments.contains("--blusic-light") { store.settings.appearance = "light" }
        #else
        let store = LibraryStore()
        #endif
        do { try BundledRelayConfiguration.load()?.install(in: store) }
        catch { store.notice = "La configuration du relais n’a pas pu être enregistrée dans le trousseau. \(error.localizedDescription)" }
        _library = State(initialValue: store)
        _player = State(initialValue: AudioPlayer(library: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .transformEnvironment(\.dynamicTypeSize) { size in
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--blusic-large-text") { size = .xxxLarge }
                    #endif
                }
                .task { await library.downloads.waitUntilReady() }
                .task(id: scenePhase) { if scenePhase == .active { await library.sync.runWhileActive() } }
                .task(id: scenePhase) { if scenePhase == .active { await library.account.runWhileActive() } }
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
