import AVFoundation
import AudioToolbox
import Combine
import CryptoKit
import MediaPlayer
import UIKit
import SwiftUI

/// Progressive AVPlayer for immediate network playback, plus the full native
/// effects graph for local/prepared audio. No web view is used for normal music.
@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = ""
    @Published private(set) var loadingProgress: Double?
    @Published private(set) var isStreaming = false
    @Published private(set) var preparingEffects = false
    @Published private(set) var effectsMessage: String?
    @Published private(set) var firstAudioLatency: Double?
    #if DEBUG
    private(set) var artworkFetchCount = 0
    #endif
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var formatLabel = ""
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var sleepDeadline: Date?
    @Published var stopAtEnd = false
    @Published var loopA: Double?
    @Published var loopB: Double?
    @Published var youtubeTrack: Track?
    @Published var unresolvedTrack: Track?
    @Published var error: String?

    let equalizerFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private let library: LibraryStore
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var audioFile: AVAudioFile?
    private var scheduledOffset = 0.0
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?
    private var loadingWatchdog: Task<Void, Never>?
    private let loadingTimeout: TimeInterval
    private let onlineLoader: any OnlineAudioLoading
    private var streamPlayer: AVPlayer?
    private var streamSource: InvidiousStream?
    private var streamObservations: [NSKeyValueObservation] = []
    private var streamEndObservation: NSObjectProtocol?
    private var alternateTask: Task<Void, Never>?
    private var bufferWatchdog: Task<Void, Never>?
    private var effectsTask: Task<Void, Never>?
    private var wantsPlayback = false
    private var usedDirectFallback = false
    private var tryingAlternate = false
    private var beganLoading = Date()
    private var requestedEffects = false
    private var timer: Timer?
    private var lastTick = Date()
    private var sessionID = UUID()
    private var sessionDay = Calendar.current.startOfDay(for: Date())
    private var listeningAccumulator = 0.0
    private var observations: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var resumeAfterInterruption = false
    private var playedIDs = Set<UUID>()
    private var artworkTask: Task<Void, Never>?

    init(library: LibraryStore, loadingTimeout: TimeInterval = 35, onlineLoader: any OnlineAudioLoading = InvidiousAudioLoader()) {
        self.library = library
        self.loadingTimeout = loadingTimeout
        self.onlineLoader = onlineLoader
        engine.attach(node); engine.attach(pitch); engine.attach(equalizer)
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric; band.frequency = equalizerFrequencies[index]
            band.bandwidth = 1; band.bypass = false
        }
        engine.connect(node, to: pitch, format: nil)
        engine.connect(pitch, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
        apply(library.settings)
        configureRemoteCommands()
        observeAudioSession()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if library.settings.restoreQueue {
            queue = library.savedQueue.compactMap { library.track($0) }
            current = library.savedCurrentID.flatMap { library.track($0) }
            duration = current?.duration ?? 0
        }
    }

    func play(_ requested: Track, in tracks: [Track]? = nil) {
        let track = library.add(requested)
        if let tracks {
            var seen = Set<UUID>()
            queue = tracks.map { library.add($0) }.filter { seen.insert($0.id).inserted }
            playedIDs.removeAll()
        }
        if !queue.contains(where: { $0.id == track.id }) { queue.append(track) }
        flushListening()
        loadTask?.cancel(); loadingWatchdog?.cancel(); artworkTask?.cancel()
        alternateTask?.cancel(); bufferWatchdog?.cancel(); effectsTask?.cancel(); stopStreaming()
        generation = UUID()
        node.stop(); engine.stop()
        audioFile = nil; isPlaying = false; isLoading = false
        error = nil; loadingMessage = ""; loadingProgress = nil
        firstAudioLatency = nil; beganLoading = Date(); wantsPlayback = true; usedDirectFallback = false; tryingAlternate = false
        preparingEffects = false; effectsMessage = nil; requestedEffects = false
        current = track; position = 0; duration = track.duration
        formatLabel = ""; loopA = nil; loopB = nil
        sessionID = UUID(); lastTick = Date()
        playedIDs.insert(track.id)
        persistQueue()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if track.source == .youtube { youtubeTrack = track; return }
        if track.source == .unresolved { unresolvedTrack = track; return }
        let nativeURL = library.nativeURL(for: track)
        guard track.source == .invidious || nativeURL != nil else {
            error = "Ce fichier est introuvable. Réassocie une source dans la bibliothèque."
            return
        }
        isLoading = true
        loadingMessage = "Préparation de l’audio…"
        let token = generation
        loadingWatchdog = Task { @MainActor [weak self] in
            guard let timeout = self?.loadingTimeout else { return }
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            guard let self, generation == token, isLoading else { return }
            generation = UUID(); loadTask?.cancel()
            alternateTask?.cancel(); bufferWatchdog?.cancel(); wantsPlayback = false; stopStreaming()
            isLoading = false; loadingMessage = "Chargement interrompu"; loadingProgress = nil
            error = "Le chargement n’a pas abouti en \(Int(timeout.rounded())) s. Le serveur audio peut être bloqué ou trop lent. Réessaie ou change d’instance dans les réglages."
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fileURL: URL
                var reportedBitrate: Int?
                if track.source == .invidious {
                    if let streaming = onlineLoader as? any StreamingAudioLoading {
                        loadingMessage = "Connexion au flux audio…"
                        let resource = try await streaming.playback(track, settings: library.settings, direct: false)
                        try Task.checkCancellation()
                        guard generation == token else { return }
                        switch resource {
                        case .stream(let stream):
                            try startStreaming(stream, token: token)
                            return
                        case .file(let audio): fileURL = audio.fileURL; reportedBitrate = audio.bitrate
                        }
                    } else {
                        let audio = try await onlineLoader.load(track, settings: library.settings, progress: { [weak self] update in
                            Task { @MainActor [weak self] in
                                guard let self, generation == token, isLoading else { return }
                                loadingMessage = update.message; loadingProgress = update.fraction
                            }
                        })
                        fileURL = audio.fileURL; reportedBitrate = audio.bitrate
                    }
                } else if track.source == .remote, let url = nativeURL {
                    fileURL = try await AudioCache.shared.localCopy(of: url)
                } else if let url = nativeURL { fileURL = url }
                else { throw BlusicError.message("Source audio introuvable.") }
                try Task.checkCancellation()
                guard generation == token else { return }
                try startNativeFile(fileURL, track: track, bitrate: reportedBitrate, at: 0, autoplay: true)
            } catch is CancellationError {
                if generation == token { isLoading = false; loadingWatchdog?.cancel(); loadingMessage = ""; loadingProgress = nil }
            } catch {
                guard generation == token else { return }
                isLoading = false; isPlaying = false
                loadingWatchdog?.cancel(); loadingMessage = "Échec du chargement"; loadingProgress = nil
                self.error = "Lecture impossible : \(error.localizedDescription)"
            }
        }
    }

    func toggle() {
        if isLoading { pause(); return }
        if isPlaying { pause(); return }
        guard let current else { if let first = queue.first ?? library.tracks.first { play(first) }; return }
        if current.source == .youtube { youtubeTrack = current; return }
        if let streamPlayer {
            wantsPlayback = true; streamPlayer.playImmediately(atRate: library.settings.playbackRate)
            return
        }
        guard audioFile != nil else { play(current); return }
        do {
            try activateSession()
            if !engine.isRunning { try engine.start() }
            if position >= duration - 0.1 { schedule(at: 0) }
            node.play(); isPlaying = true; lastTick = Date()
            updateNowPlaying()
        } catch { self.error = error.localizedDescription }
    }
    func pause() {
        flushListening()
        if isLoading { generation = UUID(); loadTask?.cancel(); stopStreaming(); isLoading = false }
        wantsPlayback = false; streamPlayer?.pause(); alternateTask?.cancel(); bufferWatchdog?.cancel()
        loadingWatchdog?.cancel(); loadingMessage = ""; loadingProgress = nil
        node.pause(); isPlaying = false
        updateNowPlaying()
    }
    func seek(to seconds: Double) {
        if let streamPlayer {
            let target = max(0, min(seconds, max(0, duration - 0.05)))
            streamPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            position = target; updateNowPlaying(); return
        }
        guard audioFile != nil else { return }
        let playing = isPlaying
        schedule(at: max(0, min(seconds, max(0, duration - 0.02))))
        if playing { node.play() }
        updateNowPlaying()
    }
    func next(userInitiated: Bool = true) {
        if stopAtEnd && !userInitiated { stopAtEnd = false; pause(); return }
        if repeatMode == .one && !userInitiated { seek(to: 0); return }
        guard !queue.isEmpty else { pause(); return }
        let index = queue.firstIndex { $0.id == current?.id } ?? -1
        if shuffle {
            var choices = queue.filter { !playedIDs.contains($0.id) }
            if choices.isEmpty {
                if repeatMode == .off && !userInitiated { pause(); return }
                playedIDs = current.map { Set([$0.id]) } ?? []
                choices = queue.filter { $0.id != current?.id }
            }
            if let chosen = choices.randomElement() { play(chosen) }
            else if repeatMode != .off || userInitiated, let first = queue.first { play(first) }
            else { pause() }
        } else if index + 1 < queue.count { play(queue[index + 1]) }
        else if repeatMode == .all || userInitiated { play(queue[0]) }
        else { pause(); position = duration }
    }
    func previous() {
        if position > 3 { seek(to: 0); return }
        guard !queue.isEmpty else { return }
        let index = queue.firstIndex { $0.id == current?.id } ?? 0
        play(queue[max(0, index - 1)])
    }
    func enqueue(_ track: Track, next: Bool = false) {
        guard track.id != current?.id else { library.notice = "Ce titre est déjà à l’écoute"; return }
        queue.removeAll { $0.id == track.id }
        let index = (queue.firstIndex { $0.id == current?.id } ?? -1) + 1
        if next { queue.insert(track, at: min(index, queue.count)) } else { queue.append(track) }
        persistQueue(); library.notice = next ? "À écouter juste après" : "Ajouté à la file d’attente"
    }
    func removeFromQueue(at offsets: IndexSet) { queue.remove(atOffsets: offsets); persistQueue() }
    func moveQueue(from offsets: IndexSet, to destination: Int) { queue.move(fromOffsets: offsets, toOffset: destination); persistQueue() }
    func clearQueue() { queue = current.map { [$0] } ?? []; persistQueue() }
    func openOfficialPlayer(for track: Track) {
        pause()
        youtubeTrack = track
    }
    func forget(_ id: UUID) {
        if current?.id == id {
            pause(); stopStreaming(); effectsTask?.cancel(); node.stop(); engine.stop(); audioFile = nil; current = nil; position = 0; duration = 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        queue.removeAll { $0.id == id }; persistQueue()
    }
    func setSleep(minutes: Int?) {
        sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0 * 60)) }
        stopAtEnd = false
    }
    func apply(_ settings: AppSettings) {
        pitch.rate = min(2, max(0.5, settings.playbackRate))
        pitch.pitch = min(1200, max(-1200, settings.pitch * 100))
        equalizer.bypass = !settings.equalizerEnabled
        for index in equalizer.bands.indices {
            equalizer.bands[index].gain = settings.equalizer.indices.contains(index) ? min(12, max(-12, settings.equalizer[index])) : 0
        }
        // Headroom avoids clipping with positive EQ boosts.
        let headroom = settings.equalizerEnabled ? max(0, settings.equalizer.max() ?? 0) : 0
        equalizer.globalGain = -headroom
        engine.mainMixerNode.outputVolume = min(1, max(0, settings.volume))
        streamPlayer?.volume = min(1, max(0, settings.volume))
        if let streamPlayer, wantsPlayback, abs(streamPlayer.rate - settings.playbackRate) > 0.001 { streamPlayer.rate = settings.playbackRate }
        if isStreaming, settings.equalizerEnabled || settings.pitch != 0 { prepareNativeEffects() }
        updateNowPlaying()
    }

    private func startNativeFile(_ url: URL, track: Track, bitrate: Int?, at seconds: Double, autoplay: Bool) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw BlusicError.message("Le fichier audio est vide.") }
        audioFile = file
        duration = Double(file.length) / file.processingFormat.sampleRate
        let codec: String
        switch file.fileFormat.streamDescription.pointee.mFormatID {
        case kAudioFormatLinearPCM: codec = "PCM · sans perte"
        case kAudioFormatAppleLossless: codec = "ALAC · sans perte"
        case kAudioFormatFLAC: codec = "FLAC · sans perte"
        case kAudioFormatMPEG4AAC: codec = "AAC"
        case kAudioFormatMPEGLayer3: codec = "MP3"
        default: codec = "Audio natif"
        }
        let rate = String(format: "%g", file.fileFormat.sampleRate / 1000)
        let quality = bitrate.flatMap { $0 > 0 ? " · \(Int((Double($0) / 1000).rounded())) kbit/s" : nil } ?? ""
        formatLabel = track.source == .invidious ? "\(codec)\(quality) · Invidious" : "\(codec) · \(rate) kHz"
        engine.disconnectNodeOutput(node); engine.disconnectNodeOutput(pitch); engine.disconnectNodeOutput(equalizer)
        engine.connect(node, to: pitch, format: file.processingFormat)
        engine.connect(pitch, to: equalizer, format: file.processingFormat)
        engine.connect(equalizer, to: engine.mainMixerNode, format: file.processingFormat)
        try activateSession(); try engine.start()
        schedule(at: min(seconds, max(0, duration - 0.05)))
        stopStreaming()
        if autoplay { node.play() }
        isPlaying = autoplay; wantsPlayback = autoplay; isLoading = false
        loadingWatchdog?.cancel(); loadingMessage = ""; loadingProgress = nil
        lastTick = Date(); updateNowPlaying(loadArtwork: true)
    }

    private func startStreaming(_ source: InvidiousStream, token: UUID, at seconds: Double = 0) throws {
        stopStreaming()
        try activateSession()
        let item = AVPlayerItem(url: source.url)
        item.preferredForwardBufferDuration = 0.5
        item.audioTimePitchAlgorithm = .spectral
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = library.settings.volume
        streamPlayer = player; streamSource = source; isStreaming = true; wantsPlayback = true
        duration = source.duration > 0 ? source.duration : duration
        formatLabel = "AAC · \(Int((Double(source.bitrate) / 1000).rounded())) kbit/s · progressif"
        loadingMessage = "Mise en tampon du flux…"
        streamObservations = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
                Task { @MainActor [weak self] in
                    guard let self, streamPlayer === observed, generation == token else { return }
                    if observed.timeControlStatus == .playing {
                        isPlaying = true; lastTick = Date()
                        if firstAudioLatency != nil { finishLoading() }
                        updateNowPlaying()
                    } else if observed.timeControlStatus == .waitingToPlayAtSpecifiedRate, wantsPlayback {
                        flushListening(); isPlaying = false; isLoading = true
                        loadingMessage = "Mise en tampon du flux…"
                        if bufferWatchdog == nil {
                            bufferWatchdog = Task { @MainActor [weak self] in
                                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                                guard let self, generation == token, isLoading else { return }
                                retryStreamOrFail(token: token)
                            }
                        }
                    }
                }
            },
            item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                guard observed.status == .failed else { return }
                Task { @MainActor [weak self] in self?.retryStreamOrFail(token: token) }
            }
        ]
        streamEndObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, streamPlayer === player, generation == token else { return }
                position = duration; next(userInitiated: false)
            }
        }
        if seconds > 0 { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
        updateNowPlaying(loadArtwork: true)
        player.playImmediately(atRate: library.settings.playbackRate)
        bufferWatchdog?.cancel()
        bufferWatchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, generation == token, isLoading else { return }
            retryStreamOrFail(token: token)
        }
    }

    private func retryStreamOrFail(token: UUID) {
        guard generation == token, wantsPlayback, !tryingAlternate, let current else { return }
        guard !usedDirectFallback, let loader = onlineLoader as? any StreamingAudioLoading else {
            stopStreaming(); isPlaying = false; isLoading = false; wantsPlayback = false
            loadingWatchdog?.cancel(); bufferWatchdog?.cancel()
            error = "Le flux ne démarre pas sur ce réseau. Réessaie ou change d’instance Invidious dans les réglages."
            return
        }
        usedDirectFallback = true
        tryingAlternate = true; bufferWatchdog?.cancel(); bufferWatchdog = nil
        loadingMessage = "Essai d’un autre accès audio…"
        alternateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == token { tryingAlternate = false; alternateTask = nil } }
            do {
                let resource = try await loader.playback(current, settings: library.settings, direct: true)
                try Task.checkCancellation()
                guard generation == token, wantsPlayback else { return }
                switch resource {
                case .stream(let source): try startStreaming(source, token: token, at: position)
                case .file(let audio): try startNativeFile(audio.fileURL, track: current, bitrate: audio.bitrate, at: position, autoplay: true)
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                stopStreaming(); isLoading = false; isPlaying = false; wantsPlayback = false; loadingWatchdog?.cancel()
                self.error = "Lecture impossible : \(error.localizedDescription)"
            }
        }
    }

    private func stopStreaming() {
        streamObservations.removeAll()
        if let observer = streamEndObservation { NotificationCenter.default.removeObserver(observer); streamEndObservation = nil }
        streamPlayer?.pause(); streamPlayer = nil; streamSource = nil; isStreaming = false
    }
    private func finishLoading() {
        isLoading = false; loadingMessage = ""; loadingProgress = nil
        loadingWatchdog?.cancel(); loadingWatchdog = nil; bufferWatchdog?.cancel(); bufferWatchdog = nil
    }

    func prepareNativeEffects() {
        requestedEffects = true
        guard isStreaming, firstAudioLatency != nil, !preparingEffects, let source = streamSource, let current else { return }
        preparingEffects = true; effectsMessage = "Préparation de l’égaliseur et de la tonalité…"
        let token = generation
        effectsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let file = try await AudioCache.shared.localCopy(of: source.url,
                    cacheKey: "invidious:\(current.location):aac:\(source.bitrate)", fileExtension: "m4a", expectedDuration: source.duration,
                    session: InvidiousService.mediaSession)
                await AudioCache.shared.storeInvidiousInfo(track: current, bitrate: source.bitrate, instance: source.instance)
                try Task.checkCancellation()
                guard generation == token, isStreaming else { return }
                let seconds = streamPlayer?.currentTime().seconds ?? position
                let playing = wantsPlayback
                try startNativeFile(file, track: current, bitrate: source.bitrate, at: seconds.isFinite ? seconds : position, autoplay: playing)
                preparingEffects = false; effectsMessage = nil
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                preparingEffects = false; effectsMessage = "La lecture continue ; les effets n’ont pas pu être préparés."
            }
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try session.setActive(true)
    }
    private func schedule(at seconds: Double) {
        guard let file = audioFile else { return }
        generation = UUID()
        let token = generation
        node.stop()
        let start = min(file.length - 1, AVAudioFramePosition(seconds * file.processingFormat.sampleRate))
        let frames = AVAudioFrameCount(min(Int64(UInt32.max), file.length - start))
        scheduledOffset = Double(start) / file.processingFormat.sampleRate
        position = scheduledOffset
        node.scheduleSegment(file, startingFrame: start, frameCount: frames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, generation == token, isPlaying else { return }
                position = duration
                next(userInitiated: false)
            }
        }
    }
    private func tick() {
        if let deadline = sleepDeadline, Date() >= deadline {
            sleepDeadline = nil; pause(); library.notice = "Bonne nuit. Lecture arrêtée."
        }
        guard isPlaying else { lastTick = Date(); return }
        if let streamPlayer {
            let seconds = streamPlayer.currentTime().seconds
            if seconds.isFinite { position = seconds }
            if let itemDuration = streamPlayer.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 { duration = itemDuration }
        } else if let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render) {
            position = min(duration, scheduledOffset + Double(time.sampleTime) / time.sampleRate)
        }
        if firstAudioLatency == nil, position > 0.05 {
            firstAudioLatency = Date().timeIntervalSince(beganLoading)
            finishLoading()
            if isStreaming, requestedEffects || library.settings.equalizerEnabled || library.settings.pitch != 0 { prepareNativeEffects() }
        }
        flushListening(force: false)
        if let a = loopA, let b = loopB, b > a, position >= b { seek(to: a) }
    }
    private func flushListening(force: Bool = true) {
        let now = Date()
        defer { lastTick = now }
        guard isPlaying, let current, current.isNative else { return }
        let elapsed = now.timeIntervalSince(lastTick)
        if elapsed > 0, elapsed < 10 { listeningAccumulator += elapsed }
        guard force || listeningAccumulator >= 5 else { return }
        let today = Calendar.current.startOfDay(for: now)
        if today != sessionDay { sessionDay = today; sessionID = UUID() }
        library.recordListening(track: current, seconds: listeningAccumulator, sessionID: sessionID)
        listeningAccumulator = 0
    }
    private func persistQueue() {
        library.savedQueue = queue.map(\.id); library.savedCurrentID = current?.id
    }
    private func updateNowPlaying(loadArtwork: Bool = false) {
        guard let current, current.isNative else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = current.title
        info[MPMediaItemPropertyArtist] = current.subtitle
        info[MPMediaItemPropertyAlbumTitle] = current.album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? library.settings.playbackRate : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = library.settings.playbackRate
        if loadArtwork, let image = UIImage(named: current.artwork) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if loadArtwork, let url = current.artworkURL {
            artworkTask?.cancel()
            #if DEBUG
            artworkFetchCount += 1
            #endif
            let id = current.id
            artworkTask = Task { [weak self] in
                let data: Data?
                if url.isFileURL { data = try? Data(contentsOf: url) }
                else { data = try? await URLSession.shared.data(from: url).0 }
                guard let self, self.current?.id == id, let data, let image = UIImage(data: data) else { return }
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
    }
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { [weak self] _ in if self?.isPlaying == false { self?.toggle() } }
        register(center.pauseCommand) { [weak self] _ in self?.pause() }
        register(center.togglePlayPauseCommand) { [weak self] _ in self?.toggle() }
        register(center.nextTrackCommand) { [weak self] _ in self?.next() }
        register(center.previousTrackCommand) { [weak self] _ in self?.previous() }
        register(center.changePlaybackPositionCommand) { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: event.positionTime) }
        }
    }
    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
        let target = command.addTarget { event in
            Task { @MainActor in action(event) }
            return .success
        }
        remoteTargets.append((command, target))
    }
    private func observeAudioSession() {
        observations.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    resumeAfterInterruption = isPlaying; pause()
                } else if resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    resumeAfterInterruption = false; toggle()
                }
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pause() }
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !isStreaming, isPlaying else { return }
                let time = position
                pause()
                do { try engine.start(); schedule(at: time); node.play(); isPlaying = true; updateNowPlaying() }
                catch { self.error = error.localizedDescription }
            }
        })
    }
}

