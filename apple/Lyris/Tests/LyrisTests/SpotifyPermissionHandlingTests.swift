import Foundation
import XCTest
@testable import Lyris

@MainActor
final class SpotifyPermissionHandlingTests: XCTestCase {
    func testPlayback403PublishesPermissionStateAndClearsStaleCapabilities() async {
        let session = PermissionHandlingSession()
        let adapter = SpotifyPlaybackAdapter(
            sessionBroker: session,
            accountProvider: PermissionHandlingAccountProvider(),
            monotonicNow: { 100 }
        )
        var snapshots: [PlaybackSnapshot] = []
        var states: [SpotifyAuthorizationState] = []
        adapter.onSnapshot = { snapshots.append($0) }
        adapter.onAuthorizationState = { states.append($0) }

        await adapter.refreshPlayback()
        await adapter.refreshPlayback()

        XCTAssertEqual(states.last, .permissionRequired)
        XCTAssertEqual(snapshots.last?.track.id, "spotify:idle")
        XCTAssertEqual(snapshots.last?.capabilities, [])
        XCTAssertEqual(snapshots.last?.likedState, .unavailable)
    }
}

@MainActor
private final class PermissionHandlingAccountProvider: SpotifyPlaybackAccountProviding {
    private let account = SpotifyPlaybackAccount(
        profile: SpotifyAuthorizationProfile(
            displayName: "Fixture",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
    )

    func currentPlaybackAccount() throws -> SpotifyPlaybackAccount? { account }
}

private actor PermissionHandlingSession: SpotifyPlaybackSessionServing {
    private var requestCount = 0

    func currentPlayback(account: SpotifyPlaybackAccount) async throws -> PlaybackSnapshot? {
        requestCount += 1
        guard requestCount == 1 else { throw SpotifyNetworkFailure.forbidden }
        return PlaybackSnapshot(
            track: Track(
                id: "spotify:track:permission-fixture",
                title: "Fixture",
                artist: "Lyris",
                album: "Tests",
                duration: 180
            ),
            position: 42,
            isPlaying: true,
            likedState: .value(true),
            isShuffled: false,
            repeatMode: .off,
            capabilities: .accountPlayback,
            source: .web
        )
    }

    func isTrackSaved(_ trackID: String, account: SpotifyPlaybackAccount) async throws -> Bool {
        true
    }

    func setTrackSaved(
        _ saved: Bool,
        trackID: String,
        account: SpotifyPlaybackAccount
    ) async throws {}

    func send(
        _ command: PlaybackCommand,
        snapshot: PlaybackSnapshot,
        account: SpotifyPlaybackAccount
    ) async throws {}
}
