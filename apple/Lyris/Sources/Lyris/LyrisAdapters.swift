import AppKit
import Foundation
import Network
import Security

@MainActor
final class DemoPlaybackAdapter: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?

    private var snapshot = PlaybackSnapshot(
        track: Track(
            id: "demo:track:northbound",
            title: "Northbound",
            artist: "Lyris Demo",
            album: "Aurora Sessions",
            duration: 161,
            artworkURL: LyrisAssets.demoArtworkURL
        ),
        position: 76,
        isPlaying: true,
        isLiked: true,
        isShuffled: false,
        repeatMode: .off,
        source: .demo
    )
    private var timer: Timer?

    func start() {
        onSnapshot?(snapshot)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.snapshot.isPlaying else { return }
                self.snapshot.position = min(self.snapshot.position + 1, self.snapshot.track.duration)
                self.onSnapshot?(self.snapshot)
            }
        }
    }

    func send(_ command: PlaybackCommand) {
        switch command {
        case .togglePlayback:
            snapshot.isPlaying.toggle()
        case .previous:
            snapshot.position = 0
        case .next:
            snapshot.position = 0
        case .seek(let position):
            snapshot.position = min(max(position, 0), snapshot.track.duration)
        case .toggleLiked:
            snapshot.isLiked.toggle()
        case .toggleShuffle:
            snapshot.isShuffled.toggle()
        case .cycleRepeat:
            snapshot.repeatMode = switch snapshot.repeatMode {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        case .setVolume(let level):
            snapshot.volume = min(max(level, 0), 1)
        }
        onSnapshot?(snapshot)
    }

    deinit {
        timer?.invalidate()
    }
}

struct DemoLyricsProvider: LyricsProviding {
    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        LyricsProviderResult(
            sourceID: "demo:static-v1",
            lyrics: [
                TimedLyric(startTime: 48, original: "Follow the green light over the ridge", translation: "沿着越过山脊的绿光前行"),
                TimedLyric(startTime: 62, original: "Every quiet road is opening", translation: "每一条安静的路都在展开"),
                TimedLyric(startTime: 74, original: "Keep the rhythm, moving north", translation: "跟随节奏，向北前行"),
                TimedLyric(startTime: 88, original: "The night makes room for a clearer sky", translation: "夜色为更澄澈的天空让路"),
                TimedLyric(startTime: 103, original: "We carry the chorus into morning", translation: "我们把副歌带进清晨"),
                TimedLyric(startTime: 119, original: "No borrowed words, no fading signal", translation: "不借来的言语，也没有消退的信号"),
                TimedLyric(startTime: 137, original: "Northbound, the horizon answers", translation: "向北而行，地平线回应")
            ],
            trackID: track.id,
            provider: "Demo"
        )
    }
}

