import SwiftUI

struct PlayerView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--blusic-lyrics") { return "lyrics" }
        #endif
        return "artwork"
    }()
    @State private var showSound = false
    @State private var showSleep = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background
                if mode == "lyrics", let track = player.current {
                    lyricsLayout(track)
                } else {
                  ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Capsule().fill(.white.opacity(0.28)).frame(width: 36, height: 5).padding(.top, 12)
                        header.padding(.top, 10).padding(.bottom, 18)
                        if let track = player.current {
                            let size = min(geometry.size.width - 64, max(160, geometry.size.height * 0.30))
                            Group {
                                if mode == "queue" { queue.frame(height: size + 20) }
                                else {
                                    ArtworkView(track: track, size: size, radius: library.settings.artworkRadius + 5)
                                        .shadow(color: .black.opacity(0.3), radius: 25, y: 17)
                                        .scaleEffect(player.isPlaying || !library.settings.animateArtwork ? 1 : 0.91)
                                        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: player.isPlaying)
                                        .frame(maxWidth: .infinity).frame(height: size + 20)
                                }
                            }.padding(.bottom, 20)

                            metadata(track).padding(.bottom, 17)
                            if player.isLoading {
                                VStack(spacing: 8) {
                                    if let fraction = player.loadingProgress { ProgressView(value: fraction).tint(.white) }
                                    HStack {
                                        Text(player.loadingMessage).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                                        Spacer(minLength: 6)
                                        if let fraction = player.loadingProgress { Text("\(Int(fraction * 100)) %").font(.caption.monospacedDigit()) }
                                        Button("Annuler") { player.pause() }.font(.caption.bold())
                                    }
                                }.padding(.bottom, 16)
                            } else if let error = player.error {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(error).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(4)
                                    Button("Réessayer") { player.play(track) }.font(.caption.bold())
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 14)
                            }
                            progress.padding(.bottom, 12)
                            transport.padding(.bottom, 16)
                            HStack(spacing: 12) {
                                Image(systemName: "speaker.fill").font(.system(size: 11))
                                Slider(value: Binding(get: { Double(library.settings.volume) }, set: { library.settings.volume = Float($0) }), in: 0...1)
                                    .tint(.white.opacity(0.75)).accessibilityLabel("Volume du lecteur")
                                Image(systemName: "speaker.wave.3.fill").font(.system(size: 13))
                            }.foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 7).padding(.bottom, 19)
                            tools
                            if let deadline = player.sleepDeadline {
                                HStack(spacing: 6) {
                                    Image(systemName: "moon.zzz.fill")
                                    Text("Arrêt à \(deadline.formatted(date: .omitted, time: .shortened))")
                                }.font(.caption).foregroundStyle(.white.opacity(0.6)).padding(.top, 14)
                            } else if player.stopAtEnd {
                                Text("Arrêt à la fin du titre").font(.caption).foregroundStyle(.white.opacity(0.6)).padding(.top, 14)
                            }
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 20).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height, alignment: .top)
                  }
                }
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .sheet(isPresented: $showSound) { NavigationStack { SoundSettingsView() }.presentationDetents([.large]) }
        .sheet(isPresented: $showSleep) { SleepTimerView().presentationDetents([.height(380)]) }
    }
    private func lyricsLayout(_ track: Track) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.28)).frame(width: 36, height: 5).padding(.top, 12)
            header.padding(.top, 6).padding(.bottom, 8)
            HStack(spacing: 12) {
                ArtworkView(track: track, size: 46, radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
                IconButton(symbol: library.isFavorite(track) ? "heart.fill" : "heart", label: "Favori") { library.toggleFavorite(track) }
            }.padding(.bottom, 8)
            LyricsView(track: track).frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1)
                .accessibilityIdentifier("expanded-lyrics")
            if player.isLoading {
                HStack { ProgressView().tint(.white); Text(player.loadingMessage).font(.caption).lineLimit(1) }.padding(.vertical, 4)
            } else if let error = player.error {
                HStack {
                    Text(error).font(.caption).lineLimit(2)
                    Button("Réessayer") { player.play(track) }.font(.caption.bold())
                }.padding(.vertical, 4)
            }
            progress.padding(.top, 4)
            transport.frame(height: 72)
            tools.padding(.bottom, 8)
        }.padding(.horizontal, 28)
    }
    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.04, green: 0.09, blue: 0.14)
                ArtworkView(track: player.current, size: 192, radius: 0, maximumPixels: 256)
                    .blur(radius: 18, opaque: true)
                    .scaleEffect(max(geometry.size.width, geometry.size.height) / 192 * 1.2)
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.5)
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            }.clipped()
        }.ignoresSafeArea()
    }
    private var header: some View {
        HStack {
            IconButton(symbol: "chevron.down", label: "Fermer le lecteur") { dismiss() }
            Spacer()
            VStack(spacing: 5) {
                Text(mode == "lyrics" ? "CHAQUE MOT COMPTE" : mode == "queue" ? "LA SUITE DU VOYAGE" : "À L’ÉCOUTE")
                    .font(.system(size: 9, weight: .bold)).tracking(2)
                Text(player.current?.album.isEmpty == false ? player.current!.album : "Ta musique, simplement")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            Menu {
                if let track = player.current { TrackActions(track: track) }
                Button { showSleep = true } label: { Label("Minuterie de sommeil", systemImage: "moon.zzz") }
                Button { showSound = true } label: { Label("Réglages audio", systemImage: "slider.horizontal.3") }
                if player.loopA == nil { Button("Définir le début de boucle A") { player.loopA = player.position } }
                else if player.loopB == nil { Button("Définir la fin de boucle B") { if player.position > (player.loopA ?? 0) { player.loopB = player.position } } }
                else { Button("Désactiver la boucle A–B") { player.loopA = nil; player.loopB = nil } }
            } label: { Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44) }.tint(.white)
                .accessibilityLabel("Options de lecture")
        }.padding(.horizontal, -10)
    }
    private func metadata(_ track: Track) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(track.title).font(.system(size: 24, weight: .bold)).tracking(-0.5).lineLimit(1).minimumScaleFactor(0.7)
                Button {
                    if let artistID = track.artistID { library.requestedArtist = MusicArtist(id: artistID, name: track.subtitle) }
                } label: {
                    Text(track.subtitle).font(.system(size: 17)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                }.buttonStyle(.plain).disabled(track.artistID == nil)
                HStack(spacing: 5) {
                    Image(systemName: track.isOffline ? "checkmark.circle" : "waveform")
                    Text(player.formatLabel.isEmpty ? track.sourceLabel : player.formatLabel)
                    if player.loopB != nil { Text("· BOUCLE A–B") }
                }.font(.system(size: 9, weight: .semibold)).tracking(0.7).foregroundStyle(.white.opacity(0.45)).padding(.top, 3)
                if let seconds = player.firstAudioLatency {
                    Text(String(format: "Démarrage : %.1f s", seconds)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                }
                if let status = player.upcomingPreparationStatus {
                    Text(status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            IconButton(symbol: library.isFavorite(track) ? "heart.fill" : "heart", label: "Favori") { library.toggleFavorite(track) }
                .foregroundStyle(library.isFavorite(track) ? library.settings.color : .white.opacity(0.8))
        }
    }
    private var progress: some View {
        PlaybackProgressView()
    }
    private var transport: some View {
        HStack {
            IconButton(symbol: "shuffle", label: player.shuffle ? "Désactiver l’aléatoire" : "Lecture aléatoire") { player.shuffle.toggle(); library.haptic() }
                .foregroundStyle(player.shuffle ? library.settings.color : .white.opacity(0.45))
            Spacer(minLength: 5)
            IconButton(symbol: "backward.end.fill", label: "Titre précédent") { player.previous() }.font(.title)
            Spacer(minLength: 5)
            Button { player.toggle(); library.haptic() } label: {
                ZStack {
                    Circle().fill(.white.opacity(0.95)).frame(width: 66, height: 66)
                    if player.isLoading { Image(systemName: "xmark").font(.system(size: 22, weight: .semibold)).foregroundStyle(.black) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 27, weight: .semibold)).foregroundStyle(.black).offset(x: player.isPlaying ? 0 : 2) }
                }
            }.buttonStyle(.plain).accessibilityLabel(player.isLoading ? "Annuler le chargement" : player.isPlaying ? "Pause" : "Lire")
            Spacer(minLength: 5)
            IconButton(symbol: "forward.end.fill", label: "Titre suivant") { player.next() }
            Spacer(minLength: 5)
            IconButton(symbol: player.repeatMode.icon, label: "Répétition : \(player.repeatMode.rawValue)") { player.repeatMode.cycle(); library.haptic() }
                .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.45) : library.settings.color)
        }.padding(.horizontal, -6)
    }
    private var tools: some View {
        HStack {
            IconButton(symbol: "quote.bubble", label: "Paroles") { mode = mode == "lyrics" ? "artwork" : "lyrics" }
                .background(mode == "lyrics" ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 13))
            Spacer()
            IconButton(symbol: "slider.horizontal.3", label: "Égaliseur, tonalité et vitesse") { showSound = true }
            Spacer()
            AirPlayPicker().frame(width: 44, height: 44).accessibilityLabel("AirPlay et sortie audio")
            Spacer()
            IconButton(symbol: "list.bullet", label: "File d’attente") { mode = mode == "queue" ? "artwork" : "queue" }
                .background(mode == "queue" ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 13))
        }.foregroundStyle(.white.opacity(0.7))
    }
    private var queue: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File d’attente").font(.title3.bold())
                Spacer()
                Button("Vider") { player.clearQueue() }.font(.caption).tint(.white.opacity(0.6))
            }
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { _, track in
                    TrackRow(track: track, context: player.queue).listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)).listRowBackground(Color.clear)
                }.onDelete { player.removeFromQueue(at: $0) }.onMove { player.moveQueue(from: $0, to: $1) }
            }.listStyle(.plain).scrollContentBackground(.hidden).environment(\.editMode, .constant(.active))
        }
    }
}

