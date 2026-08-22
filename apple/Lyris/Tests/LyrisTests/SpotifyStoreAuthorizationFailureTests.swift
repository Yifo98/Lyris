import Foundation
import XCTest
@testable import Lyris

@MainActor
final class SpotifyStoreAuthorizationFailureTests: XCTestCase {
    func testChangingInterfaceLanguageRelocalizesConnectionStatus() throws {
        let (store, cleanup) = try makeStore(
            error: SpotifyAuthorizationCoreError.profileSelectionRequired
        )
        defer { cleanup() }
        XCTAssertEqual(store.spotifyConnectionStatus, "尚未配置")

        store.updateInterfaceLanguage(.english)

        XCTAssertEqual(store.spotifyConnectionStatus, "Not configured")
    }

    func testShowSettingsPublishesTheRequestedSectionToTheWindowLayer() throws {
        let (store, cleanup) = try makeStore(
            error: SpotifyAuthorizationCoreError.profileSelectionRequired
        )
        defer { cleanup() }
        var requestedSections: [SettingsSection] = []
        store.onSettingsRequested = { requestedSections.append($0) }

        store.showSettings(.appearance)

        XCTAssertEqual(store.settingsSection, .appearance)
        XCTAssertEqual(requestedSections, [.appearance])
    }

    func testCredentialCleanupFailureDisablesAccountEnhancementsAndRequestsReconnect() throws {
        let (store, cleanup) = try makeStore(
            error: SpotifyAuthorizationCoreError.credentialCleanupFailed
        )
        defer { cleanup() }
        store.updateInterfaceLanguage(.english)
        store.spotifyClientID = "fixture-client"

        store.saveSpotifyConfiguration()

        XCTAssertEqual(store.spotifyAuthorizationState, .reauthorizationRequired)
        XCTAssertFalse(store.isSpotifyConnected)
        XCTAssertTrue(store.spotifyConnectionStatus.contains("credentials need attention"))
        XCTAssertTrue(store.configurationStatus?.contains("old Client Secret") == true)
    }

    func testCredentialRollbackFailureDisablesAccountEnhancementsAndRequestsReconnect() throws {
        let (store, cleanup) = try makeStore(
            error: SpotifyAuthorizationCoreError.credentialRollbackFailed
        )
        defer { cleanup() }
        store.spotifyClientID = "fixture-client"

        store.saveSpotifyConfiguration()

        XCTAssertEqual(store.spotifyAuthorizationState, .reauthorizationRequired)
        XCTAssertFalse(store.isSpotifyConnected)
        XCTAssertTrue(store.configurationStatus?.contains("回滚") == true)
    }

    func testMultipleProfilesRemainLocalOnlyWithActionableEnglishStatus() throws {
        let (store, cleanup) = try makeStore(
            error: SpotifyAuthorizationCoreError.profileSelectionRequired
        )
        defer { cleanup() }
        store.updateInterfaceLanguage(.english)
        store.spotifyClientID = "fixture-client"

        store.saveSpotifyConfiguration()

        XCTAssertEqual(store.spotifyAuthorizationState, .disconnected)
        XCTAssertFalse(store.isSpotifyConnected)
        XCTAssertTrue(store.spotifyConnectionStatus.contains("local mode still works"))
        XCTAssertTrue(store.configurationStatus?.contains("Multiple Spotify profiles") == true)
    }

    private func makeStore(
        error: Error
    ) throws -> (store: LyrisStore, cleanup: () -> Void) {
        let suiteName = "SpotifyStoreAuthorizationFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = LyrisStore(
            playbackAdapter: AuthorizationFailurePlaybackAdapter(),
            lyricsProvider: AuthorizationFailureLyricsProvider(),
            translationAdapter: AuthorizationFailureTranslationAdapter(),
            spotifyAuthorizer: AuthorizationFailureSpotifyAuthorizer(error: error),
            credentialVault: AuthorizationFailureCredentialVault(),
            lyricsCacheStore: AuthorizationFailureLyricsCache(),
            defaults: defaults
        )
        return (store, {
            defaults.removePersistentDomain(forName: suiteName)
        })
    }
}

@MainActor
private final class AuthorizationFailurePlaybackAdapter: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?

    func start() {}
    func send(_ command: PlaybackCommand) {}
}

private struct AuthorizationFailureLyricsProvider: LyricsProviding {
    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        throw CancellationError()
    }
}

private struct AuthorizationFailureTranslationAdapter: TranslationProviding {
    func testConnection(
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> TranslationConnectionReport {
        throw CancellationError()
    }

    func translate(
        lines: [String],
        targetLanguage: String,
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String] {
        throw CancellationError()
    }
}

@MainActor
private final class AuthorizationFailureSpotifyAuthorizer: SpotifyAuthorizing {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func configuredProfile() throws -> SpotifyAuthorizationProfile? { nil }

    func saveConfiguration(
        clientID: String,
        redirectURI: String
    ) throws -> SpotifyAuthorizationProfile {
        throw error
    }

    func restoreConnection(
        clientID: String,
        redirectURI: String
    ) async throws -> SpotifyConnectionReport? {
        nil
    }

    func authorize(
        clientID: String,
        redirectURI: String
    ) async throws -> SpotifyConnectionReport {
        throw error
    }
}

private final class AuthorizationFailureCredentialVault: CredentialVault {
    func read(account: String) throws -> String? { nil }
    func write(_ secret: String, account: String) throws {}
    func delete(account: String) throws {}
}

private actor AuthorizationFailureLyricsCache: LyricsCaching {
    func loadManual(trackID: String) async -> LyricsCacheEntry? { nil }
    func loadLatestGenerated(matching key: LyricsCacheLookupKey) async -> LyricsCacheEntry? { nil }
    func loadCompatibleGeneratedFallback(matching key: LyricsCacheLookupKey) async -> LyricsCacheEntry? { nil }
    func loadGenerated(fingerprint: LyricsCacheFingerprint) async -> LyricsCacheEntry? { nil }
    func save(_ entry: LyricsCacheEntry) async throws {}
    func clearGenerated() async throws {}
    func clearManual() async throws {}
}
