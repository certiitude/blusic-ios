import Foundation
import CryptoKit
import Observation
import Security

/// Only library metadata is shared. Audio files, paths, settings and access keys stay local.
struct SorynSharedLibrary: Codable, Sendable {
    var version = 1
    var tracks: [Track]
    var playlists: [Playlist]
    var favorites: Set<UUID>
    var history: [ListeningEvent]
    var followedArtists: [MusicArtist]

    @MainActor init(_ library: LibraryStore) {
        tracks = library.tracks.map { item in
            var track = item
            if track.source == .local { track.source = .unresolved; track.location = "" }
            if track.artworkURL?.scheme != "https" { track.artworkURL = nil }
            track.originInstance = nil
            return track
        }
        playlists = library.playlists; favorites = library.favorites
        history = library.history
        followedArtists = library.followedArtists.map { artist in
            var artist = artist
            if artist.artworkURL?.scheme != "https" { artist.artworkURL = nil }
            return artist
        }
    }

    func validate() throws {
        guard version == 1, tracks.count <= 50_000, playlists.count <= 50_000, history.count <= 50_000,
              Set(tracks.map(\.id)).count == tracks.count, Set(playlists.map(\.id)).count == playlists.count,
              tracks.allSatisfy({ $0.title.count <= 2000 && $0.location.count <= 4096 && $0.duration.isFinite && $0.duration >= 0 && $0.source != .local }),
              playlists.allSatisfy({ $0.name.count <= 2000 && $0.trackIDs.count <= 50_000 }),
              history.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 }) else {
            throw BlusicError.message("La bibliothèque reçue n’est pas valide.")
        }
    }

    static func mergeSet<T: Hashable>(_ base: Set<T>, _ local: Set<T>, _ remote: Set<T>) -> Set<T> {
        local.union(remote).filter { base.contains($0) ? local.contains($0) && remote.contains($0) : true }
    }

    /// Preserve edits made on this iPhone while a request was in flight.
    @MainActor func apply(to library: LibraryStore, sent: SorynSharedLibrary) {
        let current = SorynSharedLibrary(library)
        let localFiles = Dictionary(uniqueKeysWithValues: library.tracks.filter { $0.source == .local }.map { ($0.id, $0) })
        let merged = Self.mergeEntities(sent.tracks, current.tracks, tracks) { base, local, remote in
            // A concurrent metadata edit stays local; a subsequent sync will reconcile it.
            local == base ? remote : local
        }
        library.tracks = merged.map { localFiles[$0.id] ?? $0 } + localFiles.values.filter { local in !merged.contains(where: { $0.id == local.id }) }
        let known = Set(library.tracks.map(\.id))
        var aliases: [UUID: UUID] = [:]
        for track in current.tracks where !known.contains(track.id) && !track.location.isEmpty {
            if let canonical = library.tracks.first(where: { $0.source == track.source && $0.location == track.location }) { aliases[track.id] = canonical.id }
        }
        func remap(_ id: UUID) -> UUID { aliases[id] ?? id }
        library.playlists = Self.mergeEntities(sent.playlists, current.playlists, playlists) { base, local, remote in
            var p = local
            if local.name == base?.name { p.name = remote.name }
            if local.detail == base?.detail { p.detail = remote.detail }
            let kept = Self.mergeSet(Set(base?.trackIDs ?? []), Set(local.trackIDs), Set(remote.trackIDs))
            p.trackIDs = (local.trackIDs + remote.trackIDs).reduce(into: []) { ids, id in
                if kept.contains(id), !ids.contains(id) { ids.append(id) }
            }
            return p
        }
        library.playlists = library.playlists.map { p in var p = p; var seen = Set<UUID>(); p.trackIDs = p.trackIDs.map(remap).filter { known.contains($0) && seen.insert($0).inserted }; return p }
        library.favorites = Set(Self.mergeSet(sent.favorites, current.favorites, favorites).map(remap)).intersection(known)
        var events: [UUID: ListeningEvent] = [:]
        for event in current.history + history where event.seconds >= (events[event.id]?.seconds ?? -1) { events[event.id] = event }
        library.history = events.values.map { event in var event = event; event.trackID = remap(event.trackID); return event }.sorted { $0.date < $1.date }
        library.savedQueue = library.savedQueue.map(remap).filter { known.contains($0) }
        library.savedCurrentID = library.savedCurrentID.map(remap)
        library.followedArtists = Self.mergeEntities(sent.followedArtists, current.followedArtists, followedArtists) { _, local, _ in local }
        library.save()
    }

    private static func mergeEntities<T: Identifiable & Equatable>(_ base: [T], _ local: [T], _ remote: [T], conflict: (T?, T, T) -> T) -> [T] {
        let b = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let l = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let r = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<T.ID>(), result: [T] = []
        for id in (local + remote).map(\.id) where seen.insert(id).inserted {
            if let left = l[id], let right = r[id] {
                result.append(left == b[id] ? right : right == b[id] ? left : conflict(b[id], left, right))
            } else if let remaining = l[id] ?? r[id], b[id] == nil || remaining != b[id] { result.append(remaining) }
        }
        return result
    }
}

