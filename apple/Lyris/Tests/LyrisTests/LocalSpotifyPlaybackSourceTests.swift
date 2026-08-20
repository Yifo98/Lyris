import XCTest
@testable import Lyris

@MainActor
final class LocalSpotifyPlaybackSourceTests: XCTestCase {
    func testLocalCompanionPublishesMetadataWithoutAccountCredentials() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [.success(sample(duration: 203_000, position: 12.5))]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let clock = LocalSpotifyMonotonicClockFake(100)
        let source = LocalSpotifyPlaybackSource(
            scripting: scripting,
            scheduler: scheduler,
            monotonicNow: { clock.value }
        )
        var snapshots: [PlaybackSnapshot] = []
        source.onSnapshot = { snapshots.append($0) }

        source.start()
        XCTAssertEqual(scheduler.intervals.count, 2)
        XCTAssertEqual(scheduler.intervals[0], 0.75, accuracy: 0.000_1)
        XCTAssertEqual(scheduler.intervals[1], 1.0 / 12.0, accuracy: 0.000_1)
        await scheduler.fire(index: 0)

        let snapshot = try! XCTUnwrap(snapshots.last)
        XCTAssertEqual(snapshot.track.id, "spotify:track:local-test")
        XCTAssertEqual(snapshot.track.title, "Local Song")
        XCTAssertEqual(snapshot.track.artist, "Local Artist")
        XCTAssertEqual(snapshot.track.album, "Local Album")
        XCTAssertEqual(snapshot.track.duration, 203, accuracy: 0.000_1)
        XCTAssertEqual(snapshot.track.artworkURL?.absoluteString, "https://images.example/cover.jpg")
        XCTAssertEqual(snapshot.position, 12.5, accuracy: 0.000_1)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertTrue(snapshot.isShuffled)
        XCTAssertEqual(snapshot.repeatMode, .all)
        XCTAssertEqual(snapshot.likedState, .unavailable)
        XCTAssertEqual(snapshot.capabilities, .localCompanion)
    }

    func testDurationNormalizerAcceptsSecondsAndMilliseconds() {
        XCTAssertEqual(LocalSpotifyDurationNormalizer.seconds(from: 203), 203)
        XCTAssertEqual(LocalSpotifyDurationNormalizer.seconds(from: 203_000), 203)
        XCTAssertEqual(
            LocalSpotifyDurationNormalizer.seconds(
                from: 14_400,
                position: 30,
                itemKind: .episode
            ),
            14_400
        )
        XCTAssertEqual(LocalSpotifyDurationNormalizer.seconds(from: -20), 0)
        XCTAssertEqual(LocalSpotifyDurationNormalizer.seconds(from: .infinity), 0)
    }

    func testSpotifyURIClassifiesTracksEpisodesAdvertisementsAndUnknownItems() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [
                .success(sample(duration: 203, position: 1, spotifyURI: "spotify:track:t")),
                .success(sample(duration: 14_400, position: 30, spotifyURI: "spotify:episode:e")),
                .success(sample(duration: 30, position: 2, spotifyURI: "spotify:ad:a")),
                .success(sample(duration: 60, position: 3, spotifyURI: "local:item")),
            ]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let source = LocalSpotifyPlaybackSource(scripting: scripting, scheduler: scheduler)
        var kinds: [PlaybackItemKind] = []
        var durations: [TimeInterval] = []
        source.onSnapshot = {
            kinds.append($0.track.kind)
            durations.append($0.track.duration)
        }
        source.start()

        for _ in 0..<4 { await scheduler.fire(index: 0) }

        XCTAssertEqual(kinds, [.track, .episode, .advertisement, .unknown])
        XCTAssertEqual(durations[1], 14_400)
    }

    func testProjectionAdvancesAtHighFrequencyWithoutAnotherSpotifyRead() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [.success(sample(duration: 203, position: 20))]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let clock = LocalSpotifyMonotonicClockFake(10)
        let source = LocalSpotifyPlaybackSource(
            scripting: scripting,
            scheduler: scheduler,
            monotonicNow: { clock.value }
        )
        var snapshots: [PlaybackSnapshot] = []
        source.onSnapshot = { snapshots.append($0) }
        source.start()

        await scheduler.fire(index: 0)
        clock.value = 10.5
        await scheduler.fire(index: 1)

        XCTAssertEqual(snapshots.last?.position ?? -1, 20.5, accuracy: 0.000_1)
        let readCount = await scripting.currentReadCount()
        XCTAssertEqual(readCount, 1)
    }

    func testSeekOptimismCannotBeOverwrittenByPollStartedBeforeCommand() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [.success(sample(duration: 203, position: 20))]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let clock = LocalSpotifyMonotonicClockFake(100)
        let source = LocalSpotifyPlaybackSource(
            scripting: scripting,
            scheduler: scheduler,
            monotonicNow: { clock.value }
        )
        var snapshots: [PlaybackSnapshot] = []
        source.onSnapshot = { snapshots.append($0) }
        source.start()
        await scheduler.fire(index: 0)

        await scripting.deferNextRead()
        let stalePoll = Task { await scheduler.fire(index: 0) }
        await scripting.waitForReadCount(2)

        clock.value = 101
        source.send(.seek(80))
        await scripting.waitForCommandCount(1)
        await scripting.resumeDeferredRead(with: sample(duration: 203, position: 21))
        await stalePoll.value

        clock.value = 101.2
        await scheduler.fire(index: 1)
        XCTAssertEqual(snapshots.last?.position ?? -1, 80.2, accuracy: 0.000_1)
        let commands = await scripting.currentCommands()
        XCTAssertEqual(commands, [.seek(80)])
    }

    func testLocalTransportShuffleAndRepeatResolveToAbsoluteScriptCommands() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [.success(sample(duration: 203, position: 20))]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let source = LocalSpotifyPlaybackSource(scripting: scripting, scheduler: scheduler)
        source.start()
        await scheduler.fire(index: 0)

        source.send(.togglePlayback)
        await scripting.waitForCommandCount(1)
        source.send(.previous)
        await scripting.waitForCommandCount(2)
        source.send(.next)
        await scripting.waitForCommandCount(3)
        source.send(.toggleShuffle)
        await scripting.waitForCommandCount(4)
        source.send(.cycleRepeat)
        await scripting.waitForCommandCount(5)

        let commands = await scripting.currentCommands()
        XCTAssertEqual(
            commands,
            [.setPlaying(false), .previous, .next, .setShuffle(false), .setRepeat(false)]
        )
    }

    func testLocalVolumeResolvesToAbsoluteScriptCommand() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [.success(sample(duration: 203, position: 20))]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let source = LocalSpotifyPlaybackSource(scripting: scripting, scheduler: scheduler)
        source.start()
        await scheduler.fire(index: 0)

        source.send(.setVolume(0.42))
        await scripting.waitForCommandCount(1)

        let commands = await scripting.currentCommands()
        XCTAssertEqual(commands, [.setVolume(0.42)])
    }

    func testLocalSourceReportsTypedPermissionError() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [.failure(LocalSpotifySourceError.automationDenied)]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let source = LocalSpotifyPlaybackSource(scripting: scripting, scheduler: scheduler)
        var issues: [LocalSpotifySourceError] = []
        var snapshots: [PlaybackSnapshot] = []
        source.onIssue = { issues.append($0) }
        source.onSnapshot = { snapshots.append($0) }
        source.start()

        await scheduler.fire(index: 0)

        XCTAssertEqual(issues, [.automationDenied])
        XCTAssertEqual(snapshots.last?.track.id, "spotify:idle")
    }

    func testUnavailableLocalPlaybackPublishesIdleSoHybridCanFallBack() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [
                .success(sample(duration: 203, position: 20)),
                .failure(LocalSpotifySourceError.notRunning),
            ]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let source = LocalSpotifyPlaybackSource(scripting: scripting, scheduler: scheduler)
        var snapshots: [PlaybackSnapshot] = []
        source.onSnapshot = { snapshots.append($0) }
        source.start()

        await scheduler.fire(index: 0)
        await scheduler.fire(index: 0)

        XCTAssertEqual(snapshots.map(\.track.id), ["spotify:track:local-test", "spotify:idle"])
        XCTAssertEqual(snapshots.last?.capabilities, [])
        XCTAssertEqual(snapshots.last?.track.kind, .unknown)
    }

    func testStoppingSourceInvalidatesAnInFlightPoll() async {
        let scripting = LocalSpotifyScriptingFake(
            reads: [.success(sample(duration: 203, position: 20))]
        )
        let scheduler = LocalSpotifySchedulerFake()
        let source = LocalSpotifyPlaybackSource(scripting: scripting, scheduler: scheduler)
        var snapshots: [PlaybackSnapshot] = []
        source.onSnapshot = { snapshots.append($0) }
        source.start()
        await scheduler.fire(index: 0)

        await scripting.deferNextRead()
        let inFlightPoll = Task { await scheduler.fire(index: 0) }
        await scripting.waitForReadCount(2)
        source.stop()
        await scripting.resumeDeferredRead(
            with: sample(duration: 203, position: 99, spotifyURI: "spotify:track:stale")
        )
        await inFlightPoll.value

        XCTAssertEqual(snapshots.map(\.track.id), ["spotify:track:local-test"])
    }

    func testAppleScriptAdapterChecksInstallationAndRunningStateBeforeExecution() async {
        let executor = LocalSpotifyExecutorFake(result: .success(""))

        let missing = LocalSpotifyAppleScriptAdapter(
            executor: executor,
            applicationInspector: LocalSpotifyApplicationInspectorFake(installed: false, running: false)
        )
        await assertLocalError(.notInstalled) { try await missing.readPlayback() }

        let stopped = LocalSpotifyAppleScriptAdapter(
            executor: executor,
            applicationInspector: LocalSpotifyApplicationInspectorFake(installed: true, running: false)
        )
        await assertLocalError(.notRunning) { try await stopped.readPlayback() }

        let invocationCount = await executor.invocationCount()
        XCTAssertEqual(invocationCount, 0)
    }

    func testAppleScriptAdapterMapsAutomationDeniedAndNotPlaying() async {
        let deniedExecutor = LocalSpotifyExecutorFake(
            result: .failure(
                LocalSpotifyAppleScriptExecutionFailure(
                    exitStatus: 1,
                    standardError: "execution error: Not authorized to send Apple events. (-1743)"
                )
            )
        )
        let denied = LocalSpotifyAppleScriptAdapter(
            executor: deniedExecutor,
            applicationInspector: LocalSpotifyApplicationInspectorFake(installed: true, running: true)
        )
        await assertLocalError(.automationDenied) { try await denied.readPlayback() }

        let stoppedOutput = ["stopped"].joined(separator: LocalSpotifyAppleScriptAdapter.fieldSeparator)
        let stopped = LocalSpotifyAppleScriptAdapter(
            executor: LocalSpotifyExecutorFake(result: .success(stoppedOutput)),
            applicationInspector: LocalSpotifyApplicationInspectorFake(installed: true, running: true)
        )
        await assertLocalError(.notPlaying) { try await stopped.readPlayback() }
    }

    func testSeekValueIsPassedAsArgumentAndNeverInterpolatedIntoScriptSource() async throws {
        let executor = LocalSpotifyExecutorFake(result: .success(""))
        let adapter = LocalSpotifyAppleScriptAdapter(
            executor: executor,
            applicationInspector: LocalSpotifyApplicationInspectorFake(installed: true, running: true)
        )

        try await adapter.perform(.seek(42.5))

        let lastInvocation = await executor.lastInvocation()
        let invocation = try XCTUnwrap(lastInvocation)
        XCTAssertEqual(invocation.arguments, ["42.5"])
        XCTAssertFalse(invocation.source.contains("42.5"))
        XCTAssertTrue(invocation.source.contains("on run argv"))
    }

    private func sample(
        duration: TimeInterval,
        position: TimeInterval,
        state: LocalSpotifyPlayerState = .playing,
        spotifyURI: String = "spotify:track:local-test"
    ) -> LocalSpotifyScriptSnapshot {
        LocalSpotifyScriptSnapshot(
            state: state,
            position: position,
            title: "Local Song",
            artist: "Local Artist",
            album: "Local Album",
            duration: duration,
            spotifyURI: spotifyURI,
            artworkURL: "https://images.example/cover.jpg",
            isShuffled: true,
            isRepeating: true
        )
    }

    private func assertLocalError<T>(
        _ expected: LocalSpotifySourceError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as LocalSpotifySourceError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
private final class LocalSpotifyMonotonicClockFake {
    var value: TimeInterval

    init(_ value: TimeInterval) {
        self.value = value
    }
}

private actor LocalSpotifyScriptingFake: LocalSpotifyScripting {
    private var readResults: [Result<LocalSpotifyScriptSnapshot, Error>]
    private var shouldDeferNextRead = false
    private var deferredContinuation: CheckedContinuation<LocalSpotifyScriptSnapshot, Error>?
    private var readWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var commandWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var readCount = 0
    private(set) var commands: [LocalSpotifyScriptCommand] = []

    init(reads: [Result<LocalSpotifyScriptSnapshot, Error>]) {
        readResults = reads
    }

    func readPlayback() async throws -> LocalSpotifyScriptSnapshot {
        readCount += 1
        resumeReadWaiters()
        if shouldDeferNextRead {
            shouldDeferNextRead = false
            return try await withCheckedThrowingContinuation { deferredContinuation = $0 }
        }
        guard !readResults.isEmpty else { throw LocalSpotifySourceError.notPlaying }
        return try readResults.removeFirst().get()
    }

    func perform(_ command: LocalSpotifyScriptCommand) async throws {
        commands.append(command)
        resumeCommandWaiters()
    }

    func deferNextRead() {
        shouldDeferNextRead = true
    }

    func resumeDeferredRead(with snapshot: LocalSpotifyScriptSnapshot) {
        deferredContinuation?.resume(returning: snapshot)
        deferredContinuation = nil
    }

    func waitForReadCount(_ count: Int) async {
        guard readCount < count else { return }
        await withCheckedContinuation { readWaiters.append((count, $0)) }
    }

    func waitForCommandCount(_ count: Int) async {
        guard commands.count < count else { return }
        await withCheckedContinuation { commandWaiters.append((count, $0)) }
    }

    func currentReadCount() -> Int { readCount }

    func currentCommands() -> [LocalSpotifyScriptCommand] { commands }

    private func resumeReadWaiters() {
        let ready = readWaiters.filter { readCount >= $0.0 }
        readWaiters.removeAll { readCount >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    private func resumeCommandWaiters() {
        let ready = commandWaiters.filter { commands.count >= $0.0 }
        commandWaiters.removeAll { commands.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

@MainActor
private final class LocalSpotifySchedulerFake: LocalSpotifySourceScheduling {
    private final class Token: LocalSpotifyScheduledTask {
        func cancel() {}
    }

    private(set) var intervals: [TimeInterval] = []
    private var operations: [() async -> Void] = []

    func schedule(
        every interval: TimeInterval,
        operation: @escaping () async -> Void
    ) -> any LocalSpotifyScheduledTask {
        intervals.append(interval)
        operations.append(operation)
        return Token()
    }

    func fire(index: Int) async {
        await operations[index]()
    }
}

private actor LocalSpotifyExecutorFake: LocalSpotifyAppleScriptExecuting {
    struct Invocation: Equatable {
        let source: String
        let arguments: [String]
    }

    private let result: Result<String, Error>
    private var invocations: [Invocation] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func execute(source: String, arguments: [String]) async throws -> String {
        invocations.append(Invocation(source: source, arguments: arguments))
        return try result.get()
    }

    func invocationCount() -> Int { invocations.count }

    func lastInvocation() -> Invocation? { invocations.last }
}

private struct LocalSpotifyApplicationInspectorFake: LocalSpotifyApplicationInspecting {
    let installed: Bool
    let running: Bool

    func isSpotifyInstalled() -> Bool { installed }
    func isSpotifyRunning() -> Bool { running }
}
