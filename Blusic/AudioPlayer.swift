import AVFoundation
import AudioToolbox
import Observation
import CryptoKit
import MediaPlayer
import UIKit
import SwiftUI

/// Progressive AVPlayer for immediate network playback, plus the full native
/// effects graph for local/prepared audio. No web view is used for normal music.
@MainActor
@Observable
final class AudioPlayer {
    private(set) var current: Track?
    private(set) var queue: [Track] = []
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var loadingMessage = ""
    private(set) var loadingProgress: Double?
    private(set) var isStreaming = false
    private(set) var preparingEffects = false
    private(set) var effectsMessage: String?
    private(set) var firstAudioLatency: Double?
    private(set) var isTransitioning = false
    #if DEBUG
    private(set) var artworkFetchCount = 0
    #endif
    private(set) var position = 0.0
    private(set) var duration = 0.0
    private(set) var formatLabel = ""
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var sleepDeadline: Date?
    var stopAtEnd = false
    var loopA: Double?
    var loopB: Double?
    var youtubeTrack: Track?
    var unresolvedTrack: Track?
    var error: String?

    let equalizerFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private let library: LibraryStore
    private var engine = AVAudioEngine()
    private var node = AVAudioPlayerNode()
    private var varispeed = AVAudioUnitVarispeed()
    private var pitch = AVAudioUnitTimePitch()
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private struct FadingDeck {
        var volume: @MainActor (Float) -> Void
        var stop: @MainActor () -> Void
        var remaining: @MainActor () -> Double
        var active: @MainActor () -> Bool
        var baseGain: Float
    }
    private var outgoing: FadingDeck?
    private var fadeTask: Task<Void, Never>?
    private var incomingGain: Float = 1
    private var outgoingGain: Float = 1
    private var automaticFadeID: UUID?
    private var audioFile: AVAudioFile?
    private var scheduledOffset = 0.0
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?
    private var loadingWatchdog: Task<Void, Never>?
    private let loadingTimeout: TimeInterval
    private let streamBufferTimeout: TimeInterval
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
    @ObservationIgnored private var lastStreamFailure: String?
    @ObservationIgnored private var fileFallbackURLs = Set<URL>()
    private var beganLoading = Date()
    private var requestedEffects = false
    private var declaredDuration = 0.0
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

    #if DEBUG
    var overlappingPlaybackCount: Int { (isPlaying ? 1 : 0) + (outgoing?.active() == true ? 1 : 0) }
    #endif

