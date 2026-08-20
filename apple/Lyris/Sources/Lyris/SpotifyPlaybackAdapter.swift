import Foundation

protocol SpotifyPlaybackSessionServing: Sendable {
    func currentPlayback(account: SpotifyPlaybackAccount) async throws -> PlaybackSnapshot?
    func isTrackSaved(_ trackID: String, account: SpotifyPlaybackAccount) async throws -> Bool
    func setTrackSaved(_ saved: Bool, trackID: String, account: SpotifyPlaybackAccount) async throws
    func send(_ command: PlaybackCommand, snapshot: PlaybackSnapshot, account: SpotifyPlaybackAccount) async throws
}

private struct SpotifySessionFence: Equatable, Sendable {
    let profileID: UUID
    let generation: UInt64
}

private final class SpotifySessionBlockRegistry: @unchecked Sendable {
    private static let stateKey = "spotify.sessionFenceState.v2"
    private static let legacyBlockedProfileIDsKey = "spotify.reauthorizationBlockedProfileIDs.v1"
    private static let legacyGenerationsKey = "spotify.sessionFenceGenerations.v1"
    private static let lock = NSLock()

    private struct State {
        let blockedProfileIDs: Set<UUID>
        let generations: [UUID: UInt64]
    }

    private let persistentDefaults: UserDefaults?
    private var blockedProfileIDs: Set<UUID>
    private var generations: [UUID: UInt64]

    init(persistentDefaults: UserDefaults?) {
        self.persistentDefaults = persistentDefaults
        let state = Self.loadState(from: persistentDefaults)
        blockedProfileIDs = state.blockedProfileIDs
        generations = state.generations
    }

    func authorizationFence(for profileID: UUID) -> SpotifyAuthorizationFence {
        Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            return SpotifyAuthorizationFence(
                profileID: profileID,
                generation: generations[profileID] ?? 0
            )
        }
    }

    @discardableResult
    func block(_ profileID: UUID) -> SpotifySessionFence {
        Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            return blockWithoutLock(profileID)
        }
    }

    func blockIfAllowed(_ fence: SpotifySessionFence) throws -> SpotifySessionFence {
        try Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            try requireAllowed(fence)
            return blockWithoutLock(fence.profileID)
        }
    }

    func isBlocked(_ fence: SpotifySessionFence) -> Bool {
        Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            return generations[fence.profileID] == fence.generation
                && blockedProfileIDs.contains(fence.profileID)
        }
    }

    func sessionFence(for profileID: UUID) throws -> SpotifySessionFence {
        try Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            guard !blockedProfileIDs.contains(profileID) else {
                throw SpotifySessionError.reauthorizationRequired
            }
            return SpotifySessionFence(
                profileID: profileID,
                generation: generations[profileID] ?? 0
            )
        }
    }

    func validateAuthorizationFence(_ fence: SpotifyAuthorizationFence) throws {
        try Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            guard (generations[fence.profileID] ?? 0) == fence.generation else {
                throw SpotifyAuthorizationCoreError.attemptProfileMismatch
            }
        }
    }

    func validateSessionFence(_ fence: SpotifySessionFence) throws {
        try Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            try requireAllowed(fence)
        }
    }

    func withValidAuthorizationFence(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> Void
    ) throws {
        try Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            guard (generations[fence.profileID] ?? 0) == fence.generation else {
                throw SpotifyAuthorizationCoreError.attemptProfileMismatch
            }
            do {
                try operation()
            } catch {
                _ = blockWithoutLock(fence.profileID)
                throw error
            }
        }
    }

    func withAllowedSession<T>(
        _ fence: SpotifySessionFence,
        perform operation: () throws -> T
    ) throws -> T {
        try Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            try requireAllowed(fence)
            return try operation()
        }
    }

    func withCurrentAuthorization<T>(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> T
    ) throws -> T {
        try Self.lock.withLock {
            reloadPersistentStateWithoutLock()
            guard (generations[fence.profileID] ?? 0) == fence.generation else {
                throw SpotifyAuthorizationCoreError.attemptProfileMismatch
            }
            let result = try operation()
            blockedProfileIDs.remove(fence.profileID)
            persistState()
            return result
        }
    }

    private func requireAllowed(_ fence: SpotifySessionFence) throws {
        guard (generations[fence.profileID] ?? 0) == fence.generation,
              !blockedProfileIDs.contains(fence.profileID) else {
            throw SpotifySessionError.reauthorizationRequired
        }
    }

    private func blockWithoutLock(_ profileID: UUID) -> SpotifySessionFence {
        let generation = (generations[profileID] ?? 0) &+ 1
        generations[profileID] = generation
        blockedProfileIDs.insert(profileID)
        persistState()
        return SpotifySessionFence(profileID: profileID, generation: generation)
    }

    private func reloadPersistentStateWithoutLock() {
        guard persistentDefaults != nil else { return }
        let state = Self.loadState(from: persistentDefaults)
        blockedProfileIDs = state.blockedProfileIDs
        generations = state.generations
    }

    private static func loadState(from defaults: UserDefaults?) -> State {
        let persistedState = defaults?.dictionary(forKey: stateKey)
        let persistedBlockedProfileIDs = persistedState?["blockedProfileIDs"] as? [String]
        let persistedGenerations = persistedState?["generations"] as? [String: String]
        let blockedProfileIDs = Set(
            (
                persistedBlockedProfileIDs
                    ?? defaults?.stringArray(forKey: legacyBlockedProfileIDsKey)
                    ?? []
            )
                .compactMap(UUID.init(uuidString:))
        )
        let rawGenerations = persistedGenerations
            ?? (defaults?.dictionary(forKey: legacyGenerationsKey) ?? [:])
                .reduce(into: [String: String]()) { result, entry in
                    guard let rawValue = entry.value as? String else { return }
                    result[entry.key] = rawValue
                }
        let generations = rawGenerations.reduce(into: [UUID: UInt64]()) { result, entry in
            guard let profileID = UUID(uuidString: entry.key),
                  let generation = UInt64(entry.value) else { return }
            result[profileID] = generation
        }
        return State(
            blockedProfileIDs: blockedProfileIDs,
            generations: generations
        )
    }

    private func persistState() {
        guard let persistentDefaults else { return }
        persistentDefaults.set(
            [
                "blockedProfileIDs": blockedProfileIDs.map(\.uuidString).sorted(),
                "generations": generations.reduce(into: [String: String]()) { result, entry in
                    result[entry.key.uuidString] = String(entry.value)
                },
            ],
            forKey: Self.stateKey
        )
        persistentDefaults.removeObject(forKey: Self.legacyBlockedProfileIDsKey)
        persistentDefaults.removeObject(forKey: Self.legacyGenerationsKey)
        persistentDefaults.synchronize()
    }
}