struct HTTPTranslationAdapter: TranslationProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func testConnection(
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> TranslationConnectionReport {
        let startedAt = ContinuousClock.now
        switch configuration.provider {
        case .deepL:
            try await testDeepL(configuration: configuration, apiKey: apiKey)
            return TranslationConnectionReport(
                models: [],
                suggestedModel: "",
                latencyMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        case .deepSeek, .openAI, .custom:
            let models = try await fetchModels(configuration: configuration, apiKey: apiKey)
            let suggested = preferredModel(for: configuration.provider, in: models, fallback: configuration.model)
            var probeConfiguration = configuration
            probeConfiguration.model = suggested
            _ = try await requestChat(
                messages: [["role": "user", "content": "Reply with exactly OK"]],
                configuration: probeConfiguration,
                apiKey: apiKey,
                maxTokens: 8
            )
            return TranslationConnectionReport(
                models: models,
                suggestedModel: suggested,
                latencyMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        }
    }

    func translate(
        lines: [String],
        targetLanguage: String,
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String] {
        guard !lines.isEmpty else { return [] }
        if configuration.provider == .deepL {
            return try await translateWithDeepL(
                lines: lines,
                targetLanguage: targetLanguage,
                configuration: configuration,
                apiKey: apiKey
            )
        }

        var requestPayload: [String: Any] = ["lines": lines]
        if let song = configuration.songContext {
            requestPayload["song"] = [
                "title": song.title,
                "artist": song.artist,
                "album": song.album ?? "",
            ]
        }
        let encodedLines = try String(
            data: JSONSerialization.data(withJSONObject: requestPayload),
            encoding: .utf8
        ) ?? #"{"lines":[]}"#
        let content = try await requestChat(
            messages: [
                [
                    "role": "system",
                    "content": LyricsTranslationPrompt.systemMessage(
                        targetLanguage: targetLanguage,
                        style: configuration.style
                    ),
                ],
                ["role": "user", "content": encodedLines],
            ],
            configuration: configuration,
            apiKey: apiKey,
            maxTokens: max(256, lines.count * 80)
        )
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let translations = try? JSONDecoder().decode([String].self, from: data),
              translations.count == lines.count else {
            throw TranslationAdapterError.invalidResponse("服务返回的译文不是等长 JSON 数组。")
        }
        return translations
    }

    private func fetchModels(
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String] {
        var request = URLRequest(url: try endpoint(configuration.baseURL, path: "models"))
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let payload = try JSONDecoder().decode(ModelListResponse.self, from: data)
        let models = payload.data.map(\.id).sorted()
        guard !models.isEmpty else { throw TranslationAdapterError.invalidResponse("服务没有返回可用模型。") }
        return models
    }

    private func requestChat(
        messages: [[String: String]],
        configuration: TranslationConfiguration,
        apiKey: String,
        maxTokens: Int
    ) async throws -> String {
        guard !configuration.model.isEmpty else { throw TranslationAdapterError.missingModel }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": maxTokens,
        ]
        if configuration.provider == .deepSeek {
            body["thinking"] = ["type": configuration.thinkingEnabled ? "enabled" : "disabled"]
        }
        var request = URLRequest(url: try endpoint(configuration.baseURL, path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let payload = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = payload.choices.first?.message.content, !content.isEmpty else {
            throw TranslationAdapterError.invalidResponse("服务没有返回文本。")
        }
        return content
    }

    private func testDeepL(configuration: TranslationConfiguration, apiKey: String) async throws {
        var request = URLRequest(url: try endpoint(configuration.baseURL, path: "usage"))
        request.timeoutInterval = 20
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func translateWithDeepL(
        lines: [String],
        targetLanguage: String,
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String] {
        var components = URLComponents()
        components.queryItems = lines.map { URLQueryItem(name: "text", value: $0) }
        let targetCode = TranslationTargetLanguage.allCases
            .first(where: { $0.apiName == targetLanguage })?
            .deepLCode ?? targetLanguage
        components.queryItems?.append(URLQueryItem(name: "target_lang", value: targetCode))
        var request = URLRequest(url: try endpoint(configuration.baseURL, path: "translate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let payload = try JSONDecoder().decode(DeepLTranslationResponse.self, from: data)
        guard payload.translations.count == lines.count else {
            throw TranslationAdapterError.invalidResponse("DeepL 返回的译文数量不一致。")
        }
        return payload.translations.map(\.text)
    }

    private func endpoint(_ baseURL: String, path: String) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              TranslationEndpointPolicy.allows(components) else {
            throw TranslationAdapterError.invalidBaseURL
        }
        let current = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [current, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else { throw TranslationAdapterError.invalidBaseURL }
        return url
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw TranslationAdapterError.invalidResponse("没有收到 HTTP 响应。") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw TranslationAdapterError.httpStatus(http.statusCode, detail)
        }
    }

    private func preferredModel(for provider: TranslationProvider, in models: [String], fallback: String) -> String {
        let priorities: [String] = switch provider {
        case .deepSeek: ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .openAI: ["gpt-5-mini", "gpt-4.1-mini", "gpt-4o-mini"]
        case .deepL: []
        case .custom: [fallback]
        }
        return priorities.first(where: { models.contains($0) }) ?? (models.contains(fallback) ? fallback : models[0])
    }

    private func elapsedMilliseconds(since instant: ContinuousClock.Instant) -> Int {
        let duration = instant.duration(to: .now)
        return Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}

enum TranslationAdapterError: LocalizedError {
    case invalidBaseURL
    case missingModel
    case invalidResponse(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "Base URL 无效：远程接口必须使用 https://；http:// 仅允许本机 localhost。"
        case .missingModel: "请先选择一个模型。"
        case .invalidResponse(let detail): "接口响应无法识别：\(detail)"
        case .httpStatus(let status, let detail): "连接失败（HTTP \(status)）：\(detail)"
        }
    }
}

private struct ModelListResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct DeepLTranslationResponse: Decodable {
    struct Translation: Decodable { let text: String }
    let translations: [Translation]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

@MainActor
final class SpotifyAuthorizationRuntime: SpotifyAuthorizing, SpotifyPlaybackAccountProviding {
    var onAuthorizationChanged: (() -> Void)?

    private struct AuthorizationNotificationIdentity: Equatable {
        let profileID: UUID
        let clientID: String
        let authorizedAt: Date?
        let grantedScopes: Set<String>
    }

    private struct RefreshCredentialSnapshot {
        let refreshToken: String?
    }

    private let sessionBroker: SpotifySessionBroker
    private let defaults: UserDefaults
    private let profileStore: any SpotifyAuthorizationProfileStoring
    private let tokenStore: SpotifyTokenStore
    private let coordinator: SpotifyAuthorizationCoordinator
    private var didBootstrap = false
    private var lastAuthorizationNotification: AuthorizationNotificationIdentity?

    init(
        sessionBroker: SpotifySessionBroker,
        credentialVault: CredentialVault,
        defaults: UserDefaults = .standard,
        profileStore: (any SpotifyAuthorizationProfileStoring)? = nil
    ) {
        self.sessionBroker = sessionBroker
        self.defaults = defaults
        let resolvedProfileStore = profileStore
            ?? SpotifyAuthorizationProfileStore(defaults: defaults)
        self.profileStore = resolvedProfileStore
        tokenStore = SpotifyTokenStore(vault: credentialVault)
        coordinator = SpotifyAuthorizationCoordinator(
            profileStore: resolvedProfileStore,
            tokenStore: tokenStore,
            pkceFlow: SpotifyPKCEAuthorizationFlow(exchanger: sessionBroker),
            secretFlow: SpotifySecretAuthorizationFlow(
                exchanger: sessionBroker,
                tokenStore: tokenStore
            )
        )
    }

    func configuredProfile() throws -> SpotifyAuthorizationProfile? {
        try bootstrapIfNeeded()
        let profiles = try profileStore.allProfiles()
        guard profiles.count <= 1 else {
            throw SpotifyAuthorizationCoreError.profileSelectionRequired
        }
        return profiles.first
    }

    @discardableResult
    func saveConfiguration(
        clientID: String,
        redirectURI: String
    ) throws -> SpotifyAuthorizationProfile {
        try bootstrapIfNeeded()
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw SpotifyAuthorizationCoreError.profileNotFound
        }

        if var profile = try configuredProfile() {
            let identityChanged = profile.clientID != normalizedClientID
                || profile.redirectURI != redirectURI
            let authorizationModeChanged = profile.authorizationMode != .pkce
            let resetsCredentials = identityChanged || authorizationModeChanged
            let refreshCredentialSnapshot = resetsCredentials
                ? try refreshCredentialSnapshot(for: profile)
                : nil
            do {
                if resetsCredentials {
                    sessionBroker.blockSession(profileID: profile.id)
                    try tokenStore.deleteRefreshToken(for: profile.id)
                    profile.authorizedAt = nil
                    profile.grantedScopes = []
                    lastAuthorizationNotification = nil
                }
                profile.clientID = normalizedClientID
                profile.authorizationMode = .pkce
                profile.redirectURI = redirectURI
                try coordinator.saveProfile(profile)
            } catch let error as SpotifyAuthorizationCoreError
                where error == .credentialCleanupFailed {
                // A same-identity PKCE save does not normally reset the
                // session. If Keychain cleanup cannot be verified, persist a
                // fence before surfacing the error so a cached Access Token or
                // surviving Refresh Token cannot keep the account path alive.
                if !resetsCredentials {
                    sessionBroker.blockSession(profileID: profile.id)
                }
                lastAuthorizationNotification = nil
                defaults.removeObject(
                    forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey
                )
                throw error
            } catch {
                if let refreshCredentialSnapshot {
                    do {
                        try restoreRefreshCredentialSnapshot(
                            refreshCredentialSnapshot,
                            for: profile.id
                        )
                    } catch {
                        throw SpotifyAuthorizationCoreError.credentialRollbackFailed
                    }
                }
                throw error
            }
            defaults.removeObject(forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey)
            return profile
        }

        let profile = SpotifyAuthorizationProfile(
            displayName: "Spotify",
            clientID: normalizedClientID,
            redirectURI: redirectURI
        )
        try coordinator.saveProfile(profile)
        defaults.removeObject(forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey)
        return profile
    }

    func currentPlaybackAccount() throws -> SpotifyPlaybackAccount? {
        guard let profile = try configuredProfile() else { return nil }
        try SpotifyProductAuthorizationPolicy.requireEnabled(profile.authorizationMode)
        return SpotifyPlaybackAccount(profile: profile)
    }

    func restoreConnection(clientID: String, redirectURI: String) async throws -> SpotifyConnectionReport? {
        guard let profile = try configuredProfile(),
              profile.clientID == clientID,
              profile.redirectURI == redirectURI else { return nil }
        try SpotifyProductAuthorizationPolicy.requireEnabled(profile.authorizationMode)
        guard let refreshToken = try tokenStore.refreshToken(for: profile.id),
              !refreshToken.isEmpty else { return nil }
        notifyAuthorizationChanged(for: profile)
        // The persisted refresh credential is the local restore boundary.
        // Playback/profile validation belongs to SpotifyPlaybackAdapter and
        // runs in the background. Waiting on /v1/me here made a completed
        // authorization look stuck whenever that request was slow or retried.
        return SpotifyConnectionReport(displayName: profile.displayName, profile: profile)
    }

    func authorize(clientID: String, redirectURI: String) async throws -> SpotifyConnectionReport {
        let profile = try saveConfiguration(clientID: clientID, redirectURI: redirectURI)
        try SpotifyProductAuthorizationPolicy.requireEnabled(profile.authorizationMode)
        guard let redirect = URL(string: profile.redirectURI), let port = redirect.port else {
            throw SpotifyAuthorizationError.invalidRedirectURI
        }
        let attempt = try coordinator.beginAuthorization(profileID: profile.id)
        let callbackServer = try SpotifyLoopbackServer(
            port: UInt16(port),
            expectedPath: redirect.path
        )
        try await callbackServer.start()

        let opened = NSWorkspace.shared.open(attempt.authorizationURL)
        guard opened else { throw SpotifyAuthorizationError.couldNotOpenBrowser }

        let callbackURL = try await withTaskCancellationHandler {
            try await callbackServer.waitForCallback(timeout: 180)
        } onCancel: {
            callbackServer.cancel()
        }
        let completion = try await coordinator.completeAuthorization(
            callbackURL: callbackURL,
            attempt: attempt
        )
        return try await finishAuthorization(completion)
    }

    /// A successful token exchange is the authorization boundary. Account
    /// profile/playback refreshes happen through the playback adapter after
    /// this returns; they must never keep the setup button in "waiting".
    func finishAuthorization(
        _ completion: SpotifyAuthorizationCompletion
    ) async throws -> SpotifyConnectionReport {
        try await sessionBroker.adoptAuthorization(completion)
        notifyAuthorizationChanged(for: completion.profile)
        return SpotifyConnectionReport(
            displayName: completion.profile.displayName,
            profile: completion.profile
        )
    }

    private func bootstrapIfNeeded() throws {
        guard !didBootstrap else { return }
        let settings = SpotifyAuthorizationUserDefaultsSettingsStore(defaults: defaults)
        let existingProfiles = try profileStore.allProfiles()
        guard existingProfiles.count <= 1 else {
            throw SpotifyAuthorizationCoreError.profileSelectionRequired
        }
        let migrator = SpotifyLegacyClientIDProfileMigrator(
            settings: settings,
            profileStore: profileStore,
            tokenStore: tokenStore
        )
        let legacyClientID = settings.string(
            forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingProfiles.isEmpty
            || existingProfiles.first?.clientID == legacyClientID {
            _ = try migrator.migrateIfNeeded()
        }
        let profiles = try profileStore.allProfiles()
        guard profiles.count <= 1 else {
            throw SpotifyAuthorizationCoreError.profileSelectionRequired
        }
        if !profiles.isEmpty {
            defaults.removeObject(forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey)
        }
        didBootstrap = true
    }

    private func refreshCredentialSnapshot(
        for profile: SpotifyAuthorizationProfile
    ) throws -> RefreshCredentialSnapshot {
        RefreshCredentialSnapshot(
            refreshToken: try tokenStore.refreshToken(for: profile.id)
        )
    }

    private func restoreRefreshCredentialSnapshot(
        _ snapshot: RefreshCredentialSnapshot,
        for profileID: UUID
    ) throws {
        if let refreshToken = snapshot.refreshToken {
            try tokenStore.storeRefreshToken(refreshToken, for: profileID)
        }
    }

    private func notifyAuthorizationChanged(for profile: SpotifyAuthorizationProfile) {
        let identity = AuthorizationNotificationIdentity(
            profileID: profile.id,
            clientID: profile.clientID,
            authorizedAt: profile.authorizedAt,
            grantedScopes: profile.grantedScopes
        )
        guard identity != lastAuthorizationNotification else { return }
        lastAuthorizationNotification = identity
        onAuthorizationChanged?()
    }
}

struct SpotifyLoopbackCallbackRoute: Equatable, Sendable {
    let port: UInt16
    let expectedPath: String

    init(port: UInt16, expectedPath: String = "/oauth/callback") throws {
        guard !expectedPath.isEmpty, expectedPath.hasPrefix("/") else {
            throw SpotifyAuthorizationError.invalidRedirectURI
        }
        self.port = port
        self.expectedPath = expectedPath
    }

    func callbackURL(forRequestTarget target: String) -> URL? {
        guard target.hasPrefix("/"), !target.hasPrefix("//"),
              let targetComponents = URLComponents(string: target),
              targetComponents.scheme == nil,
              targetComponents.host == nil else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.percentEncodedPath = targetComponents.percentEncodedPath
        components.percentEncodedQuery = targetComponents.percentEncodedQuery
        return components.url
    }

    func accepts(_ url: URL) -> Bool {
        url.scheme == "http"
            && url.host == "127.0.0.1"
            && url.port == Int(port)
            && url.path == expectedPath
    }
}

final class SpotifyLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let callbackRoute: SpotifyLoopbackCallbackRoute
    private let queue = DispatchQueue(label: "com.dyifoo.lyris.spotify-callback")
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallbackResult: Result<URL, Error>?
    private var completed = false

    init(port: UInt16, expectedPath: String = "/oauth/callback") throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw SpotifyAuthorizationError.invalidRedirectURI
        }
        callbackRoute = try SpotifyLoopbackCallbackRoute(
            port: port,
            expectedPath: expectedPath
        )
        listener = try NWListener(using: .tcp, on: endpointPort)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.readyContinuation = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.readyContinuation?.resume()
                        self.readyContinuation = nil
                    case .failed(let error):
                        self.readyContinuation?.resume(throwing: error)
                        self.readyContinuation = nil
                        self.finish(throwing: error)
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
                self.listener.start(queue: self.queue)
            }
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.pendingCallbackResult {
                    self.pendingCallbackResult = nil
                    continuation.resume(with: result)
                    return
                }
                self.callbackContinuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(throwing: SpotifyAuthorizationError.timedOut)
                }
            }
        }
    }

    func cancel() {
        queue.async {
            self.finish(throwing: CancellationError())
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.finish(throwing: error)
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first,
                  firstLine.hasPrefix("GET "),
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let url = callbackRoute.callbackURL(forRequestTarget: String(target)) else {
                self.finish(throwing: SpotifyAuthorizationError.invalidCallback)
                return
            }
            let success = callbackRoute.accepts(url)
            let title = success ? "Lyris 已收到 Spotify 授权" : "Lyris 无法识别该回调"
            let detail = success
                ? "授权码已交还 Lyris，应用正在完成安全令牌交换。现在可以关闭此页面并返回应用。"
                : "请返回 Lyris 重新开始授权。"
            let body = "<!doctype html><meta charset=\"utf-8\"><title>\(title)</title><style>body{font-family:-apple-system;padding:48px;background:#111;color:#fff}p{color:#bbb}</style><h2>\(title)</h2><p>\(detail)</p>"
            let response = "HTTP/1.1 \(success ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if success { self.finish(returning: url) }
        }
    }

    private func finish(returning url: URL) {
        guard !completed else { return }
        completed = true
        if let callbackContinuation {
            callbackContinuation.resume(returning: url)
            self.callbackContinuation = nil
        } else {
            pendingCallbackResult = .success(url)
        }
        listener.cancel()
    }

    private func finish(throwing error: Error) {
        guard !completed else { return }
        completed = true
        if let callbackContinuation {
            callbackContinuation.resume(throwing: error)
            self.callbackContinuation = nil
        } else {
            pendingCallbackResult = .failure(error)
        }
        listener.cancel()
    }
}