    init(library: LibraryStore, loadingTimeout: TimeInterval = 20, streamBufferTimeout: TimeInterval = 4, onlineLoader: any OnlineAudioLoading = InvidiousAudioLoader()) {
        self.library = library
        self.loadingTimeout = loadingTimeout
        self.streamBufferTimeout = streamBufferTimeout
        self.onlineLoader = onlineLoader
        wireGraph()
        apply(library.settings)
        configureRemoteCommands()
        observeAudioSession()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
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

    private func wireGraph() {
        engine.attach(node); engine.attach(varispeed); engine.attach(pitch); engine.attach(equalizer)
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric; band.frequency = equalizerFrequencies[index]
            band.bandwidth = 1; band.bypass = false
        }
        engine.connect(node, to: varispeed, format: nil)
        engine.connect(varispeed, to: pitch, format: nil)
        engine.connect(pitch, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
    }

    func play(_ requested: Track, in tracks: [Track]? = nil) {
        let track = library.add(requested)
        if let tracks {
            var seen = Set<UUID>()
            queue = library.add(tracks).filter { seen.insert($0.id).inserted }
            playedIDs.removeAll()
        }
        if !queue.contains(where: { $0.id == track.id }) { queue.append(track) }
        flushListening()
        retainOutgoingForFade(nextID: track.id)
        loadTask?.cancel(); loadingWatchdog?.cancel(); artworkTask?.cancel()
        alternateTask?.cancel(); bufferWatchdog?.cancel(); effectsTask?.cancel(); stopStreaming()
        generation = UUID()
        node.stop(); engine.stop()
        audioFile = nil; isPlaying = false; isLoading = false
        error = nil; loadingMessage = ""; loadingProgress = nil
        firstAudioLatency = nil; beganLoading = Date(); wantsPlayback = true; usedDirectFallback = false; tryingAlternate = false; lastStreamFailure = nil
        fileFallbackURLs.removeAll()
        preparingEffects = false; effectsMessage = nil; requestedEffects = false
        automaticFadeID = nil
        current = track; position = 0; duration = track.duration
        declaredDuration = track.duration
        formatLabel = ""; loopA = nil; loopB = nil
        sessionID = UUID(); lastTick = Date()
        playedIDs.insert(track.id)
        persistQueue()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if track.source == .youtube { youtubeTrack = track; return }
        if track.source == .unresolved { unresolvedTrack = track; return }
        let nativeURL = library.nativeURL(for: track)
        guard track.source == .invidious || track.source == .catalogReference || nativeURL != nil else {
            cancelTransition()
            error = "Ce fichier est introuvable. Réassocie une source dans la bibliothèque."
            return
        }
        isLoading = true
        loadingMessage = "Préparation de l’audio…"
        let token = generation
        loadingWatchdog = Task { @MainActor [weak self] in
            guard let self else { return }
            let timeout = onlineLoader is InvidiousAudioLoader && ["auto", "youtubei"].contains(library.settings.audioSourceMode) ? max(loadingTimeout, 50) : loadingTimeout
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            guard generation == token, isLoading else { return }
            generation = UUID(); loadTask?.cancel()
            alternateTask?.cancel(); bufferWatchdog?.cancel(); wantsPlayback = false; stopStreaming()
            cancelTransition()
            isLoading = false; loadingMessage = "Chargement interrompu"; loadingProgress = nil
            error = "Le chargement n’a pas abouti en \(Int(timeout.rounded())) s. Réessaie ou change d’accès dans Réglages → Sources audio."
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                var playingTrack = track
                if track.source == .catalogReference {
                    loadingMessage = "Association au catalogue YouTube Music…"
                    do {
                        let matched = try await MusicCatalogService().match(track)
                        try Task.checkCancellation()
                        guard generation == token else { return }
                        library.replaceSource(of: track.id, with: matched)
                        playingTrack = library.track(track.id) ?? matched
                        current = playingTrack; declaredDuration = playingTrack.duration; duration = playingTrack.duration
                        queue = queue.map { $0.id == track.id ? playingTrack : $0 }
                    } catch {
                        guard generation == token, !Task.isCancelled else { return }
                        isLoading = false; loadingWatchdog?.cancel(); cancelTransition(); unresolvedTrack = track
                        return
                    }
                }
                let fileURL: URL
                var reportedBitrate: Int?
                var reportedProvider: String?
                if playingTrack.source == .invidious {
                    if let streaming = onlineLoader as? any StreamingAudioLoading {
                        loadingMessage = "Connexion au flux audio…"
                        let resource = try await streaming.playback(playingTrack, settings: library.settings, direct: false)
                        try Task.checkCancellation()
                        guard generation == token else { return }
                        switch resource {
                        case .stream(let stream):
                            try startStreaming(stream, token: token)
                            return
                        case .file(let audio):
                            fileURL = audio.fileURL; reportedBitrate = audio.bitrate
                            reportedProvider = audio.provider
                            if declaredDuration <= 0, let seconds = audio.duration, seconds > 0 { declaredDuration = seconds }
                        }
                    } else {
                        let audio = try await onlineLoader.load(playingTrack, settings: library.settings, progress: { [weak self] update in
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
                try startNativeFile(fileURL, track: playingTrack, bitrate: reportedBitrate, at: 0, autoplay: true, provider: reportedProvider)
            } catch is CancellationError {
                if generation == token { isLoading = false; loadingWatchdog?.cancel(); cancelTransition(); loadingMessage = ""; loadingProgress = nil }
            } catch {
                guard generation == token else { return }
                isLoading = false; isPlaying = false
                cancelTransition()
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
            if position >= duration - 0.1 {
                streamPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero); position = 0
            }
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
        cancelTransition()
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
        let rate = min(2, max(0.5, settings.playbackRate))
        varispeed.bypass = !settings.usesLinkedSpeedAndPitch || abs(rate - 1) < 0.0001
        varispeed.rate = settings.usesLinkedSpeedAndPitch ? rate : 1
        pitch.bypass = settings.usesLinkedSpeedAndPitch
        pitch.rate = settings.usesLinkedSpeedAndPitch ? 1 : rate
        pitch.pitch = settings.usesLinkedSpeedAndPitch ? 0 : min(1200, max(-1200, settings.pitch * 100))
        pitch.overlap = 16
        equalizer.bypass = !settings.equalizerEnabled
        for index in equalizer.bands.indices {
            equalizer.bands[index].gain = settings.equalizer.indices.contains(index) ? min(12, max(-12, settings.equalizer[index])) : 0
        }
        // Headroom avoids clipping with positive EQ boosts.
        let headroom = settings.equalizerEnabled ? max(0, settings.equalizer.max() ?? 0) : 0
        equalizer.globalGain = -headroom
        if !settings.usesCrossfade, outgoing != nil { cancelTransition() }
        setIncomingGain(incomingGain)
        outgoing?.volume(min(1, max(0, settings.volume)) * outgoingGain)
        if let streamPlayer, wantsPlayback, abs(streamPlayer.rate - settings.playbackRate) > 0.001 { streamPlayer.rate = settings.playbackRate }
        let algorithm: AVAudioTimePitchAlgorithm = settings.usesLinkedSpeedAndPitch ? .varispeed : .spectral
        if let item = streamPlayer?.currentItem, item.audioTimePitchAlgorithm != algorithm { item.audioTimePitchAlgorithm = algorithm }
        if isStreaming, settings.needsPreparedEffects { prepareNativeEffects() }
        updateNowPlaying()
    }

    private func setIncomingGain(_ gain: Float) {
        incomingGain = min(1, max(0, gain))
        let volume = min(1, max(0, library.settings.volume)) * incomingGain
        engine.mainMixerNode.outputVolume = volume
        streamPlayer?.volume = volume
    }
    private func cancelTransition(restoreVolume: Bool = true) {
        fadeTask?.cancel(); fadeTask = nil
        outgoing?.stop(); outgoing = nil; outgoingGain = 0; isTransitioning = false
        if restoreVolume { setIncomingGain(1) }
    }
    private func retainOutgoingForFade(nextID: UUID) {
        let actualVolume = streamPlayer?.volume ?? engine.mainMixerNode.outputVolume
        cancelTransition(restoreVolume: false)
        guard library.settings.usesCrossfade, isPlaying, current?.id != nextID else { incomingGain = 1; return }
        let oldDuration = duration
        let oldRate = Double(max(0.5, library.settings.playbackRate))
        let baseGain = min(1, max(0, actualVolume / max(0.001, library.settings.volume)))
        if let player = streamPlayer {
            outgoing = FadingDeck(volume: { player.volume = $0 }, stop: { player.pause() }, remaining: {
                let seconds = player.currentTime().seconds
                return seconds.isFinite ? max(0, oldDuration - seconds) / oldRate : 0
            }, active: { player.timeControlStatus == .playing }, baseGain: baseGain)
            stopStreaming(pause: false)
        } else if let oldFile = audioFile, node.isPlaying {
            let oldEngine = engine, oldNode = node, offset = scheduledOffset
            let sampleRate = oldFile.processingFormat.sampleRate
            outgoing = FadingDeck(volume: { oldEngine.mainMixerNode.outputVolume = $0 }, stop: {
                oldNode.stop(); oldEngine.stop(); _ = oldFile
            }, remaining: {
                guard let render = oldNode.lastRenderTime, let time = oldNode.playerTime(forNodeTime: render) else { return 0 }
                return max(0, oldDuration - offset - Double(time.sampleTime) / sampleRate) / oldRate
            }, active: { oldEngine.isRunning && oldNode.isPlaying }, baseGain: baseGain)
            engine = AVAudioEngine(); node = AVAudioPlayerNode(); varispeed = AVAudioUnitVarispeed()
            pitch = AVAudioUnitTimePitch(); equalizer = AVAudioUnitEQ(numberOfBands: 10)
            wireGraph()
        }
        incomingGain = outgoing == nil ? 1 : 0
        outgoingGain = baseGain
        isTransitioning = outgoing != nil
        apply(library.settings)
    }
    private func beginCrossfade() {
        guard let deck = outgoing, fadeTask == nil else { return }
        let seconds = min(library.settings.crossfadeSeconds, max(0.15, deck.remaining()))
        let began = Date()
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let fraction = min(1, Date().timeIntervalSince(began) / seconds)
                setIncomingGain(Float(fraction))
                outgoingGain = deck.baseGain * Float(1 - fraction)
                deck.volume(library.settings.volume * outgoingGain)
                if fraction >= 1 {
                    deck.stop(); outgoing = nil; isTransitioning = false; outgoingGain = 0; fadeTask = nil
                    return
                }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
    }

    private func startNativeFile(_ url: URL, track: Track, bitrate: Int?, at seconds: Double, autoplay: Bool, provider: String? = nil) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw BlusicError.message("Le fichier audio est vide.") }
        audioFile = file
        duration = PlaybackDuration.effective(declared: declaredDuration, measured: Double(file.length) / file.processingFormat.sampleRate)
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
        formatLabel = track.source == .invidious ? "\(codec)\(quality) · \(provider ?? "cache audio")" : "\(codec) · \(rate) kHz"
        engine.disconnectNodeOutput(node); engine.disconnectNodeOutput(varispeed); engine.disconnectNodeOutput(pitch); engine.disconnectNodeOutput(equalizer)
        engine.connect(node, to: varispeed, format: file.processingFormat)
        engine.connect(varispeed, to: pitch, format: file.processingFormat)
        engine.connect(pitch, to: equalizer, format: file.processingFormat)
        engine.connect(equalizer, to: engine.mainMixerNode, format: file.processingFormat)
        try activateSession(); try engine.start()
        schedule(at: min(seconds, max(0, duration - 0.05)))
        stopStreaming()
        setIncomingGain(incomingGain)
        if autoplay { node.play() }
        isPlaying = autoplay; wantsPlayback = autoplay; isLoading = false
        loadingWatchdog?.cancel(); loadingMessage = ""; loadingProgress = nil
        lastTick = Date(); updateNowPlaying(loadArtwork: true)
    }

    private func startStreaming(_ source: InvidiousStream, token: UUID, at seconds: Double = 0) throws {
        stopStreaming()
        try activateSession()
        let prepared = PreparedAudioCache.shared.take(source.url)
        let item = prepared?.currentItem ?? AVPlayerItem(url: source.url)
        item.preferredForwardBufferDuration = 0.5
        let algorithm: AVAudioTimePitchAlgorithm = library.settings.usesLinkedSpeedAndPitch ? .varispeed : .spectral
        if item.audioTimePitchAlgorithm != algorithm { item.audioTimePitchAlgorithm = algorithm }
        let player = prepared ?? AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = library.settings.volume * incomingGain
        streamPlayer = player; streamSource = source; isStreaming = true; wantsPlayback = true
        if declaredDuration <= 0, source.duration > 0 { declaredDuration = source.duration }
        duration = PlaybackDuration.effective(declared: declaredDuration, measured: source.duration)
        formatLabel = "AAC · \(Int((Double(source.bitrate) / 1000).rounded())) kbit/s · \(source.providerLabel)"
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
                                do { try await Task.sleep(for: .seconds(self?.streamBufferTimeout ?? 4)) } catch { return }
                                guard let self, generation == token, isLoading else { return }
                                retryStreamOrFail(token: token)
                            }
                        }
                    }
                }
            },
            item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                guard observed.status == .failed else { return }
                let failure = observed.error as NSError?
                let code = failure.map { " (\($0.domain) \($0.code))" } ?? ""
                let message = (failure?.localizedDescription ?? "Le lecteur n’a pas pu ouvrir le flux.") + code
                Task { @MainActor [weak self] in
                    guard let self, generation == token else { return }
                    lastStreamFailure = "\(source.providerLabel) : \(message)"
                    retryStreamOrFail(token: token)
                }
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
            do { try await Task.sleep(for: .seconds(self?.streamBufferTimeout ?? 4)) } catch { return }
            guard let self, generation == token, isLoading else { return }
            retryStreamOrFail(token: token)
        }
    }

    private func retryStreamOrFail(token: UUID) {
        guard generation == token, wantsPlayback, !tryingAlternate, let current else { return }
        // CFNetwork may fetch a valid signed AAC while AVPlayer's remote loader
        // rejects it. Preserve this usable source and try a validated local file
        // before replacing it with an unavailable community relay.
        if let loader = onlineLoader as? any StreamingAudioLoading, let source = streamSource,
           fileFallbackURLs.count < 2, fileFallbackURLs.insert(source.url).inserted {
            tryingAlternate = true; bufferWatchdog?.cancel(); bufferWatchdog = nil
            streamPlayer?.pause()
            loadingMessage = "Préparation d’un accès compatible iOS…"
            alternateTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let audio = try await loader.prepareFile(source, for: current)
                    try Task.checkCancellation()
                    guard generation == token, wantsPlayback else { return }
                    tryingAlternate = false; alternateTask = nil
                    try startNativeFile(audio.fileURL, track: current, bitrate: audio.bitrate, at: position, autoplay: true)
                } catch {
                    guard generation == token, !Task.isCancelled, wantsPlayback else { return }
                    tryingAlternate = false; alternateTask = nil
                    lastStreamFailure = (lastStreamFailure.map { $0 + "\n" } ?? "") + "Fichier \(source.providerLabel) : \(error.localizedDescription)"
                    retryStreamOrFail(token: token)
                }
            }
            return
        }
        guard !usedDirectFallback, let loader = onlineLoader as? any StreamingAudioLoading else {
            if let loader = onlineLoader as? any StreamingAudioLoading {
                let settings = library.settings
                Task { await loader.invalidate(current, settings: settings) }
            }
            stopStreaming(); isPlaying = false; isLoading = false; wantsPlayback = false
            cancelTransition()
            loadingWatchdog?.cancel(); bufferWatchdog?.cancel()
            error = "Le flux ne démarre pas sur ce réseau. Réessaie ou change d’accès dans Réglages → Sources audio."
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
                await loader.invalidate(current, settings: library.settings)
                guard generation == token, !Task.isCancelled else { return }
                stopStreaming(); isLoading = false; isPlaying = false; wantsPlayback = false; loadingWatchdog?.cancel()
                cancelTransition()
                self.error = "Lecture impossible : " + (lastStreamFailure.map { $0 + "\n" } ?? "") + error.localizedDescription
            }
        }
    }

    private func stopStreaming(pause: Bool = true) {
        streamObservations.removeAll()
        if let observer = streamEndObservation { NotificationCenter.default.removeObserver(observer); streamEndObservation = nil }
        if pause { streamPlayer?.pause() }
        streamPlayer = nil; streamSource = nil; isStreaming = false
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
                await AudioCache.shared.storeInvidiousInfo(track: current, bitrate: source.bitrate, instance: source.instance, duration: source.duration)
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
        let end = min(file.length, AVAudioFramePosition((duration > 0 ? duration : Double(file.length) / file.processingFormat.sampleRate) * file.processingFormat.sampleRate))
        let start = max(0, min(end - 1, AVAudioFramePosition(seconds * file.processingFormat.sampleRate)))
        let frames = AVAudioFrameCount(min(Int64(UInt32.max), max(1, end - start)))
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
            if let itemDuration = streamPlayer.currentItem?.duration.seconds {
                let seconds = PlaybackDuration.effective(declared: declaredDuration, measured: itemDuration)
                if duration != seconds { duration = seconds }
            }
        } else if let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render) {
            position = min(duration, scheduledOffset + Double(time.sampleTime) / time.sampleRate)
        }
        if firstAudioLatency == nil, position > 0.05 {
            firstAudioLatency = Date().timeIntervalSince(beganLoading)
            finishLoading()
            beginCrossfade()
            let nextIndex = (queue.firstIndex { $0.id == current?.id } ?? -1) + 1
            if queue.indices.contains(nextIndex) {
                let nextTracks = Array(queue.dropFirst(nextIndex).prefix(2)).filter { $0.source == .invidious }
                let settings = library.settings
                Task { await InvidiousAudioLoader.prefetch(nextTracks, settings: settings) }
            }
            if isStreaming, requestedEffects || library.settings.needsPreparedEffects { prepareNativeEffects() }
        }
        flushListening(force: false)
        if library.settings.usesCrossfade, !isLoading, !isTransitioning, stopAtEnd == false, repeatMode != .one,
           loopB == nil, let id = current?.id, automaticFadeID != id, duration > 0,
           (duration - position) / Double(max(0.5, library.settings.playbackRate)) <= library.settings.crossfadeSeconds {
            let index = queue.firstIndex { $0.id == id } ?? -1
            let canAdvance = shuffle ? queue.contains { !playedIDs.contains($0.id) } || repeatMode == .all : index + 1 < queue.count || repeatMode == .all
            if queue.count > 1, canAdvance { automaticFadeID = id; next(userInitiated: false); return }
        }
        if isStreaming, duration > 0, position >= duration - 0.03 { position = duration; next(userInitiated: false); return }
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
                let image = await ArtworkImageCache.shared.image(for: ArtworkRequest(url: url, pixels: 512))
                guard !Task.isCancelled, let self, self.current?.id == id, let image else { return }
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
        observations.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] notification in
            let changed = notification.object as? AVAudioEngine
            Task { @MainActor [weak self] in
                guard let self, changed === engine, !isStreaming, !isTransitioning, isPlaying else { return }
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
        var duration: Double?
        var provider: String?
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
        let expected = track.duration > 0 ? track.duration : source.duration ?? 0
        guard expected > 0 else { return nil }
        do {
            try validate(file, expectedDuration: expected)
            return InvidiousAudio(fileURL: file, bitrate: source.bitrate, instance: source.instance, duration: expected, provider: source.provider)
        } catch { return nil }
    }
    func storeInvidiousInfo(track: Track, bitrate: Int, instance: URL, duration: Double? = nil, provider: String? = nil) {
        let metadata = destination(key: "invidious:\(track.location):aac", ext: "json")
        let source = CachedSource(bitrate: bitrate, instance: instance, expires: Date().addingTimeInterval(bitrate >= 90000 ? 86400 : 600), duration: duration ?? track.duration, provider: provider)
        if let data = try? JSONEncoder().encode(source) { try? data.write(to: metadata, options: .atomic) }
    }
    func adoptNativeYouTubei(_ audio: InvidiousAudio, track: Track) throws -> InvidiousAudio {
        guard audio.fileURL.isFileURL, audio.fileURL.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL else { throw BlusicError.message("Fichier youtubei.js hors du répertoire temporaire.") }
        try validate(audio.fileURL, expectedDuration: audio.duration ?? track.duration)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = destination(key: "invidious:\(track.location):aac:\(audio.bitrate)", ext: "m4a")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: audio.fileURL, to: target)
        storeInvidiousInfo(track: track, bitrate: audio.bitrate, instance: audio.instance, duration: audio.duration, provider: audio.provider)
        var result = audio; result.fileURL = target; return result
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
        request.setValue("Blusic/1.1 (iOS; Invidious client)", forHTTPHeaderField: "User-Agent")
        progress(nil)
        if fileExtension == "m4a" {
            return try await rangedCopy(request, to: destination, expectedDuration: expectedDuration, session: session, progress: progress)
        }
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
    /// Some signed audio hosts accept finite ranges but refuse open-ended
    /// requests. Assemble ordinary 256 KiB ranges, checking every boundary.
    private func rangedCopy(_ original: URLRequest, to destination: URL, expectedDuration: Double,
                            session: URLSession, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        let temporary = directory.appendingPathComponent("partial-\(UUID().uuidString).m4a")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw BlusicError.message("Impossible de préparer le cache audio.") }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        var offset = 0, total: Int?
        repeat {
            try Task.checkCancellation()
            var request = original
            request.setValue("bytes=\(offset)-\(offset + 262143)", forHTTPHeaderField: "Range")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
                throw BlusicError.message("Le téléchargement audio est refusé (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            guard response.mimeType?.hasPrefix("text/") != true, response.mimeType != "application/json", !data.isEmpty else {
                throw BlusicError.message("Le serveur renvoie une page au lieu de l’audio.")
            }
            if http.statusCode == 206 {
                guard let range = http.value(forHTTPHeaderField: "Content-Range"),
                      let parsed = AudioByteRange.parse(range), parsed.start == offset,
                      parsed.end - parsed.start + 1 == data.count, parsed.total <= 300_000_000,
                      total == nil || total == parsed.total else { throw BlusicError.message("Plage audio incohérente ou fichier trop volumineux.") }
                total = parsed.total
            } else {
                guard offset == 0, data.count <= 300_000_000 else { throw BlusicError.message("Le serveur ne respecte pas les plages audio.") }
                total = data.count
            }
            try output.write(contentsOf: data)
            offset += data.count
            progress(total.map { Double(offset) / Double($0) })
        } while offset < (total ?? 0)
        try output.synchronize()
        try validate(temporary, expectedDuration: expectedDuration)
        try Task.checkCancellation()
        if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: temporary, to: destination) }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
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

enum AudioByteRange {
    static func parse(_ value: String) -> (start: Int, end: Int, total: Int)? {
        guard value.hasPrefix("bytes ") else { return nil }
        let parts = value.dropFirst(6).split(separator: "/")
        guard parts.count == 2, let total = Int(parts[1]), total > 0 else { return nil }
        let span = parts[0].split(separator: "-")
        guard span.count == 2, let start = Int(span[0]), let end = Int(span[1]), start >= 0, end >= start, end < total else { return nil }
        return (start, end, total)
    }
}
