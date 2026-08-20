import Foundation
import XCTest
@testable import Lyris

@MainActor
final class PlaybackItemKindTests: XCTestCase {
    func testEpisodeAdvertisementAndUnknownDoNotRequestLikedStateOrRetainTrackValue() async {
        let session = ItemKindSpotifySession(
            playback: [
                itemSnapshot(id: "spotify:track:A", kind: .track, capabilities: .accountPlayback),
                itemSnapshot(id: "spotify:episode:B", kind: .episode, capabilities: .localCompanion),
                itemSnapshot(id: "spotify:advertisement", kind: .advertisement, capabilities: [.transport]),
                itemSnapshot(id: "spotify:unknown:C", kind: .unknown, capabilities: .localCompanion),
            ],
            likedValues: [true]
        )
        let adapter = makeItemKindAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.likedState, .value(true))
        XCTAssertEqual(received.last?.source, .web)
        var likedReadCount = await session.likedReadCount
        XCTAssertEqual(likedReadCount, 1)

        for expectedKind in [PlaybackItemKind.episode, .advertisement, .unknown] {
            await adapter.refreshPlayback()
            XCTAssertEqual(received.last?.track.kind, expectedKind)
            XCTAssertEqual(received.last?.likedState, .unavailable)
            XCTAssertEqual(received.last?.source, .web)
            likedReadCount = await session.likedReadCount
            XCTAssertEqual(likedReadCount, 1)
        }
    }

    func testEachTrackStillRequestsAndPublishesItsOwnLikedState() async {
        let session = ItemKindSpotifySession(
            playback: [
                itemSnapshot(id: "spotify:track:A", kind: .track, capabilities: .accountPlayback),
                itemSnapshot(id: "spotify:track:B", kind: .track, capabilities: .accountPlayback),
            ],
            likedValues: [true, false]
        )
        let adapter = makeItemKindAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.likedState, .value(true))
        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.likedState, .value(false))
        let likedReadCount = await session.likedReadCount
        XCTAssertEqual(likedReadCount, 2)
    }

    func testNoWebPlaybackPublishesUnavailableSource() async {
        let session = ItemKindSpotifySession(playback: [nil], likedValues: [])
        let adapter = makeItemKindAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()

        XCTAssertEqual(received.last?.source, .unavailable)
        XCTAssertEqual(received.last?.likedState, .unavailable)
        let likedReadCount = await session.likedReadCount
        XCTAssertEqual(likedReadCount, 0)
    }
}

private actor ItemKindSpotifySession: SpotifyPlaybackSessionServing {
    private var playback: [PlaybackSnapshot?]
    private var likedValues: [Bool]
    private(set) var likedReadCount = 0

    init(playback: [PlaybackSnapshot?], likedValues: [Bool]) {
        self.playback = playback
        self.likedValues = likedValues
    }

    func currentPlayback(account: SpotifyPlaybackAccount) async throws -> PlaybackSnapshot? {
        precondition(!playback.isEmpty, "Unexpected playback read")
        return playback.removeFirst()
    }

    func isTrackSaved(_ trackID: String, account: SpotifyPlaybackAccount) async throws -> Bool {
        likedReadCount += 1
        precondition(!likedValues.isEmpty, "Unexpected liked-state read for \(trackID)")
        return likedValues.removeFirst()
    }

    func setTrackSaved(_ saved: Bool, trackID: String, account: SpotifyPlaybackAccount) async throws {}
    func send(_ command: PlaybackCommand, snapshot: PlaybackSnapshot, account: SpotifyPlaybackAccount) async throws {}
}

@MainActor
private func makeItemKindAdapter(session: ItemKindSpotifySession) -> SpotifyPlaybackAdapter {
    return SpotifyPlaybackAdapter(
        sessionBroker: session,
        accountProvider: ItemKindAccountProvider(),
        monotonicNow: { 100 }
    )
}

@MainActor
private final class ItemKindAccountProvider: SpotifyPlaybackAccountProviding {
    func currentPlaybackAccount() throws -> SpotifyPlaybackAccount? {
        SpotifyPlaybackAccount(
            profile: SpotifyAuthorizationProfile(
                displayName: "Fixture",
                clientID: "client-fixture",
                redirectURI: "http://127.0.0.1:43821/oauth/callback"
            )
        )
    }
}

private func itemSnapshot(
    id: String,
    kind: PlaybackItemKind,
    capabilities: PlaybackCapabilities
) -> PlaybackSnapshot {
    PlaybackSnapshot(
        track: Track(
            id: id,
            title: "Fixture \(kind.rawValue)",
            artist: "Fixture Artist",
            album: "Fixture Album",
            duration: 180,
            kind: kind
        ),
        position: 30,
        isPlaying: true,
        likedState: .unknown,
        isShuffled: false,
        repeatMode: .off,
        capabilities: capabilities
    )
}