enum SpotifyAuthorizationError: LocalizedError {
    case invalidRedirectURI
    case invalidAuthorizationURL
    case couldNotOpenBrowser
    case stateMismatch
    case denied(String)
    case missingCode
    case missingRefreshToken
    case invalidCallback
    case timedOut
    case invalidResponse(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidRedirectURI: "Spotify Redirect URI 无效。"
        case .invalidAuthorizationURL: "无法生成 Spotify 授权地址。"
        case .couldNotOpenBrowser: "无法打开浏览器完成 Spotify 授权。"
        case .stateMismatch: "Spotify 回调校验失败，请重新授权。"
        case .denied(let message): "Spotify 授权未完成：\(message)"
        case .missingCode: "Spotify 回调没有返回授权码。"
        case .missingRefreshToken: "Spotify 没有返回刷新令牌。"
        case .invalidCallback: "Spotify 返回了无法识别的回调。"
        case .timedOut: "Spotify 授权等待超时，请重试。"
        case .invalidResponse(let detail): "Spotify 响应无法识别：\(detail)"
        case .httpStatus(let status, let detail): "Spotify 连接失败（HTTP \(status)）：\(detail)"
        }
    }
}

struct KeychainCredentialVault: CredentialVault {
    private let service = "com.dyifoo.lyris"
    private let legacyService = "com.dyifoo.melofloat"

    func read(account: String) throws -> String? {
        if let current = try read(account: account, service: service) {
            return current
        }
        guard let legacy = try read(account: account, service: legacyService) else {
            return nil
        }

        // Preserve existing Spotify/API credentials across the product rename.
        // Migration is copy-verify-delete; a failed copy leaves the legacy item
        // readable so the user is never forced to re-enter a secret.
        do {
            try write(legacy, account: account, service: service)
            if try read(account: account, service: service) == legacy {
                try? delete(account: account, service: legacyService)
            }
        } catch {
            return legacy
        }
        return legacy
    }

    private func read(account: String, service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ secret: String, account: String) throws {
        if secret.isEmpty {
            try delete(account: account)
            return
        }
        try write(secret, account: account, service: service)
    }

    private func write(_ secret: String, account: String, service: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    func delete(account: String) throws {
        var firstError: Error?
        for candidate in [service, legacyService] {
            do {
                try delete(account: account, service: candidate)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func delete(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status): "Keychain 操作失败（\(status)）"
        }
    }
}