struct SorynSyncBox: Codable {
    var version = 1
    var box: String
    static let context = Data("soryn-sync-v1".utf8)
    static func seal<T: Encodable>(_ value: T, key: SymmetricKey) throws -> SorynSyncBox {
        let encrypted = try AES.GCM.seal(JSONEncoder().encode(value), using: key, authenticating: context)
        guard let data = encrypted.combined else { throw BlusicError.message("Chiffrement indisponible.") }
        return SorynSyncBox(box: data.base64EncodedString())
    }
    func open<T: Decodable>(_ type: T.Type, key: SymmetricKey) throws -> T {
        guard version == 1, let data = Data(base64Encoded: box), data.count >= 28 else { throw BlusicError.message("Échange chiffré invalide.") }
        let decrypted = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: Self.context)
        return try JSONDecoder().decode(type, from: decrypted)
    }
}

@MainActor @Observable
final class SorynSyncClient {
    var status = "Non associé à un PC"
    private(set) var busy = false
    private(set) var address: String
    private(set) var lastSync: Date?
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private let credentials: any SorynSyncKeyStoring
    var paired: Bool { !address.isEmpty && credentials.read() != nil }

    init(library: LibraryStore, defaults: UserDefaults = .standard, credentials: (any SorynSyncKeyStoring)? = nil) {
        self.library = library; self.defaults = defaults
        self.credentials = credentials ?? SorynSyncKeychain()
        address = defaults.string(forKey: "soryn.sync.address") ?? ""
        deviceID = defaults.string(forKey: "soryn.sync.deviceID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "soryn.sync.deviceID")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: SorynNoRedirect(), delegateQueue: nil)
        if !address.isEmpty { status = "PC associé · en attente du réseau local" }
    }

    static func pairing(_ input: String) throws -> (String, Data) {
        guard let url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "soryn", url.host == "pair",
              let address = url.queryItems?.first(where: { $0.name == "address" })?.value,
              let endpoint = URLComponents(string: address), endpoint.scheme == "http", endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil, endpoint.path.isEmpty, let host = endpoint.host, let port = endpoint.port, (1024...65535).contains(port),
              isPrivateIPv4(host), let keyString = url.queryItems?.first(where: { $0.name == "key" })?.value else {
            throw BlusicError.message("Colle le lien d’appairage affiché dans Soryn Windows → Synchroniser. Adresse IP privée uniquement.")
        }
        let base64 = keyString.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let key = Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)), key.count == 32 else {
            throw BlusicError.message("Clé d’appairage invalide.")
        }
        return (address, key)
    }
    static func isPrivateIPv4(_ host: String) -> Bool {
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1])) || p[0] == 127
    }
    func pair(_ input: String) async {
        do {
            let (endpoint, key) = try Self.pairing(input)
            try credentials.write(key)
            address = endpoint; defaults.set(endpoint, forKey: "soryn.sync.address")
            await sync()
        } catch { status = error.localizedDescription }
    }
    func forget() {
        address = ""; defaults.removeObject(forKey: "soryn.sync.address")
        credentials.forget(); defaults.removeObject(forKey: "soryn.sync.acknowledgedRequestID")
        status = "Association supprimée"; lastSync = nil
    }
    func runWhileActive() async {
        while !Task.isCancelled {
            if paired { await sync() }
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
        }
    }
    func sync() async {
        guard !busy, let library, let bytes = credentials.read(), !address.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            let snapshot = SorynSharedLibrary(library), requestID = UUID().uuidString, key = SymmetricKey(data: bytes)
            let packet = RequestPacket(deviceID: deviceID, requestID: requestID, sentAt: Date().timeIntervalSince1970 * 1000,
                                       snapshot: snapshot, acknowledgedRequestID: defaults.string(forKey: "soryn.sync.acknowledgedRequestID"))
            var request = URLRequest(url: URL(string: address + "/v1/sync")!)
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(SorynSyncBox.seal(packet, key: key))
            let (stream, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw BlusicError.message("Échange refusé par le PC. Vérifie l’appairage et l’heure des deux appareils.") }
            var data = Data()
            for try await byte in stream {
                guard data.count < 12_000_000 else { throw BlusicError.message("Réponse trop volumineuse.") }
                data.append(byte)
            }
            let reply = try JSONDecoder().decode(SorynSyncBox.self, from: data).open(ReplyPacket.self, key: key)
            guard reply.protocolVersion == 1, reply.requestID == requestID else { throw BlusicError.message("Réponse d’un autre échange refusée.") }
            try reply.snapshot.validate()
            try Task.checkCancellation()
            reply.snapshot.apply(to: library, sent: snapshot)
            defaults.set(requestID, forKey: "soryn.sync.acknowledgedRequestID")
            lastSync = Date(); status = "Bibliothèque synchronisée avec Soryn Windows"
        } catch is CancellationError { status = "Synchronisation interrompue" }
        catch { status = "PC inaccessible ou échange refusé. Même Wi-Fi, Soryn ouvert et réseau privé autorisé dans le pare-feu Windows. \(error.localizedDescription)" }
    }
    private struct RequestPacket: Encodable {
        let protocolVersion = 1
        var deviceID: String; var requestID: String; var sentAt: Double; var snapshot: SorynSharedLibrary; var acknowledgedRequestID: String?
        enum CodingKeys: String, CodingKey { case protocolVersion = "protocol", deviceID, requestID, sentAt, snapshot, acknowledgedRequestID }
    }
    private struct ReplyPacket: Decodable {
        var protocolVersion: Int; var requestID: String; var snapshot: SorynSharedLibrary
        enum CodingKeys: String, CodingKey { case protocolVersion = "protocol", requestID, snapshot }
    }
}

