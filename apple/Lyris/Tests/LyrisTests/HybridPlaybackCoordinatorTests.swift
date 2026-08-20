import XCTest
@testable import Lyris

@MainActor
final class HybridPlaybackCoordinatorTests: XCTestCase {
    func testLocalOwnsPlaybackFieldsWhileMatchingWebSnapshotAddsAccountState() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var received: [PlaybackSnapshot] = []
        hybrid.onSnapshot = { received.append($0) }

        hybrid.start()
        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: true))

        XCTAssertTrue(local.didStart)
        XCTAssertTrue(web.didStart)
        XCTAssertEqual(received.last?.track.title, "Local title")
        XCTAssertEqual(received.last?.position, 42)
        XCTAssertEqual(received.last?.isPlaying, true)
        XCTAssertEqual(received.last?.isShuffled, false)
        XCTAssertEqual(received.last?.repeatMode, .off)
        XCTAssertEqual(received.last?.likedState, .value(true))
        XCTAssertEqual(received.last?.source, .hybrid)
        XCTAssertTrue(received.last?.capabilities.contains(.likedSongsWrite) == true)
        XCTAssertFalse(received.last?.capabilities.contains(.remoteDevices) == true)
    }

    func testMismatchedWebTrackCannotReplaceOrEnrichActiveLocalTrack() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(localSnapshot(id: "spotify:track:B"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: true))

        XCTAssertEqual(latest?.track.id, "spotify:track:B")
        XCTAssertEqual(latest?.track.title, "Local title")
        XCTAssertEqual(latest?.likedState, .unavailable)
        XCTAssertEqual(latest?.capabilities, .localCompanion)
        XCTAssertEqual(latest?.source, .local)
    }

    func testCanonicalSpotifyURLAndURIIdentifyTheSameTrack() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(localSnapshot(id: "spotify:track:Canonical123"))
        web.emit(webSnapshot(
            id: "https://open.spotify.com/track/Canonical123?si=fixture",
            liked: true
        ))

        XCTAssertEqual(latest?.track.id, "spotify:track:Canonical123")
        XCTAssertEqual(latest?.likedState, .value(true))
        XCTAssertTrue(latest?.capabilities.contains(.likedSongsWrite) == true)
    }

    func testOrderedWebSourceCanAdvanceAheadOfANewLocalTrack() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: true))
        web.emit(webSnapshot(id: "spotify:track:B", liked: false))
        local.emit(localSnapshot(id: "spotify:track:B"))

        XCTAssertEqual(latest?.track.id, "spotify:track:B")
        XCTAssertEqual(latest?.track.title, "Local title")
        XCTAssertEqual(latest?.likedState, .value(false))
        XCTAssertEqual(latest?.source, .hybrid)
    }

    func testWebBecomesPlaybackSourceWhenLocalIsUnavailable() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(idleSnapshot())
        web.emit(webSnapshot(id: "spotify:track:REMOTE", liked: false))

        XCTAssertEqual(latest?.track.id, "spotify:track:REMOTE")
        XCTAssertEqual(latest?.track.title, "Web title")
        XCTAssertEqual(latest?.position, 7)
        XCTAssertEqual(latest?.likedState, .value(false))
        XCTAssertEqual(latest?.capabilities, .accountPlayback)
        XCTAssertEqual(latest?.source, .web)
    }

    func testPlayingWebDeviceOverridesPausedStaleLocalTrack() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(localSnapshot(id: "spotify:track:LOCAL", isPlaying: false))
        web.emit(webSnapshot(id: "spotify:track:REMOTE", liked: true, isPlaying: true))

        XCTAssertEqual(latest?.track.id, "spotify:track:REMOTE")
        XCTAssertEqual(latest?.track.title, "Web title")
        XCTAssertTrue(latest?.isPlaying == true)
        XCTAssertEqual(latest?.position, 7)
        XCTAssertEqual(latest?.likedState, .value(true))
        XCTAssertEqual(latest?.source, .web)

        hybrid.send(.next)
        hybrid.send(.toggleLiked)
        XCTAssertTrue(local.commands.isEmpty)
        XCTAssertEqual(web.commands.count, 2)
        XCTAssertTrue(web.commands.first?.isNext == true)
        XCTAssertTrue(web.commands.dropFirst().first?.isToggleLiked == true)
    }

    func testTransportUsesExactlyOneCurrentPlaybackAdapterAndLikedAlwaysUsesWeb() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        hybrid.start()
        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: false))

        hybrid.send(.togglePlayback)
        hybrid.send(.previous)
        hybrid.send(.next)
        hybrid.send(.seek(90))
        hybrid.send(.toggleShuffle)
        hybrid.send(.cycleRepeat)
        hybrid.send(.toggleLiked)

        XCTAssertEqual(local.commands.count, 6)
        XCTAssertTrue(local.commands[0].isTogglePlayback)
        XCTAssertEqual(local.commands[3].seekPosition, 90)
        XCTAssertEqual(web.commands.count, 1)
        XCTAssertTrue(web.commands[0].isToggleLiked)
    }

    func testRemoteTransportUsesWebButNeverDoubleSends() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        hybrid.start()
        local.emit(idleSnapshot())
        web.emit(webSnapshot(id: "spotify:track:REMOTE", liked: false))

        hybrid.send(.next)

        XCTAssertTrue(local.commands.isEmpty)
        XCTAssertEqual(web.commands.count, 1)
        XCTAssertTrue(web.commands[0].isNext)
    }

    func testLocalOnlyModeHidesLikedStateAndRejectsLikedCommand() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()
        local.emit(localSnapshot(id: "spotify:track:A"))

        hybrid.send(.toggleLiked)

        XCTAssertEqual(latest?.likedState, .failed(lastKnown: nil))
        XCTAssertFalse(latest?.capabilities.contains(.likedSongsRead) == true)
        XCTAssertFalse(latest?.capabilities.contains(.likedSongsWrite) == true)
        XCTAssertTrue(web.commands.isEmpty)
    }

    func testDisconnectImmediatelyRemovesWebAccountEnrichment() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()
        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: true))

        web.emitAuthorization(.disconnected)

        XCTAssertEqual(latest?.likedState, .unavailable)
        XCTAssertFalse(latest?.capabilities.contains(.likedSongsWrite) == true)
    }

    func testOldWebSnapshotCannotOverwriteNewLocalGeneration() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()
        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: true))

        local.emit(localSnapshot(id: "spotify:track:B"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: false))

        XCTAssertEqual(latest?.track.id, "spotify:track:B")
        XCTAssertEqual(latest?.track.title, "Local title")
        XCTAssertEqual(latest?.likedState, .unavailable)
        XCTAssertEqual(latest?.capabilities, .localCompanion)
    }

    func testOldWebASnapshotCannotEnrichNewLocalAGenerationAfterABA() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: true))
        XCTAssertEqual(latest?.likedState, .value(true))

        local.emit(localSnapshot(id: "spotify:track:B"))
        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: false))

        XCTAssertEqual(latest?.track.id, "spotify:track:A")
        XCTAssertEqual(latest?.track.title, "Local title")
        XCTAssertEqual(latest?.likedState, .unavailable)
        XCTAssertEqual(latest?.capabilities, .localCompanion)
        XCTAssertEqual(latest?.source, .local)

        hybrid.send(.toggleLiked)
        XCTAssertTrue(web.commands.isEmpty)

        web.emit(webSnapshot(id: "spotify:track:B", liked: false))
        XCTAssertEqual(latest?.likedState, .unavailable)
        web.emit(webSnapshot(id: "spotify:track:A", liked: true))

        XCTAssertEqual(latest?.likedState, .value(true))
        XCTAssertEqual(latest?.source, .hybrid)
        hybrid.send(.toggleLiked)
        XCTAssertEqual(web.commands.count, 1)
    }

    func testFirstObservedWebAStillCannotBindToRepeatedLocalAAfterABA() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(localSnapshot(id: "spotify:track:A"))
        local.emit(localSnapshot(id: "spotify:track:B"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: false))
        local.emit(localSnapshot(id: "spotify:track:A"))

        XCTAssertEqual(latest?.track.id, "spotify:track:A")
        XCTAssertEqual(latest?.likedState, .unavailable)
        XCTAssertEqual(latest?.capabilities, .localCompanion)
        XCTAssertEqual(latest?.source, .local)
    }

    func testFirstObservedWebAAfterRepeatedLocalAStillCannotEnrichIt() {
        let local = FakePlaybackAdapter()
        let web = FakePlaybackAdapter()
        let hybrid = HybridPlaybackAdapter(local: local, web: web)
        var latest: PlaybackSnapshot?
        hybrid.onSnapshot = { latest = $0 }
        hybrid.start()

        local.emit(localSnapshot(id: "spotify:track:A"))
        local.emit(localSnapshot(id: "spotify:track:B"))
        local.emit(localSnapshot(id: "spotify:track:A"))
        web.emit(webSnapshot(id: "spotify:track:A", liked: false))

        XCTAssertEqual(latest?.track.id, "spotify:track:A")
        XCTAssertEqual(latest?.likedState, .unavailable)
        XCTAssertEqual(latest?.capabilities, .localCompanion)
        XCTAssertEqual(latest?.source, .local)
    }
}