actor SpotifySessionBroker: SpotifyPlaybackSessionServing, SpotifyAuthorizationTokenExchanging {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    private enum TokenGrant: Equatable {
        case authorizationCode
        case refreshToken
    }

    private enum TokenClientAuthentication {
        case publicClient
        case basic(clientID: String, clientSecret: String)
    }

    private enum TokenOperationFence: Sendable {
        case authorization(SpotifyAuthorizationFence)
        case session(SpotifySessionFence)
    }

    private struct SessionIdentity: Equatable, Sendable {
        let profileID: UUID
        let clientID: String
        let authorizationMode: SpotifyAuthorizationMode

        init(account: SpotifyPlaybackAccount) {
            profileID = account.profileID
            clientID = account.clientID
            authorizationMode = account.authorizationMode
        }

        init(request: SpotifyAuthorizationTokenRequest) {
            profileID = request.profileID
            clientID = request.clientID
            authorizationMode = switch request.authentication {
            case .pkce: .pkce
            case .clientSecret: .authorizationCodeWithSecret
            }
        }
    }

    private struct RefreshFlight {
        let id: UUID
        let identity: SessionIdentity
        let sessionFence: SpotifySessionFence
        let authorizationEpoch: UInt64
        let task: Task<SpotifySessionTokenResponse, Error>
    }

    private let session: URLSession
    private let tokenStore: SpotifyTokenStore
    private let retryPolicy: SpotifyRetryPolicy
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    nonisolated private let sessionBlockRegistry: SpotifySessionBlockRegistry
    private var cachedAccessToken: String?
    private var cachedSessionFence: SpotifySessionFence?
    private var accessTokenExpiry = Date.distantPast
    private var activeIdentity: SessionIdentity?
    private var refreshFlight: RefreshFlight?
    private var reauthorizationBlockedIdentity: SessionIdentity?
    private var authorizationEpoch: UInt64 = 0

    init(
        credentialVault: CredentialVault,
        session: URLSession = .shared,
        persistentSessionDefaults: UserDefaults? = nil,
        retryPolicy: SpotifyRetryPolicy = SpotifyRetryPolicy(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleep = { delay in
            let seconds = max(0, delay)
            let maximumSeconds = Double(UInt64.max) / 1_000_000_000
            try await Task.sleep(nanoseconds: UInt64(min(seconds, maximumSeconds) * 1_000_000_000))
        }
    ) {
        tokenStore = SpotifyTokenStore(vault: credentialVault)
        sessionBlockRegistry = SpotifySessionBlockRegistry(
            persistentDefaults: persistentSessionDefaults
        )
        self.session = session
        self.retryPolicy = retryPolicy
        self.now = now
        self.sleep = sleep
    }

    nonisolated func blockSession(profileID: UUID) {
        let fence = sessionBlockRegistry.block(profileID)
        Task { [weak self] in
            await self?.applySessionBlock(fence)
        }
    }

    nonisolated func authorizationFence(for profileID: UUID) -> SpotifyAuthorizationFence {
        sessionBlockRegistry.authorizationFence(for: profileID)
    }

    nonisolated func withValidAuthorizationFence(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> Void
    ) throws {
        try sessionBlockRegistry.withValidAuthorizationFence(fence, perform: operation)
    }

    private func applySessionBlock(_ fence: SpotifySessionFence) {
        guard sessionBlockRegistry.isBlocked(fence) else { return }
        if let refreshFlight,
           refreshFlight.identity.profileID == fence.profileID,
           refreshFlight.sessionFence.generation != fence.generation {
            refreshFlight.task.cancel()
            self.refreshFlight = nil
        }
        if let cachedSessionFence,
           cachedSessionFence.profileID == fence.profileID,
           cachedSessionFence.generation != fence.generation {
            cachedAccessToken = nil
            self.cachedSessionFence = nil
            accessTokenExpiry = .distantPast
        }
    }

    func restoreConnection(account: SpotifyPlaybackAccount) async throws -> SpotifyConnectionReport? {
        _ = try sessionBlockRegistry.sessionFence(for: account.profileID)
        let identity = prepare(for: account)
        guard reauthorizationBlockedIdentity != identity else {
            throw SpotifySessionError.reauthorizationRequired
        }
        guard try tokenStore.refreshToken(for: account.profileID) != nil else { return nil }
        return try await fetchProfile(account: account)
    }

    func exchange(_ request: SpotifyAuthorizationTokenRequest) async throws -> SpotifyAuthorizationTokenGrant {
        try sessionBlockRegistry.validateAuthorizationFence(request.authorizationFence)
        authorizationEpoch &+= 1
        let exchangeEpoch = authorizationEpoch
        refreshFlight?.task.cancel()
        refreshFlight = nil
        cachedAccessToken = nil
        cachedSessionFence = nil
        accessTokenExpiry = .distantPast
        activeIdentity = SessionIdentity(request: request)
        reauthorizationBlockedIdentity = nil

        var parameters = [
            "grant_type": "authorization_code",
            "code": request.authorizationCode,
            "redirect_uri": request.redirectURI,
        ]
        let clientAuthentication: TokenClientAuthentication
        switch request.authentication {
        case .pkce(let codeVerifier):
            parameters["client_id"] = request.clientID
            parameters["code_verifier"] = codeVerifier
            clientAuthentication = .publicClient
        case .clientSecret(let clientSecret):
            clientAuthentication = .basic(clientID: request.clientID, clientSecret: clientSecret)
        }
        let token = try await requestToken(
            parameters: parameters,
            clientAuthentication: clientAuthentication,
            grant: .authorizationCode,
            authorizationEpoch: exchangeEpoch,
            operationFence: .authorization(request.authorizationFence)
        )
        guard authorizationEpoch == exchangeEpoch else { throw CancellationError() }
        try sessionBlockRegistry.validateAuthorizationFence(request.authorizationFence)
        return SpotifyAuthorizationTokenGrant(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresIn: token.expiresIn,
            grantedScopes: token.scope.map { Set($0.split(separator: " ").map(String.init)) }
        )
    }

    func adoptAuthorization(
        _ completion: SpotifyAuthorizationCompletion
    ) throws {
        let account = SpotifyPlaybackAccount(profile: completion.profile)
        guard completion.authorizationFence.profileID == account.profileID else {
            throw SpotifyAuthorizationCoreError.attemptProfileMismatch
        }
        try sessionBlockRegistry.withCurrentAuthorization(completion.authorizationFence) {
            let identity = prepare(for: account)
            reauthorizationBlockedIdentity = nil
            cache(
                SpotifySessionTokenResponse(
                    accessToken: completion.accessToken,
                    refreshToken: nil,
                    expiresIn: completion.expiresIn,
                    scope: nil
                ),
                identity: identity,
                sessionFence: SpotifySessionFence(
                    profileID: completion.authorizationFence.profileID,
                    generation: completion.authorizationFence.generation
                )
            )
        }
    }

    func currentPlayback(account: SpotifyPlaybackAccount) async throws -> PlaybackSnapshot? {
        let accountCapabilities = account.playbackCapabilities
        guard accountCapabilities.contains(.metadata) else {
            throw SpotifyNetworkFailure.forbidden
        }
        let (data, response) = try await authorizedRequest(
            account: account,
            method: "GET",
            url: URL(string: "https://api.spotify.com/v1/me/player")!,
            operation: .read
        )
        if response.statusCode == 204 || data.isEmpty { return nil }
        let state = try JSONDecoder.spotify.decode(SpotifyPlayerState.self, from: data)
        if state.currentlyPlayingType == "ad", state.item == nil {
            return PlaybackSnapshot(
                track: Track(
                    id: "spotify:advertisement",
                    title: "Spotify 广告",
                    artist: "Spotify",
                    album: "",
                    duration: 1,
                    kind: .advertisement
                ),
                position: 0,
                isPlaying: state.isPlaying,
                likedState: .unavailable,
                isShuffled: state.shuffleState,
                repeatMode: .off,
                volume: state.device?.volumePercent.map {
                    min(max(Double($0) / 100, 0), 1)
                },
                capabilities: [.transport],
                source: .web
            )
        }
        guard let item = state.item else { return nil }
        let trackID = item.uri ?? "spotify:track:\(item.id)"
        let itemKind: PlaybackItemKind = switch state.currentlyPlayingType {
        case "track": .track
        case "episode": .episode
        case "ad": .advertisement
        default:
            trackID.hasPrefix("spotify:track:") ? .track
                : trackID.hasPrefix("spotify:episode:") ? .episode : .unknown
        }
        let repeatMode: RepeatMode
        switch state.repeatState {
        case "track": repeatMode = .one
        case "context": repeatMode = .all
        default: repeatMode = .off
        }
        return PlaybackSnapshot(
            track: Track(
                id: trackID,
                title: item.name,
                artist: item.artists?.map(\.name).joined(separator: ", ")
                    ?? item.show?.publisher
                    ?? item.show?.name
                    ?? "Spotify",
                album: item.album?.name ?? item.show?.name ?? "",
                duration: TimeInterval(item.durationMs) / 1_000,
                artworkURL: item.album?.images.first?.url ?? item.images?.first?.url,
                kind: itemKind
            ),
            position: TimeInterval(state.progressMs ?? 0) / 1_000,
            isPlaying: state.isPlaying,
            likedState: itemKind == .track && accountCapabilities.contains(.likedSongsRead)
                ? .unknown
                : .unavailable,
            isShuffled: state.shuffleState,
            repeatMode: repeatMode,
            volume: state.device?.volumePercent.map {
                min(max(Double($0) / 100, 0), 1)
            },
            capabilities: itemKind == .track
                ? accountCapabilities
                : accountCapabilities.intersection([
                    .metadata,
                    .transport,
                    .seek,
                    .shuffle,
                    .repeatMode,
                    .remoteDevices,
                    .transferPlayback,
                ]),
            source: .web
        )
    }

    func isTrackSaved(_ trackID: String, account: SpotifyPlaybackAccount) async throws -> Bool {
        guard account.playbackCapabilities.contains(.likedSongsRead) else {
            throw SpotifyNetworkFailure.forbidden
        }
        guard trackID.hasPrefix("spotify:track:"), !trackID.isEmpty else { return false }
        var components = URLComponents(string: "https://api.spotify.com/v1/me/library/contains")!
        components.queryItems = [URLQueryItem(name: "uris", value: trackID)]
        let (data, _) = try await authorizedRequest(
            account: account,
            method: "GET",
            url: components.url!,
            operation: .read
        )
        return (try JSONDecoder().decode([Bool].self, from: data).first) ?? false
    }

    func setTrackSaved(
        _ saved: Bool,
        trackID: String,
        account: SpotifyPlaybackAccount
    ) async throws {
        guard account.playbackCapabilities.contains(.likedSongsWrite) else {
            throw SpotifyNetworkFailure.forbidden
        }
        guard trackID.hasPrefix("spotify:track:"), !trackID.isEmpty else { return }
        var components = URLComponents(string: "https://api.spotify.com/v1/me/library")!
        components.queryItems = [URLQueryItem(name: "uris", value: trackID)]
        _ = try await authorizedRequest(
            account: account,
            method: saved ? "PUT" : "DELETE",
            url: components.url!,
            operation: .absoluteMutation
        )
    }

    func send(
        _ command: PlaybackCommand,
        snapshot: PlaybackSnapshot,
        account: SpotifyPlaybackAccount
    ) async throws {
        guard account.playbackCapabilities.contains(requiredCapability(for: command)) else {
            throw SpotifyNetworkFailure.forbidden
        }
        let method: String
        let url: URL
        let operation: SpotifyRequestOperation
        switch command {
        case .togglePlayback:
            method = "PUT"
            url = URL(string: "https://api.spotify.com/v1/me/player/\(snapshot.isPlaying ? "pause" : "play")")!
            operation = .absoluteMutation
        case .previous:
            method = "POST"
            url = URL(string: "https://api.spotify.com/v1/me/player/previous")!
            operation = .navigation
        case .next:
            method = "POST"
            url = URL(string: "https://api.spotify.com/v1/me/player/next")!
            operation = .navigation
        case .seek(let position):
            method = "PUT"
            var components = URLComponents(string: "https://api.spotify.com/v1/me/player/seek")!
            components.queryItems = [
                URLQueryItem(name: "position_ms", value: String(Int(max(0, position) * 1_000)))
            ]
            url = components.url!
            operation = .absoluteMutation
        case .toggleLiked:
            return try await setTrackSaved(!snapshot.isLiked, trackID: snapshot.track.id, account: account)
        case .toggleShuffle:
            method = "PUT"
            var components = URLComponents(string: "https://api.spotify.com/v1/me/player/shuffle")!
            components.queryItems = [URLQueryItem(name: "state", value: String(!snapshot.isShuffled))]
            url = components.url!
            operation = .absoluteMutation
        case .cycleRepeat:
            method = "PUT"
            let nextState = switch snapshot.repeatMode {
            case .off: "context"
            case .all: "track"
            case .one: "off"
            }
            var components = URLComponents(string: "https://api.spotify.com/v1/me/player/repeat")!
            components.queryItems = [URLQueryItem(name: "state", value: nextState)]
            url = components.url!
            operation = .absoluteMutation
        case .setVolume(let requestedLevel):
            method = "PUT"
            var components = URLComponents(
                string: "https://api.spotify.com/v1/me/player/volume"
            )!
            let percent = Int((min(max(requestedLevel, 0), 1) * 100).rounded())
            components.queryItems = [
                URLQueryItem(name: "volume_percent", value: String(percent))
            ]
            url = components.url!
            operation = .absoluteMutation
        }
        _ = try await authorizedRequest(
            account: account,
            method: method,
            url: url,
            operation: operation
        )
    }

    private func requiredCapability(for command: PlaybackCommand) -> PlaybackCapabilities {
        switch command {
        case .togglePlayback, .previous, .next:
            .transport
        case .seek:
            .seek
        case .toggleLiked:
            .likedSongsWrite
        case .toggleShuffle:
            .shuffle
        case .cycleRepeat:
            .repeatMode
        case .setVolume:
            .volume
        }
    }

    private func accessToken(
        account: SpotifyPlaybackAccount,
        forceRefresh: Bool = false,
        sessionFence existingSessionFence: SpotifySessionFence? = nil
    ) async throws -> String {
        let sessionFence: SpotifySessionFence
        if let existingSessionFence {
            sessionFence = existingSessionFence
        } else {
            sessionFence = try sessionBlockRegistry.sessionFence(for: account.profileID)
        }
        let identity = prepare(for: account)
        guard reauthorizationBlockedIdentity != identity else {
            throw SpotifySessionError.reauthorizationRequired
        }
        if !forceRefresh,
           let cachedAccessToken,
           activeIdentity == identity,
           cachedSessionFence == sessionFence,
           accessTokenExpiry > now().addingTimeInterval(30) {
            return try sessionBlockRegistry.withAllowedSession(sessionFence) {
                cachedAccessToken
            }
        }
        if let refreshFlight,
           refreshFlight.identity == identity,
           refreshFlight.sessionFence == sessionFence {
            return try await finish(refreshFlight)
        }
        let refreshToken = try sessionBlockRegistry.withAllowedSession(sessionFence) {
            try tokenStore.refreshToken(for: account.profileID)
        }
        guard let refreshToken, !refreshToken.isEmpty else {
            throw SpotifyPlaybackError.notAuthorized
        }
        let clientAuthentication: TokenClientAuthentication
        switch account.authorizationMode {
        case .pkce:
            clientAuthentication = .publicClient
        case .authorizationCodeWithSecret:
            let clientSecret = try sessionBlockRegistry.withAllowedSession(sessionFence) {
                try tokenStore.clientSecret(for: account.profileID)
            }
            guard let clientSecret,
                  !clientSecret.isEmpty else {
                throw SpotifyAuthorizationCoreError.missingClientSecret
            }
            clientAuthentication = .basic(clientID: account.clientID, clientSecret: clientSecret)
        }
        let refreshEpoch = authorizationEpoch
        var parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        if account.authorizationMode == .pkce {
            parameters["client_id"] = account.clientID
        }
        let flight = RefreshFlight(
            id: UUID(),
            identity: identity,
            sessionFence: sessionFence,
            authorizationEpoch: refreshEpoch,
            task: Task { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.requestToken(
                    parameters: parameters,
                    clientAuthentication: clientAuthentication,
                    grant: .refreshToken,
                    authorizationEpoch: refreshEpoch,
                    operationFence: .session(sessionFence)
                )
            }
        )
        refreshFlight = flight
        return try await finish(flight)
    }

    private func finish(_ flight: RefreshFlight) async throws -> String {
        do {
            let token = try await flight.task.value
            if refreshFlight?.id == flight.id { refreshFlight = nil }
            guard authorizationEpoch == flight.authorizationEpoch,
                  activeIdentity == flight.identity else { throw CancellationError() }
            try sessionBlockRegistry.withAllowedSession(flight.sessionFence) {
                if let updatedRefreshToken = token.refreshToken, !updatedRefreshToken.isEmpty {
                    try tokenStore.storeRefreshToken(
                        updatedRefreshToken,
                        for: flight.identity.profileID
                    )
                }
                cache(
                    token,
                    identity: flight.identity,
                    sessionFence: flight.sessionFence
                )
            }
            return token.accessToken
        } catch {
            if refreshFlight?.id == flight.id { refreshFlight = nil }
            throw error
        }
    }

    private func invalidateRefreshToken(
        authorizationEpoch expectedEpoch: UInt64,
        identity: SessionIdentity,
        sessionFence: SpotifySessionFence
    ) throws {
        guard authorizationEpoch == expectedEpoch,
              activeIdentity == identity else { throw CancellationError() }
        _ = try sessionBlockRegistry.blockIfAllowed(sessionFence)
        authorizationEpoch &+= 1
        refreshFlight?.task.cancel()
        refreshFlight = nil
        cachedAccessToken = nil
        cachedSessionFence = nil
        accessTokenExpiry = .distantPast
        reauthorizationBlockedIdentity = identity
        do {
            try tokenStore.deleteRefreshToken(for: identity.profileID)
        } catch {
            throw SpotifySessionError.credentialCleanupFailed
        }
    }

    private func cache(
        _ token: SpotifySessionTokenResponse,
        identity: SessionIdentity,
        sessionFence: SpotifySessionFence
    ) {
        activeIdentity = identity
        cachedAccessToken = token.accessToken
        cachedSessionFence = sessionFence
        accessTokenExpiry = now().addingTimeInterval(TimeInterval(max(60, token.expiresIn - 30)))
    }

    @discardableResult
    private func prepare(for account: SpotifyPlaybackAccount) -> SessionIdentity {
        let identity = SessionIdentity(account: account)
        guard activeIdentity != identity else { return identity }
        authorizationEpoch &+= 1
        refreshFlight?.task.cancel()
        refreshFlight = nil
        cachedAccessToken = nil
        cachedSessionFence = nil
        accessTokenExpiry = .distantPast
        activeIdentity = identity
        return identity
    }

    private func requestToken(
        parameters: [String: String],
        clientAuthentication: TokenClientAuthentication,
        grant: TokenGrant,
        authorizationEpoch requestEpoch: UInt64,
        operationFence: TokenOperationFence,
        retryNumber: Int = 0
    ) async throws -> SpotifySessionTokenResponse {
        guard authorizationEpoch == requestEpoch else { throw CancellationError() }
        try requireCurrent(operationFence)
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if case .basic(let clientID, let clientSecret) = clientAuthentication {
            let value = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
            request.setValue("Basic \(value)", forHTTPHeaderField: "Authorization")
        }
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await perform(request)
        } catch {
            let failure = SpotifyNetworkFailureClassifier.classify(underlyingError: error, now: now())
            if failure == .cancelled { throw CancellationError() }
            throw failure
        }
        try requireCurrent(operationFence)

        guard !(200..<300).contains(http.statusCode) else {
            return try JSONDecoder.spotify.decode(SpotifySessionTokenResponse.self, from: data)
        }

        let failure = classify(http: http, data: data)
        if failure == .invalidGrant,
           grant == .refreshToken,
           let activeIdentity,
           case .session(let sessionFence) = operationFence {
            try invalidateRefreshToken(
                authorizationEpoch: requestEpoch,
                identity: activeIdentity,
                sessionFence: sessionFence
            )
            throw SpotifySessionError.reauthorizationRequired
        }
        let isExplicitlyRetryableRefreshResponse: Bool = switch failure {
        case .rateLimited, .server:
            true
        case .invalidGrant, .unauthorized, .forbidden, .offline, .cancelled,
             .client, .transport:
            false
        }
        let nextRetryNumber = retryNumber + 1
        if grant == .refreshToken,
           isExplicitlyRetryableRefreshResponse,
           let delay = retryPolicy.delay(
               for: failure,
               retryNumber: nextRetryNumber
           ) {
            try await sleep(delay)
            guard authorizationEpoch == requestEpoch else { throw CancellationError() }
            try requireCurrent(operationFence)
            return try await requestToken(
                parameters: parameters,
                clientAuthentication: clientAuthentication,
                grant: grant,
                authorizationEpoch: requestEpoch,
                operationFence: operationFence,
                retryNumber: nextRetryNumber
            )
        }
        throw failure
    }

    private func requireCurrent(_ fence: TokenOperationFence) throws {
        switch fence {
        case .authorization(let authorizationFence):
            try sessionBlockRegistry.validateAuthorizationFence(authorizationFence)
        case .session(let sessionFence):
            try sessionBlockRegistry.validateSessionFence(sessionFence)
        }
    }

    private func fetchProfile(account: SpotifyPlaybackAccount) async throws -> SpotifyConnectionReport {
        let (data, _) = try await authorizedRequest(
            account: account,
            method: "GET",
            url: URL(string: "https://api.spotify.com/v1/me")!,
            operation: .read
        )
        let profile = try JSONDecoder.spotify.decode(SpotifyProfileResponse.self, from: data)
        return SpotifyConnectionReport(displayName: profile.displayName ?? profile.id)
    }

    private func authorizedRequest(
        account: SpotifyPlaybackAccount,
        method: String,
        url: URL,
        operation: SpotifyRequestOperation
    ) async throws -> (Data, HTTPURLResponse) {
        let sessionFence = try sessionBlockRegistry.sessionFence(for: account.profileID)
        var token = try await accessToken(account: account, sessionFence: sessionFence)
        var didRefreshAfterUnauthorized = false
        var retryNumber = 0

        while true {
            try sessionBlockRegistry.validateSessionFence(sessionFence)
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let result: Result<(Data, HTTPURLResponse), SpotifyNetworkFailure>
            do {
                result = .success(try await perform(request))
            } catch {
                let failure = SpotifyNetworkFailureClassifier.classify(
                    underlyingError: error,
                    now: now()
                )
                if failure == .cancelled { throw CancellationError() }
                result = .failure(failure)
            }
            try sessionBlockRegistry.validateSessionFence(sessionFence)

            switch result {
            case .success(let (data, http)) where (200..<300).contains(http.statusCode):
                return (data, http)
            case .success(let (data, http)):
                let failure = classify(http: http, data: data)
                if failure == .unauthorized, !didRefreshAfterUnauthorized {
                    cachedAccessToken = nil
                    cachedSessionFence = nil
                    accessTokenExpiry = .distantPast
                    token = try await accessToken(
                        account: account,
                        forceRefresh: true,
                        sessionFence: sessionFence
                    )
                    didRefreshAfterUnauthorized = true
                    continue
                }
                if failure == .unauthorized {
                    try invalidateRefreshToken(
                        authorizationEpoch: authorizationEpoch,
                        identity: SessionIdentity(account: account),
                        sessionFence: sessionFence
                    )
                    throw SpotifySessionError.reauthorizationRequired
                }
                try await retryOrThrow(failure, operation: operation, retryNumber: &retryNumber)
            case .failure(let failure):
                try await retryOrThrow(failure, operation: operation, retryNumber: &retryNumber)
            }
        }
    }

    private func retryOrThrow(
        _ failure: SpotifyNetworkFailure,
        operation: SpotifyRequestOperation,
        retryNumber: inout Int
    ) async throws {
        guard operation.permitsAutomaticRetry(for: failure) else { throw failure }
        retryNumber += 1
        guard let delay = retryPolicy.delay(for: failure, retryNumber: retryNumber) else {
            throw failure
        }
        try await sleep(delay)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifySessionError.invalidResponse
        }
        return (data, http)
    }

    private func classify(http: HTTPURLResponse, data: Data) -> SpotifyNetworkFailure {
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        return SpotifyNetworkFailureClassifier.classify(
            statusCode: http.statusCode,
            headers: headers,
            responseBody: data,
            now: now()
        )
    }
}

