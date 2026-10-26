import Foundation
import WebKit
import AVFoundation

enum NativeYouTubeRequestPolicy {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return ["www.youtube.com", "music.youtube.com", "m.youtube.com", "youtube.com", "youtubei.googleapis.com",
                "jnn-pa.googleapis.com", "www.google.com", "www.gstatic.com"].contains(host)
            || host.hasSuffix(".googlevideo.com") || host.hasSuffix(".gstatic.com")
    }
}

/// Executes the packaged resolution protocol in WebKit; never renders or plays
/// a YouTube media element. AAC bytes are handed to the native audio engine.
@MainActor
final class NativeYouTubeiResolver: NSObject, WKScriptMessageHandler {
    static let shared = NativeYouTubeiResolver()
    private var web: WKWebView?
    private var ready = false
    private var job: String?
    private var continuation: CheckedContinuation<InvidiousAudio, Error>?
    private var watchdog: Task<Void, Never>?
    private var requests: [Int: Task<Void, Never>] = [:]
    private var fetches: [Int: NativeResolverNetworkStream] = [:]
    private let spool = NativeYouTubeSpool()
    private static let network: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        // Ephemeral session cookies belong only to this resolver, never to the
        // user's Safari/Google account. Script-supplied Cookie headers remain blocked.
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }()

    func resolve(_ track: Track, quality: OnlineAudioQuality = .standard) async throws -> InvidiousAudio {
        guard InvidiousService.isVideoID(track.location) else { throw BlusicError.message("Identifiant musical invalide.") }
        while job != nil { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(50)) }
        let token = UUID().uuidString
        job = token
        do {
            await spool.start(token: token, quality: quality)
            try Task.checkCancellation()
            try prepareDocument()
            for _ in 0..<120 {
                try Task.checkCancellation()
                if ready { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard ready else { throw BlusicError.message("Le moteur youtubei.js n’a pas démarré.") }
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { callback in
                    continuation = callback
                    watchdog = Task { @MainActor [weak self] in
                        do { try await Task.sleep(for: .seconds(35)) } catch { return }
                        self?.fail(BlusicError.message("youtubei.js : la préparation audio a dépassé 35 secondes."), token: token, reset: true)
                    }
                    let arguments = "'\(track.location)','\(token)','\(quality.rawValue)'"
                    web?.evaluateJavaScript("window.__blusicResolve(\(arguments)); void 0") { [weak self] _, error in
                        if let error { Task { @MainActor in self?.fail(BlusicError.message("youtubei.js n’a pas pu lancer la résolution : \(error.localizedDescription)"), token: token, reset: true) } }
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.fail(CancellationError(), token: token, reset: true) }
            }
        } catch {
            if job == token { job = nil }
            throw error
        }
    }

    private func prepareDocument() throws {
        if web != nil { return }
        guard let url = Bundle.main.url(forResource: "YouTubeiResolver", withExtension: "js") else {
            throw BlusicError.message("Le moteur youtubei.js embarqué est absent de cette version.")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(self, name: "blusicResolver")
        configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let document = WKWebView(frame: .zero, configuration: configuration)
        document.isInspectable = false
        web = document; ready = false
        document.loadHTMLString("<!doctype html><html><head><meta charset='utf-8'><title>Blusic audio resolver</title></head><body></body></html>", baseURL: URL(string: "https://www.youtube.com"))
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in self?.handle(message) }
    }
    private func handle(_ message: WKScriptMessage) {
        guard let document = web, message.webView === document, let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "ready" { ready = true; return }
        guard let token = job, body["job"] as? String == token else { return }
        if action == "fetch", let identifier = body["request"] as? Int {
            requests[identifier] = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    guard let address = body["url"] as? String, let url = URL(string: address), NativeYouTubeRequestPolicy.allows(url) else {
                        throw BlusicError.message("Hôte réseau du moteur youtubei.js non autorisé.")
                    }
                    var request = URLRequest(url: url)
                    let method = body["method"] as? String ?? "GET"
                    guard ["GET", "POST", "HEAD"].contains(method) else { throw BlusicError.message("Méthode réseau non autorisée.") }
                    request.httpMethod = method; request.httpShouldHandleCookies = true
                    for (name, value) in body["headers"] as? [String: String] ?? [:] where !["host", "cookie", "authorization", "content-length", "connection"].contains(name.lowercased()) {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                    if let encoded = body["body"] as? String {
                        guard encoded.count <= 4_000_000, let data = Data(base64Encoded: encoded) else { throw BlusicError.message("Requête audio trop volumineuse.") }
                        request.httpBody = data
                    }
                    let (bytes, response) = try await Self.network.bytes(for: request)
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse, let final = http.url, NativeYouTubeRequestPolicy.allows(final) else {
                        bytes.task.cancel()
                        throw BlusicError.message("Réponse réseau youtubei.js invalide ou trop importante.")
                    }
                    guard job == token, web === document else { bytes.task.cancel(); return }
                    fetches[identifier] = NativeResolverNetworkStream(bytes)
                    var headers: [String: String] = [:]
                    for (name, value) in http.allHeaderFields { headers[String(describing: name)] = String(describing: value) }
                    reply(identifier, ["status": http.statusCode, "headers": headers, "stream": identifier, "url": final.absoluteString], document: document, token: token)
                } catch {
                    reply(identifier, ["error": "Réseau youtubei.js : \(error.localizedDescription)"], document: document, token: token)
                }
                if web === document { requests[identifier] = nil }
            }
        } else if action == "readFetch" || action == "closeFetch", let streamID = body["stream"] as? Int, let identifier = body["request"] as? Int {
            requests[identifier] = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    guard let stream = fetches[streamID] else { throw BlusicError.message("Flux réseau fermé.") }
                    if action == "closeFetch" {
                        await stream.close(); fetches[streamID] = nil
                        reply(identifier, ["ok": true], document: document, token: token)
                    } else {
                        let data = try await stream.read()
                        try Task.checkCancellation()
                        if data.isEmpty { await stream.close(); fetches[streamID] = nil }
                        reply(identifier, ["done": data.isEmpty, "body": data.base64EncodedString()], document: document, token: token)
                    }
                } catch { reply(identifier, ["error": error.localizedDescription], document: document, token: token) }
                if web === document { requests[identifier] = nil }
            }
        } else if action == "beginAudio" || action == "appendAudio", body["job"] as? String == token, let identifier = body["request"] as? Int {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if action == "beginAudio" { try await spool.begin(expected: body["expected"] as? Int ?? 0, token: token) }
                    else { try await spool.append(encoded: body["body"] as? String ?? "", token: token) }
                    reply(identifier, ["ok": true], document: document, token: token)
                } catch { reply(identifier, ["error": error.localizedDescription], document: document, token: token) }
            }
        } else if action == "finished", body["job"] as? String == token {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await spool.finish(expected: body["expected"] as? Int ?? 0,
                        bitrate: body["bitrate"] as? Int ?? 0, duration: body["duration"] as? Double ?? 0, token: token)
                    guard job == token else { try? FileManager.default.removeItem(at: result.fileURL); return }
                    watchdog?.cancel(); watchdog = nil; closeNetwork(); job = nil
                    let callback = continuation; continuation = nil; callback?.resume(returning: result)
                } catch { fail(error, token: token, reset: false) }
            }
        } else if action == "failed", body["job"] as? String == token {
            fail(BlusicError.message("youtubei.js sur cet iPhone : \(String((body["error"] as? String ?? "Résolution impossible").prefix(600)))"), token: token, reset: true)
        }
    }
    private func reply(_ identifier: Int, _ result: [String: Any], document: WKWebView, token: String) {
        guard job == token, web === document, let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) else { return }
        document.evaluateJavaScript("window.__blusicReply(\(identifier),\(json))", completionHandler: nil)
    }
    private func fail(_ error: Error, token: String, reset: Bool) {
        guard job == token else { return }
        watchdog?.cancel(); watchdog = nil
        closeNetwork()
        web?.evaluateJavaScript("window.__blusicCancel()", completionHandler: nil)
        if reset { web?.configuration.userContentController.removeScriptMessageHandler(forName: "blusicResolver"); web?.stopLoading(); web = nil; ready = false }
        Task { await spool.cancel(token: token) }
        job = nil
        let callback = continuation; continuation = nil; callback?.resume(throwing: error)
    }
    private func closeNetwork() {
        requests.values.forEach { $0.cancel() }; requests.removeAll()
        let active = Array(fetches.values); fetches.removeAll()
        Task { for stream in active { await stream.close() } }
    }
}