@MainActor
private final class FakePlaybackAdapter: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?
    private(set) var didStart = false
    private(set) var commands: [PlaybackCommand] = []

    func start() {
        didStart = true
    }

    func send(_ command: PlaybackCommand) {
        commands.append(command)
    }

    func emit(_ snapshot: PlaybackSnapshot) {
        onSnapshot?(snapshot)
    }

    func emitAuthorization(_ state: SpotifyAuthorizationState) {
        onAuthorizationState?(state)
    }
}

private extension PlaybackCommand {
    var isTogglePlayback: Bool {
        if case .togglePlayback = self { return true }
        return false
    }

    var isToggleLiked: Bool {
        if case .toggleLiked = self { return true }
        return false
    }

    var isNext: Bool {
        if case .next = self { return true }
        return false
    }

    var seekPosition: TimeInterval? {
        if case .seek(let position) = self { return position }
        return nil
    }
}

private func localSnapshot(id: String, isPlaying: Bool = true) -> PlaybackSnapshot {
    PlaybackSnapshot(
        track: Track(id: id, title: "Local title", artist: "Local artist", album: "Local album", duration: 200),
        position: 42,
        isPlaying: isPlaying,
        likedState: .unavailable,
        isShuffled: false,
        repeatMode: .off,
        capabilities: .localCompanion,
        source: .local
    )
}

private func webSnapshot(id: String, liked: Bool, isPlaying: Bool = false) -> PlaybackSnapshot {
    PlaybackSnapshot(
        track: Track(id: id, title: "Web title", artist: "Web artist", album: "Web album", duration: 201),
        position: 7,
        isPlaying: isPlaying,
        likedState: .value(liked),
        isShuffled: true,
        repeatMode: .one,
        capabilities: .accountPlayback,
        source: .web
    )
}

private func idleSnapshot() -> PlaybackSnapshot {
    PlaybackSnapshot(
        track: Track(id: "spotify:idle", title: "Idle", artist: "", album: "", duration: 1),
        position: 0,
        isPlaying: false,
        likedState: .unavailable,
        isShuffled: false,
        repeatMode: .off,
        capabilities: [],
        source: .unavailable
    )
}