actor AudioCache {
    static let shared = AudioCache()
    private struct CachedSource: Codable {
        var bitrate: Int
        var instance: URL
        var expires: Date
    }
    private var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BlusicAudio")
    }
    private func destination(key: String, ext: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension(ext)
    }
    func cachedInvidious(track: Track) -> InvidiousAudio? {
        let metadata = destination(key: "invidious:\(track.location):aac", ext: "json")
        guard let data = try? Data(contentsOf: metadata), let source = try? JSONDecoder().decode(CachedSource.self, from: data),
              source.expires > Date() else { return nil }
        let file = destination(key: "invidious:\(track.location):aac:\(source.bitrate)", ext: "m4a")
        do {
            try validate(file, expectedDuration: track.duration)
            return InvidiousAudio(fileURL: file, bitrate: source.bitrate, instance: source.instance)
        } catch { return nil }
    }
    func storeInvidiousInfo(track: Track, bitrate: Int, instance: URL) {
        let metadata = destination(key: "invidious:\(track.location):aac", ext: "json")
        let source = CachedSource(bitrate: bitrate, instance: instance, expires: Date().addingTimeInterval(bitrate >= 90000 ? 86400 : 600))
        if let data = try? JSONEncoder().encode(source) { try? data.write(to: metadata, options: .atomic) }
    }
    func localCopy(of url: URL, cacheKey: String? = nil, fileExtension: String? = nil,
                   expectedDuration: Double = 0, session: URLSession = .shared,
                   progress: @escaping @Sendable (Double?) -> Void = { _ in }) async throws -> URL {
        guard url.scheme == "https" else { throw BlusicError.message("Seules les sources HTTPS sont acceptées.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data((cacheKey ?? url.absoluteString).utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent(key).appendingPathExtension(fileExtension ?? (url.pathExtension.isEmpty ? "audio" : url.pathExtension))
        if FileManager.default.fileExists(atPath: destination.path) {
            do { try validate(destination, expectedDuration: expectedDuration); progress(1); return destination }
            catch { try? FileManager.default.removeItem(at: destination) }
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if fileExtension == "m4a" { request.setValue("bytes=0-", forHTTPHeaderField: "Range") }
        request.setValue("Blusic/1.1 (iOS; Invidious client)", forHTTPHeaderField: "User-Agent")
        progress(nil)
        let (temp, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BlusicError.message("La source audio n’est pas accessible.")
        }
        if let mime = response.mimeType, mime.hasPrefix("text/") || mime == "application/json" {
            throw BlusicError.message("La source a renvoyé une page d’erreur à la place du fichier audio.")
        }
        let size = (try temp.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= 300_000_000 else { throw BlusicError.message("Ce fichier dépasse la limite de cache de 300 Mo. Importe-le depuis Fichiers.") }
        try Task.checkCancellation()
        try validate(temp, expectedDuration: expectedDuration)
        if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: temp, to: destination) }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        progress(1)
        return destination
    }
    private func validate(_ url: URL, expectedDuration: Double) throws {
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard file.length > 0, duration.isFinite, duration > 0,
              expectedDuration <= 0 || duration >= expectedDuration * 0.8 else {
            throw BlusicError.message("Le fichier audio est vide, tronqué ou plus court que le morceau annoncé.")
        }
    }
}