private actor NativeResolverNetworkStream {
    private var iterator: URLSession.AsyncBytes.AsyncIterator?
    private let task: URLSessionTask
    private var received = 0
    init(_ bytes: URLSession.AsyncBytes) { iterator = bytes.makeAsyncIterator(); task = bytes.task }
    func read() async throws -> Data {
        guard var iterator = self.iterator else { return Data() }
        var chunk = Data(); chunk.reserveCapacity(32768)
        for _ in 0..<32768 {
            try Task.checkCancellation()
            guard let byte = try await iterator.next() else { break }
            chunk.append(byte)
        }
        received += chunk.count
        guard received <= 12_000_000 else { task.cancel(); throw BlusicError.message("Réponse du moteur youtubei.js trop volumineuse.") }
        self.iterator = iterator
        return chunk
    }
    func close() { task.cancel(); iterator = nil }
}

actor NativeYouTubeSpool {
    private var token: String?
    private var quality: OnlineAudioQuality = .standard
    private var handle: FileHandle?
    private var url: URL?
    private var expected = 0
    private var written = 0
    func start(token: String, quality: OnlineAudioQuality = .standard) { discard(); self.token = token; self.quality = quality }
    func begin(expected: Int, token: String) throws {
        guard self.token == token else { throw CancellationError() }
        discard()
        guard expected > 0, expected <= 25_000_000 else { throw BlusicError.message("Taille AAC invalide.") }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("youtubei-\(UUID().uuidString).m4a")
        guard FileManager.default.createFile(atPath: path.path, contents: nil) else { throw BlusicError.message("Impossible de préparer le fichier audio.") }
        url = path; handle = try FileHandle(forWritingTo: path); self.expected = expected; written = 0
    }
    func append(encoded: String, token: String) throws {
        guard self.token == token else { throw CancellationError() }
        guard encoded.count <= 12_000_000, let data = Data(base64Encoded: encoded), let handle, written + data.count <= expected else { throw BlusicError.message("Bloc AAC invalide.") }
        try handle.write(contentsOf: data); written += data.count
    }
    func finish(expected: Int, bitrate: Int, duration: Double, token: String) throws -> InvidiousAudio {
        guard self.token == token else { throw CancellationError() }
        guard let url, expected == self.expected, written == expected else { throw BlusicError.message("Fichier AAC incomplet.") }
        try handle?.synchronize(); try handle?.close(); handle = nil
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        guard file.length > 0, duration > 0, seconds.isFinite, seconds >= duration * 0.8 else { throw BlusicError.message("Le fichier AAC n’est pas décodable ou est tronqué.") }
        self.url = nil
        return InvidiousAudio(fileURL: url, bitrate: bitrate, instance: URL(string: "https://www.youtube.com")!, duration: duration, provider: "youtubei.js · iPhone", quality: quality)
    }
    func cancel(token: String) { guard self.token == token else { return }; discard(); self.token = nil }
    private func discard() { try? handle?.close(); handle = nil; if let url { try? FileManager.default.removeItem(at: url) }; url = nil; written = 0 }
}
