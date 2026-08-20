import Foundation

enum SpotifyAuthorizationMode: String, Codable, CaseIterable, Hashable, Sendable {
    case pkce
    case authorizationCodeWithSecret

    var supportedScopes: Set<String> {
        SpotifyAuthorizationScopes.accountEnhancement
    }
}

enum SpotifyAuthorizationScopes {
    static let readPlaybackState = "user-read-playback-state"
    static let modifyPlaybackState = "user-modify-playback-state"
    static let readCurrentlyPlaying = "user-read-currently-playing"
    static let readLibrary = "user-library-read"
    static let modifyLibrary = "user-library-modify"

    static let accountEnhancement: Set<String> = [
        readPlaybackState,
        modifyPlaybackState,
        readCurrentlyPlaying,
        readLibrary,
        modifyLibrary,
    ]
}

/// Product boundary for authorization modes that may be entered by the
/// shipping Lyris runtime. Experimental flows remain testable through the
/// coordinator, but persisted or externally modified profiles cannot activate
/// them without a deliberate product decision.
enum SpotifyProductAuthorizationPolicy {
    private static let enabledModes: Set<SpotifyAuthorizationMode> = [.pkce]

    static func isEnabled(_ mode: SpotifyAuthorizationMode) -> Bool {
        enabledModes.contains(mode)
    }

    static func requireEnabled(_ mode: SpotifyAuthorizationMode) throws {
        guard isEnabled(mode) else {
            throw SpotifyAuthorizationCoreError.authorizationModeUnavailable(mode)
        }
    }
}

struct SpotifyAuthorizationProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var clientID: String
    var authorizationMode: SpotifyAuthorizationMode
    var redirectURI: String
    var authorizedAt: Date?
    var grantedScopes: Set<String>

    init(
        id: UUID = UUID(),
        displayName: String,
        clientID: String,
        authorizationMode: SpotifyAuthorizationMode = .pkce,
        redirectURI: String,
        authorizedAt: Date? = nil,
        grantedScopes: Set<String> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.clientID = clientID
        self.authorizationMode = authorizationMode
        self.redirectURI = redirectURI
        self.authorizedAt = authorizedAt
        self.grantedScopes = grantedScopes
    }
}

/// Immutable credentials-free context passed through the playback boundary.
/// It identifies exactly which profile-scoped Keychain account may be used
/// without exposing a token or client secret to UI state.
struct SpotifyPlaybackAccount: Equatable, Sendable {
    let profileID: UUID
    let clientID: String
    let authorizationMode: SpotifyAuthorizationMode
    let grantedScopes: Set<String>

    init(profile: SpotifyAuthorizationProfile) {
        profileID = profile.id
        clientID = profile.clientID
        authorizationMode = profile.authorizationMode
        grantedScopes = profile.grantedScopes
    }

    var playbackCapabilities: PlaybackCapabilities {
        var capabilities: PlaybackCapabilities = []
        if grantedScopes.contains(SpotifyAuthorizationScopes.readPlaybackState) {
            capabilities.formUnion([.metadata, .remoteDevices])
        }
        if grantedScopes.contains(SpotifyAuthorizationScopes.modifyPlaybackState) {
            capabilities.formUnion([
                .transport,
                .seek,
                .shuffle,
                .repeatMode,
                .volume,
                .transferPlayback,
            ])
        }
        if grantedScopes.contains(SpotifyAuthorizationScopes.readLibrary) {
            capabilities.insert(.likedSongsRead)
        }
        if grantedScopes.contains(SpotifyAuthorizationScopes.modifyLibrary) {
            capabilities.insert(.likedSongsWrite)
        }
        return capabilities
    }
}

@MainActor
protocol SpotifyPlaybackAccountProviding: AnyObject {
    func currentPlaybackAccount() throws -> SpotifyPlaybackAccount?
}

struct SpotifyPKCEProof: CustomStringConvertible, CustomDebugStringConvertible, Equatable, Sendable {
    let verifier: String
    let challenge: String

    var description: String { "SpotifyPKCEProof(redacted)" }
    var debugDescription: String { description }
}

/// Binds a browser authorization attempt to the profile credential generation
/// that existed when the attempt started. It carries no credential material.
struct SpotifyAuthorizationFence: Equatable, Sendable {
    let profileID: UUID
    let generation: UInt64

    static func initial(for profileID: UUID) -> Self {
        Self(profileID: profileID, generation: 0)
    }
}

enum SpotifyAuthorizationSessionProof: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    case pkce(codeVerifier: String)
    case clientSecretFromTokenStore

    var description: String {
        switch self {
        case .pkce: "pkce(redacted)"
        case .clientSecretFromTokenStore: "clientSecretFromTokenStore"
        }
    }

    var debugDescription: String { description }
}

struct SpotifyAuthorizationAttempt: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    let profileID: UUID
    let clientID: String
    let mode: SpotifyAuthorizationMode
    let redirectURI: String
    let requestedScopes: Set<String>
    let authorizationURL: URL
    let state: String
    let sessionProof: SpotifyAuthorizationSessionProof
    let authorizationFence: SpotifyAuthorizationFence

    var description: String {
        "SpotifyAuthorizationAttempt(profileID: \(profileID), mode: \(mode.rawValue), scopeCount: \(requestedScopes.count))"
    }

    var debugDescription: String { description }
}