@MainActor
final class SpotifyPlaybackAdapter: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?

    private enum MutationLane: Hashable {
        case playback
        case navigation
        case seek
        case liked
        case shuffle
        case repeatMode
        case volume

        static let allReconciled: [Self] = [
            .playback,
            .shuffle,
            .repeatMode,
            .volume,
        ]
    }

    private enum OptimisticValue: Equatable {
        case playback(Bool)
        case shuffle(Bool)
        case repeatMode(RepeatMode)
        case volume(Double?)
    }

    private struct PendingOptimisticMutation {
        let generation: UInt64
        let trackID: String
        let desiredValue: OptimisticValue
        var confirmationDeadline: TimeInterval?
    }

    private struct PollContext {
        let sequence: UInt64
        let mutationGenerations: [MutationLane: UInt64]
    }

    private let sessionBroker: any SpotifyPlaybackSessionServing
    private let accountProvider: any SpotifyPlaybackAccountProviding
    private let monotonicNow: () -> TimeInterval
    private let optimisticConfirmationWindow: TimeInterval
    private var pollingTask: Task<Void, Never>?
    private var projectionTask: Task<Void, Never>?
    private var sourceSnapshot: PlaybackSnapshot?
    private var latestSnapshot: PlaybackSnapshot?
    private var playbackClock = PlaybackClock()
    private var likedSongs = LikedSongsCoordinator()
    private var likedTrackID: String?
    private var mutationGenerations: [MutationLane: UInt64] = [:]
    private var mutationTasks: [MutationLane: Task<Void, Never>] = [:]
    private var pendingOptimisticMutations: [MutationLane: PendingOptimisticMutation] = [:]
    private var nextPollSequence: UInt64 = 0
    private var lastAppliedPollSequence: UInt64 = 0

    init(
        sessionBroker: any SpotifyPlaybackSessionServing,
        accountProvider: any SpotifyPlaybackAccountProviding,
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        optimisticConfirmationWindow: TimeInterval = 3
    ) {
        self.sessionBroker = sessionBroker
        self.accountProvider = accountProvider
        self.monotonicNow = monotonicNow
        self.optimisticConfirmationWindow = max(0, optimisticConfirmationWindow)
    }

    func start() {
        projectionTask?.cancel()
        restartPolling(forceLikedRefresh: false)
        projectionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 83_333_333)
                guard !Task.isCancelled else { return }
                self?.publishProjection()
            }
        }
    }

    func refreshPlayback() async {
        _ = await pollOnce(forceLikedRefresh: false)
    }

    func refreshAccountState() async {
        _ = await pollOnce(forceLikedRefresh: true)
    }

    func requestImmediateAccountRefresh() {
        restartPolling(forceLikedRefresh: true)
    }

    func send(_ command: PlaybackCommand) {
        guard let originalSnapshot = latestSnapshot,
              let account = try? accountProvider.currentPlaybackAccount(),
              originalSnapshot.capabilities.contains(capabilityRequired(for: command)) else { return }

        let lane = mutationLane(for: command)
        let generation = nextGeneration(for: lane)
        let trackID = originalSnapshot.track.id

        var likedPermit: LikedSongsRequestPermit?
        switch command {
        case .toggleLiked:
            guard originalSnapshot.capabilities.contains(.likedSongsWrite),
                  let current = likedSongs.state.displayedValue else { return }
            likedPermit = likedSongs.beginMutation(desired: !current)
            updateLikedPresentation(for: trackID)
        case .togglePlayback:
            let desired = !originalSnapshot.isPlaying
            beginOptimisticMutation(
                lane: lane,
                generation: generation,
                trackID: trackID,
                desiredValue: .playback(desired)
            )
            playbackClock.apply(.setPlaying(desired), at: monotonicNow())
            sourceSnapshot?.isPlaying = desired
            publishProjection()
        case .seek(let position):
            playbackClock.apply(.seek(to: position), at: monotonicNow())
            publishProjection()
        case .toggleShuffle:
            let desired = !originalSnapshot.isShuffled
            beginOptimisticMutation(
                lane: lane,
                generation: generation,
                trackID: trackID,
                desiredValue: .shuffle(desired)
            )
            sourceSnapshot?.isShuffled = desired
            publishProjection()
        case .cycleRepeat:
            let desired: RepeatMode = switch originalSnapshot.repeatMode {
            case .off: .all
            case .all: .one
            case .one: .off
            }
            beginOptimisticMutation(
                lane: lane,
                generation: generation,
                trackID: trackID,
                desiredValue: .repeatMode(desired)
            )
            sourceSnapshot?.repeatMode = desired
            publishProjection()
        case .setVolume(let requestedLevel):
            let desired = min(max(requestedLevel, 0), 1)
            beginOptimisticMutation(
                lane: lane,
                generation: generation,
                trackID: trackID,
                desiredValue: .volume(desired)
            )
            sourceSnapshot?.volume = desired
            publishProjection()
        case .previous, .next:
            break
        }

        let previousTask = mutationTasks[lane]
        let task = Task { [weak self] in
            _ = await previousTask?.result
            guard let self else { return }
            defer {
                if mutationGenerations[lane] == generation {
                    mutationTasks[lane] = nil
                }
            }
            if lane != .navigation,
               !isCurrent(generation: generation, lane: lane, trackID: trackID) {
                return
            }
            do {
                if case .toggleLiked = command, let likedPermit,
                   case .mutation(let desired, _) = likedPermit.kind {
                    try await sessionBroker.setTrackSaved(desired, trackID: trackID, account: account)
                    guard isCurrent(generation: generation, lane: lane, trackID: trackID),
                          let confirmation = likedSongs.completeMutation(permit: likedPermit) else { return }
                    updateLikedPresentation(for: trackID)
                    do {
                        let confirmed = try await sessionBroker.isTrackSaved(trackID, account: account)
                        guard likedSongs.completeQuery(confirmed, permit: confirmation, at: monotonicNow()) else { return }
                        updateLikedPresentation(for: trackID)
                    } catch {
                        handleAuthorizationError(error, deniedCapabilities: .likedSongsRead)
                        guard likedSongs.failQuery(
                            permit: confirmation,
                            at: monotonicNow()
                        ) else { return }
                        updateLikedPresentation(for: trackID)
                    }
                    return
                }

                try await sessionBroker.send(command, snapshot: originalSnapshot, account: account)
                markOptimisticMutationSent(
                    lane: lane,
                    generation: generation,
                    trackID: trackID
                )
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard isCurrent(generation: generation, lane: lane, trackID: trackID) else { return }
                _ = await pollOnce(forceLikedRefresh: false)
            } catch {
                guard isCurrent(generation: generation, lane: lane, trackID: trackID) else { return }
                handleAuthorizationError(
                    error,
                    deniedCapabilities: capabilityRequired(for: command)
                )
                if case .toggleLiked = command, let likedPermit {
                    _ = likedSongs.failMutation(permit: likedPermit)
                    updateLikedPresentation(for: trackID)
                } else {
                    rollback(command, to: originalSnapshot)
                }
            }
        }
        mutationTasks[lane] = task
    }

    private func pollOnce(
        forceLikedRefresh: Bool
    ) async -> SpotifyPollingCadence.Outcome {
        guard let account = try? accountProvider.currentPlaybackAccount() else {
            publishIdle(title: "尚未连接 Spotify", artist: "请先在设置中完成授权")
            return .noAccount
        }
        let pollContext = beginPoll()
        do {
            guard var snapshot = try await sessionBroker.currentPlayback(account: account) else {
                guard accept(pollContext: pollContext) else { return .idle }
                expireOptimisticMutations(at: monotonicNow())
                guard pendingOptimisticMutations.isEmpty,
                      !hasMutationNewerThan(pollContext) else { return .idle }
                publishIdle(title: "Spotify 未在播放", artist: "播放一首歌曲后会自动显示")
                return .idle
            }
            snapshot.source = .web
            guard accept(pollContext: pollContext) else { return .playbackAvailable }
            reconcileOptimisticMutations(into: &snapshot, pollContext: pollContext)
            let likedPermit: LikedSongsRequestPermit?
            if likedTrackID != snapshot.track.id {
                likedTrackID = snapshot.track.id
                likedPermit = likedSongs.selectTrack(
                    snapshot.track.id,
                    accountCapability: snapshot.capabilities.contains(.likedSongsRead)
                )
            } else if forceLikedRefresh || likedSongs.shouldRefresh(at: monotonicNow()) {
                likedPermit = likedSongs.beginRefresh()
            } else {
                likedPermit = nil
            }
            snapshot.likedState = likedSongs.state
            publishSource(snapshot)

            if let likedPermit {
                do {
                    let value = try await sessionBroker.isTrackSaved(snapshot.track.id, account: account)
                    guard likedSongs.completeQuery(value, permit: likedPermit, at: monotonicNow()) else {
                        return .playbackAvailable
                    }
                } catch {
                    if Task.isCancelled {
                        _ = likedSongs.failQuery(permit: likedPermit, at: monotonicNow())
                        return pollingOutcome(for: error)
                    }
                    guard likedSongs.failQuery(
                        permit: likedPermit,
                        at: monotonicNow()
                    ) else { return pollingOutcome(for: error) }
                    handleAuthorizationError(error, deniedCapabilities: .likedSongsRead)
                    updateLikedPresentation(for: snapshot.track.id)
                    return pollingOutcome(for: error)
                }
                updateLikedPresentation(for: snapshot.track.id)
            }
            return .playbackAvailable
        } catch {
            if Task.isCancelled { return pollingOutcome(for: error) }
            handleAuthorizationError(error)
            if (error as? SpotifyNetworkFailure) == .forbidden {
                publishIdle(
                    title: "Spotify 权限不足",
                    artist: "请在设置中重新授权所需范围"
                )
            } else if latestSnapshot == nil {
                publishIdle(title: "正在连接 Spotify", artist: "Lyris 会自动重试")
            }
            return pollingOutcome(for: error)
        }
    }

    private func restartPolling(forceLikedRefresh: Bool) {
        let previousTask = pollingTask
        previousTask?.cancel()
        pollingTask = Task { [weak self] in
            _ = await previousTask?.result
            guard let self, !Task.isCancelled else { return }
            var cadence = SpotifyPollingCadence()
            var shouldForceLikedRefresh = forceLikedRefresh
            while !Task.isCancelled {
                let outcome = await pollOnce(forceLikedRefresh: shouldForceLikedRefresh)
                shouldForceLikedRefresh = false
                guard !Task.isCancelled else { return }
                let delay = cadence.nextDelay(after: outcome)
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    private func pollingOutcome(for error: Error) -> SpotifyPollingCadence.Outcome {
        guard let failure = error as? SpotifyNetworkFailure else { return .failure }
        switch failure {
        case .offline, .transport:
            return .offline
        case .invalidGrant, .unauthorized, .forbidden, .rateLimited, .server,
             .cancelled, .client:
            return .failure
        }
    }

    private func publishIdle(title: String, artist: String) {
        let snapshot = PlaybackSnapshot(
            track: Track(id: "spotify:idle", title: title, artist: artist, album: "", duration: 1),
            position: 0,
            isPlaying: false,
            likedState: .unavailable,
            isShuffled: false,
            repeatMode: .off,
            capabilities: [],
            source: .unavailable
        )
        likedTrackID = nil
        _ = likedSongs.selectTrack(nil, accountCapability: false)
        pendingOptimisticMutations.removeAll()
        playbackClock.apply(.clear, at: monotonicNow())
        publishSource(snapshot)
    }

    private func publishSource(_ snapshot: PlaybackSnapshot) {
        sourceSnapshot = snapshot
        playbackClock.apply(
            .source(
                PlaybackClockSourceSample(
                    trackID: snapshot.track.id,
                    position: snapshot.position,
                    duration: snapshot.track.duration,
                    isPlaying: snapshot.isPlaying
                )
            ),
            at: monotonicNow()
        )
        publishProjection()
    }

    private func publishProjection() {
        guard var snapshot = sourceSnapshot else { return }
        snapshot.position = playbackClock.position(at: monotonicNow())
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
    }

    private func updateLikedPresentation(for trackID: String) {
        guard sourceSnapshot?.track.id == trackID else { return }
        sourceSnapshot?.likedState = likedSongs.state
        publishProjection()
    }

    private func handleAuthorizationError(
        _ error: Error,
        deniedCapabilities: PlaybackCapabilities = []
    ) {
        if let sessionError = error as? SpotifySessionError {
            switch sessionError {
            case .reauthorizationRequired, .credentialCleanupFailed:
                onAuthorizationState?(.reauthorizationRequired)
            case .missingRefreshToken, .invalidResponse:
                onAuthorizationState?(.failed)
            }
            return
        }
        guard let failure = error as? SpotifyNetworkFailure else { return }
        switch failure {
        case .invalidGrant, .unauthorized:
            onAuthorizationState?(.reauthorizationRequired)
        case .forbidden:
            if !deniedCapabilities.isEmpty {
                sourceSnapshot?.capabilities.subtract(deniedCapabilities)
                if deniedCapabilities.contains(.likedSongsRead) {
                    sourceSnapshot?.likedState = .unavailable
                    likedTrackID = nil
                    _ = likedSongs.selectTrack(nil, accountCapability: false)
                }
                publishProjection()
            }
            onAuthorizationState?(.permissionRequired)
        case .rateLimited, .server, .offline, .cancelled, .client, .transport:
            break
        }
    }

    private func capabilityRequired(for command: PlaybackCommand) -> PlaybackCapabilities {
        switch command {
        case .togglePlayback, .previous, .next:
            .transport
        case .seek:
            .seek
        case .toggleLiked:
            .likedSongsWrite
        case .toggleShuffle:
            .shuffle
        case .cycleRepeat:
            .repeatMode
        case .setVolume:
            .volume
        }
    }

    private func rollback(_ command: PlaybackCommand, to snapshot: PlaybackSnapshot) {
        guard sourceSnapshot?.track.id == snapshot.track.id else { return }
        pendingOptimisticMutations.removeValue(forKey: mutationLane(for: command))
        switch command {
        case .togglePlayback, .seek:
            playbackClock.apply(.clear, at: monotonicNow())
            playbackClock.apply(
                .source(
                    PlaybackClockSourceSample(
                        trackID: snapshot.track.id,
                        position: snapshot.position,
                        duration: snapshot.track.duration,
                        isPlaying: snapshot.isPlaying
                    )
                ),
                at: monotonicNow()
            )
            sourceSnapshot?.isPlaying = snapshot.isPlaying
        case .toggleShuffle:
            sourceSnapshot?.isShuffled = snapshot.isShuffled
        case .cycleRepeat:
            sourceSnapshot?.repeatMode = snapshot.repeatMode
        case .setVolume:
            sourceSnapshot?.volume = snapshot.volume
        case .previous, .next, .toggleLiked:
            break
        }
        publishProjection()
    }

    private func mutationLane(for command: PlaybackCommand) -> MutationLane {
        switch command {
        case .togglePlayback: .playback
        case .previous, .next: .navigation
        case .seek: .seek
        case .toggleLiked: .liked
        case .toggleShuffle: .shuffle
        case .cycleRepeat: .repeatMode
        case .setVolume: .volume
        }
    }

    private func nextGeneration(for lane: MutationLane) -> UInt64 {
        let generation = (mutationGenerations[lane] ?? 0) &+ 1
        mutationGenerations[lane] = generation
        return generation
    }

    private func beginOptimisticMutation(
        lane: MutationLane,
        generation: UInt64,
        trackID: String,
        desiredValue: OptimisticValue
    ) {
        pendingOptimisticMutations[lane] = PendingOptimisticMutation(
            generation: generation,
            trackID: trackID,
            desiredValue: desiredValue,
            confirmationDeadline: nil
        )
    }

    private func markOptimisticMutationSent(
        lane: MutationLane,
        generation: UInt64,
        trackID: String
    ) {
        guard var pending = pendingOptimisticMutations[lane],
              pending.generation == generation,
              pending.trackID == trackID else { return }
        pending.confirmationDeadline = monotonicNow() + optimisticConfirmationWindow
        pendingOptimisticMutations[lane] = pending
    }

    private func beginPoll() -> PollContext {
        nextPollSequence &+= 1
        return PollContext(
            sequence: nextPollSequence,
            mutationGenerations: mutationGenerations
        )
    }

    private func accept(pollContext: PollContext) -> Bool {
        guard pollContext.sequence > lastAppliedPollSequence else { return false }
        lastAppliedPollSequence = pollContext.sequence
        return true
    }

    private func hasMutationNewerThan(_ pollContext: PollContext) -> Bool {
        MutationLane.allReconciled.contains { lane in
            generation(for: lane, in: pollContext.mutationGenerations)
                != generation(for: lane, in: mutationGenerations)
        }
    }

    private func reconcileOptimisticMutations(
        into snapshot: inout PlaybackSnapshot,
        pollContext: PollContext
    ) {
        guard let current = sourceSnapshot,
              current.track.id == snapshot.track.id else {
            pendingOptimisticMutations.removeAll()
            return
        }

        for lane in MutationLane.allReconciled {
            let pollGeneration = generation(for: lane, in: pollContext.mutationGenerations)
            let currentGeneration = generation(for: lane, in: mutationGenerations)
            if pollGeneration != currentGeneration {
                apply(value(for: lane, in: current), to: &snapshot)
                continue
            }

            guard let pending = pendingOptimisticMutations[lane],
                  pending.generation == currentGeneration,
                  pending.trackID == snapshot.track.id else { continue }

            let incomingValue = value(for: lane, in: snapshot)
            if pending.confirmationDeadline != nil,
               incomingValue == pending.desiredValue {
                pendingOptimisticMutations.removeValue(forKey: lane)
                continue
            }

            if pending.confirmationDeadline == nil
                || monotonicNow() <= (pending.confirmationDeadline ?? -.infinity) {
                apply(pending.desiredValue, to: &snapshot)
            } else {
                pendingOptimisticMutations.removeValue(forKey: lane)
            }
        }
    }

    private func expireOptimisticMutations(at time: TimeInterval) {
        pendingOptimisticMutations = pendingOptimisticMutations.filter { _, pending in
            guard let deadline = pending.confirmationDeadline else { return true }
            return time <= deadline
        }
    }

    private func generation(
        for lane: MutationLane,
        in generations: [MutationLane: UInt64]
    ) -> UInt64 {
        generations[lane] ?? 0
    }

    private func value(for lane: MutationLane, in snapshot: PlaybackSnapshot) -> OptimisticValue {
        switch lane {
        case .playback:
            .playback(snapshot.isPlaying)
        case .shuffle:
            .shuffle(snapshot.isShuffled)
        case .repeatMode:
            .repeatMode(snapshot.repeatMode)
        case .volume:
            .volume(snapshot.volume)
        case .navigation, .seek, .liked:
            preconditionFailure("Lane \(lane) does not use optimistic reconciliation")
        }
    }

    private func apply(_ value: OptimisticValue, to snapshot: inout PlaybackSnapshot) {
        switch value {
        case .playback(let isPlaying):
            snapshot.isPlaying = isPlaying
        case .shuffle(let isShuffled):
            snapshot.isShuffled = isShuffled
        case .repeatMode(let repeatMode):
            snapshot.repeatMode = repeatMode
        case .volume(let volume):
            snapshot.volume = volume
        }
    }

    private func isCurrent(
        generation: UInt64,
        lane: MutationLane,
        trackID: String
    ) -> Bool {
        mutationGenerations[lane] == generation && sourceSnapshot?.track.id == trackID
    }

    deinit {
        pollingTask?.cancel()
        projectionTask?.cancel()
        mutationTasks.values.forEach { $0.cancel() }
    }
}

enum SpotifyPlaybackError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        "Spotify 尚未授权。"
    }
}

