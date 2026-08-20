import Foundation
import XCTest
@testable import Lyris

@MainActor
final class SpotifyRefreshOrderingTests: XCTestCase {
    func testOlderPollCannotOverwriteNewerCompletedPoll() async {
        let older = snapshot(id: "spotify:track:older")
        let newer = snapshot(id: "spotify:track:newer")
        let session = OrderingSpotifySession(playback: [older])
        let adapter = makeAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        await session.suspendNextPlaybackRead()
        let delayedPoll = Task { await adapter.refreshPlayback() }
        await session.waitUntilPlaybackReadIsSuspended()

        await session.enqueuePlayback(newer)
        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.track.id, newer.track.id)

        await session.resumeSuspendedPlayback(with: older)
        await delayedPoll.value
        XCTAssertEqual(received.last?.track.id, newer.track.id)
    }

    func testDelayedPollStartedBeforeShuffleDoesNotOverwriteOptimisticState() async {
        let initial = snapshot(isShuffled: false)
        let session = OrderingSpotifySession(playback: [initial])
        let adapter = makeAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        await session.suspendNextPlaybackRead()
        let delayedPoll = Task { await adapter.refreshPlayback() }
        await session.waitUntilPlaybackReadIsSuspended()

        adapter.send(.toggleShuffle)
        XCTAssertEqual(received.last?.isShuffled, true)

        await session.resumeSuspendedPlayback(with: initial)
        await delayedPoll.value
        XCTAssertEqual(received.last?.isShuffled, true)
    }

    func testStalePlaybackPollAfterSuccessfulCommandKeepsPendingOptimisticState() async {
        let initial = snapshot(isPlaying: false)
        let session = OrderingSpotifySession(playback: [initial])
        let adapter = makeAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        adapter.send(.togglePlayback)
        await session.waitForCommandCount(1)
        XCTAssertEqual(received.last?.isPlaying, true)

        await session.enqueuePlayback(initial)
        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.isPlaying, true)
    }

    func testServerConfirmationReleasesPlaybackOverlayForLaterExternalChanges() async {
        let initial = snapshot(isPlaying: false)
        let confirmed = snapshot(isPlaying: true)
        let externalPause = snapshot(isPlaying: false)
        let session = OrderingSpotifySession(playback: [initial])
        let adapter = makeAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        adapter.send(.togglePlayback)
        await session.waitForCommandCount(1)
        await Task.yield()

        await session.enqueuePlayback(confirmed)
        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.isPlaying, true)

        await session.enqueuePlayback(externalPause)
        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.isPlaying, false)
    }

    func testRapidRepeatCommandsKeepNewestGenerationWhenOlderPollCompletes() async {
        let initial = snapshot(repeatMode: .off)
        let session = OrderingSpotifySession(playback: [initial])
        let adapter = makeAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        await session.suspendNextPlaybackRead()
        let delayedPoll = Task { await adapter.refreshPlayback() }
        await session.waitUntilPlaybackReadIsSuspended()

        adapter.send(.cycleRepeat)
        adapter.send(.cycleRepeat)
        XCTAssertEqual(received.last?.repeatMode, .one)

        await session.resumeSuspendedPlayback(with: initial)
        await delayedPoll.value
        XCTAssertEqual(received.last?.repeatMode, .one)
    }

    func testExplicitAccountRefreshBypassesLikedSongsTTL() async {
        let initial = snapshot()
        let session = OrderingSpotifySession(
            playback: [initial],
            likedValues: [false, true]
        )
        let adapter = makeAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        XCTAssertEqual(received.last?.likedState, .value(false))

        await adapter.refreshAccountState()
        XCTAssertEqual(received.last?.likedState, .value(true))
        let queryCount = await session.likedQueryCount()
        XCTAssertEqual(queryCount, 2)
    }

    func testLikedMutationFailureRollsBackWithExplicitFailureState() async {
        let initial = snapshot()
        let session = OrderingSpotifySession(
            playback: [initial],
            likedValues: [true],
            failLikedMutation: true
        )
        let adapter = makeAdapter(session: session)
        var received: [PlaybackSnapshot] = []
        adapter.onSnapshot = { received.append($0) }

        await adapter.refreshPlayback()
        adapter.send(.toggleLiked)
        XCTAssertEqual(received.last?.likedState, .updating(desired: false, previous: true))

        await session.waitForLikedMutationCount(1)
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(received.last?.likedState, .failed(lastKnown: true))
    }

    private func makeAdapter(session: OrderingSpotifySession) -> SpotifyPlaybackAdapter {
        return SpotifyPlaybackAdapter(
            sessionBroker: session,
            accountProvider: OrderingAccountProvider(),
            monotonicNow: { 100 }
        )
    }
}