enum SpotifyTokenClientAuthentication: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    case pkce(codeVerifier: String)
    case clientSecret(String)

    var description: String {
        switch self {
        case .pkce: "pkce(redacted)"
        case .clientSecret: "clientSecret(redacted)"
        }
    }

    var debugDescription: String { description }
}

struct SpotifyAuthorizationTokenRequest: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    let profileID: UUID
    let clientID: String
    let redirectURI: String
    let authorizationCode: String
    let authentication: SpotifyTokenClientAuthentication
    let authorizationFence: SpotifyAuthorizationFence

    var description: String {
        "SpotifyAuthorizationTokenRequest(authentication: \(authentication))"
    }

    var debugDescription: String { description }

    init(
        profileID: UUID,
        clientID: String,
        redirectURI: String,
        authorizationCode: String,
        authentication: SpotifyTokenClientAuthentication,
        authorizationFence: SpotifyAuthorizationFence? = nil
    ) {
        self.profileID = profileID
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.authorizationCode = authorizationCode
        self.authentication = authentication
        self.authorizationFence = authorizationFence ?? .initial(for: profileID)
    }
}

struct SpotifyAuthorizationTokenGrant: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let grantedScopes: Set<String>?

    var description: String {
        "SpotifyAuthorizationTokenGrant(expiresIn: \(expiresIn), hasRefreshToken: \(refreshToken != nil))"
    }

    var debugDescription: String { description }

    init(
        accessToken: String,
        refreshToken: String?,
        expiresIn: Int,
        grantedScopes: Set<String>? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.grantedScopes = grantedScopes
    }
}

struct SpotifyAuthorizationCompletion: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    let profile: SpotifyAuthorizationProfile
    let accessToken: String
    let expiresIn: Int
    let authorizationFence: SpotifyAuthorizationFence

    var description: String {
        "SpotifyAuthorizationCompletion(profileID: \(profile.id), expiresIn: \(expiresIn))"
    }

    var debugDescription: String { description }

    init(
        profile: SpotifyAuthorizationProfile,
        accessToken: String,
        expiresIn: Int,
        authorizationFence: SpotifyAuthorizationFence? = nil
    ) {
        self.profile = profile
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.authorizationFence = authorizationFence ?? .initial(for: profile.id)
    }
}

protocol SpotifyAuthorizationTokenExchanging {
    func authorizationFence(for profileID: UUID) -> SpotifyAuthorizationFence
    func withValidAuthorizationFence(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> Void
    ) throws
    func exchange(_ request: SpotifyAuthorizationTokenRequest) async throws -> SpotifyAuthorizationTokenGrant
}

extension SpotifyAuthorizationTokenExchanging {
    func authorizationFence(for profileID: UUID) -> SpotifyAuthorizationFence {
        .initial(for: profileID)
    }

    func withValidAuthorizationFence(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> Void
    ) throws {
        try operation()
    }
}

enum SpotifyAuthorizationCoreError: Error, Equatable {
    case authorizationModeUnavailable(SpotifyAuthorizationMode)
    case credentialCleanupFailed
    case credentialRollbackFailed
    case profileModeMismatch
    case profileNotFound
    case profileSelectionRequired
    case attemptProfileMismatch
    case invalidRedirectURI
    case invalidAuthorizationURL
    case invalidProof
    case invalidCallback
    case stateMismatch
    case denied(String)
    case missingCode
    case missingClientSecret
    case missingRefreshToken
}

extension SpotifyAuthorizationCoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authorizationModeUnavailable:
            "Spotify 实验授权模式未启用；请保存 Client ID 后使用 PKCE 重新连接。"
        case .credentialCleanupFailed:
            "Spotify 配置已安全停用旧凭证，但 Keychain 清理未完成；请重新授权并检查旧凭证。"
        case .credentialRollbackFailed:
            "Spotify 授权配置更新失败，且凭证回滚未能完成；请检查 Keychain 后重试。"
        case .profileModeMismatch:
            "Spotify 授权方式与当前配置不一致，请重新开始授权。"
        case .profileNotFound:
            "没有找到可用的 Spotify 授权配置。"
        case .profileSelectionRequired:
            "检测到多个 Spotify 授权配置；为避免使用错误账户，账户增强已停用。请清理旧配置后重新连接。"
        case .attemptProfileMismatch:
            "Spotify 配置在授权期间已变化，请重新开始授权。"
        case .invalidRedirectURI:
            "Spotify Redirect URI 无效；请使用应用显示的本机回调地址。"
        case .invalidAuthorizationURL:
            "无法生成 Spotify 授权地址。"
        case .invalidProof:
            "无法建立安全的 Spotify 授权校验，请重试。"
        case .invalidCallback:
            "Spotify 返回了无法识别的回调。"
        case .stateMismatch:
            "Spotify 回调安全校验失败，请重新授权。"
        case .denied(let reason):
            "Spotify 授权未完成：\(reason)"
        case .missingCode:
            "Spotify 回调没有包含授权码。"
        case .missingClientSecret:
            "兼容授权方式缺少 Client Secret。"
        case .missingRefreshToken:
            "Spotify 没有返回刷新令牌，请重新授权。"
        }
    }
}