enum SpotifySessionError: LocalizedError, Equatable {
    case reauthorizationRequired
    case credentialCleanupFailed
    case missingRefreshToken
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .reauthorizationRequired:
            "Spotify 授权已过期，请重新授权。"
        case .credentialCleanupFailed:
            "Spotify 授权已过期，但旧令牌未能从 Keychain 删除；已停止自动重试。"
        case .missingRefreshToken:
            "Spotify 没有返回刷新令牌。"
        case .invalidResponse:
            "Spotify 没有返回有效的 HTTP 响应。"
        }
    }
}

private struct SpotifySessionTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let scope: String?
}

private struct SpotifyProfileResponse: Decodable {
    let id: String
    let displayName: String?
}

private struct SpotifyPlayerState: Decodable {
    struct Device: Decodable {
        let volumePercent: Int?
    }

    struct Item: Decodable {
        struct Artist: Decodable { let name: String }
        struct Image: Decodable { let url: URL }
        struct Album: Decodable {
            let name: String
            let images: [Image]
        }
        struct Show: Decodable {
            let name: String
            let publisher: String?
        }
        let id: String
        let uri: String?
        let name: String
        let durationMs: Int
        let artists: [Artist]?
        let album: Album?
        let show: Show?
        let images: [Image]?
    }

    let progressMs: Int?
    let isPlaying: Bool
    let shuffleState: Bool
    let repeatState: String
    let currentlyPlayingType: String?
    let device: Device?
    let item: Item?
}

private enum SpotifyAPIError {
    static func message(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(SpotifyWebAPIErrorEnvelope.self, from: data) {
            return envelope.error.message
        }
        if let envelope = try? JSONDecoder.spotify.decode(SpotifyTokenErrorEnvelope.self, from: data) {
            return envelope.errorDescription ?? envelope.error
        }
        return nil
    }
}

private struct SpotifyWebAPIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

private struct SpotifyTokenErrorEnvelope: Decodable {
    let error: String
    let errorDescription: String?
}

extension JSONDecoder {
    static var spotify: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