private actor OrderingSpotifySession: SpotifyPlaybackSessionServing {
    private var playback: [PlaybackSnapshot?]
    private var fallbackPlayback: PlaybackSnapshot?
    private var shouldSuspendNextPlayback = false
    private var suspendedPlayback: CheckedContinuation<PlaybackSnapshot?, Never>?
    private var playbackSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var commandCount = 0
    private var commandCountWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var likedValues: [Bool]
    private var fallbackLikedValue: Bool
    private var likedQueryCounter = 0
    private var likedMutationCounter = 0
    private var likedMutationWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private let failLikedMutation: Bool

    init(
        playback: [PlaybackSnapshot?],
        likedValues: [Bool] = [false],
        failLikedMutation: Bool = false
    ) {
        self.playback = playback
        fallbackPlayback = playback.compactMap { $0 }.last
        self.likedValues = likedValues
        fallbackLikedValue = likedValues.last ?? false
        self.failLikedMutation = failLikedMutation
    }

    func currentPlayback(account: SpotifyPlaybackAccount) async throws -> PlaybackSnapshot? {
        if shouldSuspendNextPlayback {
            shouldSuspendNextPlayback = false
            return await withCheckedContinuation { continuation in
                suspendedPlayback = continuation
                let waiters = playbackSuspensionWaiters
                playbackSuspensionWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        guard !playback.isEmpty else { return fallbackPlayback }
        let next = playback.removeFirst()
        if let next { fallbackPlayback = next }
        return next
    }

    func isTrackSaved(_ trackID: String, account: SpotifyPlaybackAccount) async throws -> Bool {
        likedQueryCounter += 1
        guard !likedValues.isEmpty else { return fallbackLikedValue }
        let value = likedValues.removeFirst()
        fallbackLikedValue = value
        return value
    }

    func setTrackSaved(_ saved: Bool, trackID: String, account: SpotifyPlaybackAccount) async throws {
        likedMutationCounter += 1
        let ready = likedMutationWaiters.filter { likedMutationCounter >= $0.target }
        likedMutationWaiters.removeAll { likedMutationCounter >= $0.target }
        ready.forEach { $0.continuation.resume() }
        if failLikedMutation { throw OrderingSpotifyFailure.likedMutationRejected }
    }

    func send(_ command: PlaybackCommand, snapshot: PlaybackSnapshot, account: SpotifyPlaybackAccount) async throws {
        commandCount += 1
        let ready = commandCountWaiters.filter { commandCount >= $0.target }
        commandCountWaiters.removeAll { commandCount >= $0.target }
        ready.forEach { $0.continuation.resume() }
    }

    func enqueuePlayback(_ snapshot: PlaybackSnapshot?) {
        playback.append(snapshot)
    }

    func suspendNextPlaybackRead() {
        shouldSuspendNextPlayback = true
    }

    func waitUntilPlaybackReadIsSuspended() async {
        if suspendedPlayback != nil { return }
        await withCheckedContinuation { continuation in
            playbackSuspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedPlayback(with snapshot: PlaybackSnapshot?) {
        precondition(suspendedPlayback != nil, "No suspended playback read")
        let continuation = suspendedPlayback
        suspendedPlayback = nil
        if let snapshot { fallbackPlayback = snapshot }
        continuation?.resume(returning: snapshot)
    }

    func waitForCommandCount(_ target: Int) async {
        if commandCount >= target { return }
        await withCheckedContinuation { continuation in
            commandCountWaiters.append((target, continuation))
        }
    }

    func likedQueryCount() -> Int { likedQueryCounter }

    func waitForLikedMutationCount(_ target: Int) async {
        if likedMutationCounter >= target { return }
        await withCheckedContinuation { continuation in
            likedMutationWaiters.append((target, continuation))
        }
    }
}

private enum OrderingSpotifyFailure: Error {
    case likedMutationRejected
}

@MainActor
private final class OrderingAccountProvider: SpotifyPlaybackAccountProviding {
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

private func snapshot(
    id: String = "spotify:track:fixture",
    kind: PlaybackItemKind = .track,
    isPlaying: Bool = true,
    isShuffled: Bool = false,
    repeatMode: RepeatMode = .off,
    capabilities: PlaybackCapabilities = .accountPlayback
) -> PlaybackSnapshot {
    PlaybackSnapshot(
        track: Track(
            id: id,
            title: "Fixture Track",
            artist: "Fixture Artist",
            album: "Fixture Album",
            duration: 180,
            kind: kind
        ),
        position: 30,
        isPlaying: isPlaying,
        likedState: .unknown,
        isShuffled: isShuffled,
        repeatMode: repeatMode,
        capabilities: capabilities
    )
}