private struct PlaybackProgressView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    var body: some View {
        VStack(spacing: 3) {
            Slider(value: Binding(get: { scrubbing ? scrubPosition : min(player.position, max(0.01, player.duration)) }, set: { scrubPosition = $0 }),
                   in: 0...max(0.01, player.duration), onEditingChanged: { editing in
                if editing { scrubPosition = player.position; scrubbing = true }
                else { scrubbing = false; player.seek(to: scrubPosition) }
            }).tint(.white).disabled(player.current?.isNative != true).accessibilityLabel("Position de lecture")
            HStack {
                Text((scrubbing ? scrubPosition : player.position).clock)
                Spacer()
                Text("−" + max(0, player.duration - (scrubbing ? scrubPosition : player.position)).clock)
            }.font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
        }
    }
}

struct SleepTimerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 23) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 30)).foregroundStyle(.indigo).padding(.top, 30)
            Text("La musique s’endort avec toi.").font(.title3.bold())
            HStack(spacing: 12) {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button { player.setSleep(minutes: minutes); dismiss() } label: {
                        VStack(spacing: 5) { Text("\(minutes)").font(.title2.bold()); Text("min").font(.caption) }.frame(maxWidth: .infinity).padding(.vertical, 16).surface(radius: 16)
                    }.buttonStyle(.plain)
                }
            }
            Button("À la fin du titre") { player.setSleep(minutes: nil); player.stopAtEnd = true; dismiss() }
            Button("Désactiver la minuterie", role: .destructive) { player.setSleep(minutes: nil); dismiss() }.font(.subheadline)
            Spacer(minLength: 0)
        }.padding(.horizontal, 24).frame(maxWidth: .infinity).background(Palette.background)
    }
}