@MainActor protocol SorynSyncKeyStoring {
    func read() -> Data?
    func write(_ value: Data) throws
    func forget()
}

/// Production always uses the protected system keychain. Tests may inject storage
/// because an unsigned simulator has no keychain-access entitlement.
@MainActor private struct SorynSyncKeychain: SorynSyncKeyStoring {
    private static var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.soryn.lan-sync", kSecAttrAccount as String: "paired-desktop"]
    }
    func read() -> Data? {
        var query = Self.keyQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    func forget() { SecItemDelete(Self.keyQuery as CFDictionary) }
    func write(_ value: Data) throws {
        let update = [kSecValueData as String: value]
        let status = SecItemUpdate(Self.keyQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var query = Self.keyQuery; query[kSecValueData as String] = value; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw BlusicError.message("Impossible de conserver l’appairage dans le trousseau (\(added)). Vérifie la signature de l’app.") }
        } else if status != errSecSuccess { throw BlusicError.message("Impossible de modifier l’appairage (\(status)). Vérifie la signature de l’app.") }
    }
}

private final class SorynNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor @Observable
final class SorynAccountClient {
    static let serverAddress = "https://soryn-accounts.onrender.com"
    private(set) var status = "Sans compte · bibliothèque locale"
    private(set) var busy = false
    private(set) var lastSync: Date?
    var signedIn: Bool { accountSession != nil }
    var displayName: String { accountSession?.account.displayName ?? "" }
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private let credentials: any SorynSyncKeyStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let server: URL
    private var accountSession: AccountSession?
    private struct AccountSession: Codable {
        struct Account: Codable { var id: String; var username: String; var displayName: String }
        var account: Account; var token: String; var expiresAt: Double
    }
    init(library: LibraryStore, defaults: UserDefaults = .standard, credentials: (any SorynSyncKeyStoring)? = nil, testServer: URL? = nil) {
        self.library = library; self.defaults = defaults; self.credentials = credentials ?? SorynAccountKeychain()
        #if DEBUG
        server = testServer ?? URL(string: Self.serverAddress)!
        #else
        server = URL(string: Self.serverAddress)!
        #endif
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 65; config.timeoutIntervalForResource = 70
        session = URLSession(configuration: config, delegate: SorynNoRedirect(), delegateQueue: nil)
        if let data = self.credentials.read(), let saved = try? JSONDecoder().decode(AccountSession.self, from: data) {
            accountSession = saved; status = "Compte connecté · synchronisation en attente"
        }
        if defaults.string(forKey: "soryn.account.deviceID") == nil { defaults.set(UUID().uuidString, forKey: "soryn.account.deviceID") }
    }
    private func request(_ action: String, data: Data, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent("v1/accounts/\(action)"))
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (stream, response) = try await session.bytes(for: request)
        var body = Data()
        for try await byte in stream { guard body.count < 8_000_000 else { throw BlusicError.message("Réponse du compte trop volumineuse.") }; body.append(byte) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            struct ServerError: Decodable { var error: String }
            let message = (try? JSONDecoder().decode(ServerError.self, from: body).error) ?? "Serveur de comptes indisponible. Ta bibliothèque locale reste accessible."
            throw BlusicError.message(message)
        }
        return body
    }
    func authenticate(username: String, password: String, create: Bool) async {
        guard !busy, !signedIn else { return }
        guard username.range(of: #"^[a-zA-Z0-9_][a-zA-Z0-9_.-]{2,23}$"#, options: .regularExpression) != nil,
              (12...128).contains(password.utf16.count) else { status = "Pseudo : 3 à 24 caractères. Mot de passe : 12 à 128 caractères."; return }
        busy = true; status = "Connexion au compte…"
        do {
            let body = try JSONEncoder().encode(["username": username, "password": password])
            let data = try await request(create ? "register" : "login", data: body)
            let saved = try JSONDecoder().decode(AccountSession.self, from: data)
            guard UUID(uuidString: saved.account.id) != nil, saved.token.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else { throw BlusicError.message("Session reçue invalide.") }
            try credentials.write(data); accountSession = saved
            defaults.set(UUID().uuidString, forKey: "soryn.account.deviceID"); defaults.removeObject(forKey: "soryn.account.ack")
            status = "Connecté. Prêt à fusionner la bibliothèque."
        } catch { status = error.localizedDescription }
        busy = false
        if signedIn { await sync() }
    }
    func sync() async {
        guard !busy, let accountSession, let library else { return }
        busy = true; defer { busy = false }
        status = "Synchronisation du compte…"
        do {
            struct Packet: Encodable {
                var `protocol` = 1; var deviceID: String; var requestID: String; var snapshot: SorynSharedLibrary; var acknowledgedRequestID: String?
            }
            struct Reply: Decodable { var `protocol`: Int; var requestID: String; var snapshot: SorynSharedLibrary }
            let sent = SorynSharedLibrary(library), id = UUID().uuidString
            let packet = Packet(deviceID: defaults.string(forKey: "soryn.account.deviceID")!, requestID: id, snapshot: sent, acknowledgedRequestID: defaults.string(forKey: "soryn.account.ack"))
            let body = try await request("sync", data: JSONEncoder().encode(packet), token: accountSession.token)
            let reply = try JSONDecoder().decode(Reply.self, from: body)
            guard reply.protocol == 1, reply.requestID == id else { throw BlusicError.message("Réponse d’un autre échange refusée.") }
            try reply.snapshot.validate(); try Task.checkCancellation()
            reply.snapshot.apply(to: library, sent: sent)
            defaults.set(id, forKey: "soryn.account.ack"); lastSync = Date(); status = "Bibliothèque synchronisée avec ton compte"
        } catch { status = error.localizedDescription }
    }
    func logout() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let token = accountSession?.token
        accountSession = nil; credentials.forget(); defaults.removeObject(forKey: "soryn.account.ack"); lastSync = nil
        status = "Déconnecté · bibliothèque locale conservée"
        if let token {
            do { _ = try await request("logout", data: Data("{}".utf8), token: token) }
            catch { status = "Déconnecté sur cet iPhone. Révocation distante non confirmée ; la session distante expire au plus tard après 30 jours." }
        }
    }
    func deleteAccount(password: String) async {
        guard !busy, let token = accountSession?.token else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await request("delete", data: JSONEncoder().encode(["password": password]), token: token)
            accountSession = nil; credentials.forget(); defaults.removeObject(forKey: "soryn.account.ack"); lastSync = nil
            status = "Compte supprimé du serveur · bibliothèque locale conservée"
        } catch { status = error.localizedDescription }
    }
    func runWhileActive() async {
        while !Task.isCancelled {
            if signedIn { await sync() }
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }
}

@MainActor private struct SorynAccountKeychain: SorynSyncKeyStoring {
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.soryn.account-session", kSecAttrAccount as String: "optional-account"] }
    func read() -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }; return result as? Data
    }
    func write(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw BlusicError.message("Impossible de protéger la session dans le trousseau (\(added)). Vérifie la signature de l’app.") }
        } else if status != errSecSuccess { throw BlusicError.message("Impossible de protéger la session (\(status)). Vérifie la signature de l’app.") }
    }
    func forget() { SecItemDelete(query as CFDictionary) }
}
