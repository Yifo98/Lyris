import XCTest
@testable import Lyris

final class SpotifyLikedSyncTests: XCTestCase {
    func testLocalModeIsUnavailableInsteadOfFalse() {
        var coordinator = LikedSongsCoordinator()

        XCTAssertNil(coordinator.selectTrack("spotify:track:A", accountCapability: false))
        XCTAssertEqual(coordinator.state, .unavailable)
    }

    func testOldTrackQueryCannotOverwriteNewTrack() throws {
        var coordinator = LikedSongsCoordinator()
        let old = try XCTUnwrap(coordinator.selectTrack("spotify:track:A", accountCapability: true))
        let current = try XCTUnwrap(coordinator.selectTrack("spotify:track:B", accountCapability: true))

        XCTAssertFalse(coordinator.completeQuery(true, permit: old, at: 1))
        XCTAssertTrue(coordinator.completeQuery(false, permit: current, at: 1))
        XCTAssertEqual(coordinator.state, .value(false))
    }

    func testSameTrackExternalChangeIsRefreshedAfterInterval() throws {
        var coordinator = LikedSongsCoordinator()
        let initial = try XCTUnwrap(coordinator.selectTrack("spotify:track:A", accountCapability: true))
        XCTAssertTrue(coordinator.completeQuery(false, permit: initial, at: 0))
        XCTAssertFalse(coordinator.shouldRefresh(at: 9.9))
        XCTAssertTrue(coordinator.shouldRefresh(at: 10))

        let refresh = try XCTUnwrap(coordinator.beginRefresh())
        XCTAssertTrue(coordinator.completeQuery(true, permit: refresh, at: 10))
        XCTAssertEqual(coordinator.state, .value(true))
    }

    func testRefreshRequestsAreDeduplicatedWhileServerTruthIsInFlight() throws {
        var coordinator = LikedSongsCoordinator()
        let inFlight = try XCTUnwrap(
            coordinator.selectTrack("spotify:track:A", accountCapability: true)
        )

        XCTAssertNil(coordinator.beginRefresh())
        XCTAssertTrue(coordinator.completeQuery(true, permit: inFlight, at: 1))

        let forcedRefresh = try XCTUnwrap(coordinator.beginRefresh())
        XCTAssertNil(coordinator.beginRefresh())
        XCTAssertTrue(coordinator.completeQuery(false, permit: forcedRefresh, at: 2))
        XCTAssertEqual(coordinator.state, .value(false))
    }

    func testMutationIsOptimisticThenServerConfirmed() throws {
        var coordinator = LikedSongsCoordinator()
        let initial = try XCTUnwrap(coordinator.selectTrack("spotify:track:A", accountCapability: true))
        XCTAssertTrue(coordinator.completeQuery(false, permit: initial, at: 0))

        let mutation = try XCTUnwrap(coordinator.beginMutation(desired: true))
        XCTAssertEqual(coordinator.state, .updating(desired: true, previous: false))
        let confirmation = try XCTUnwrap(coordinator.completeMutation(permit: mutation))
        XCTAssertEqual(coordinator.state, .checking(lastKnown: true))
        XCTAssertTrue(coordinator.completeQuery(true, permit: confirmation, at: 1))
        XCTAssertEqual(coordinator.state, .value(true))
    }

    func testMutationFailureRollsBackOnlyCurrentGeneration() throws {
        var coordinator = LikedSongsCoordinator()
        let initial = try XCTUnwrap(coordinator.selectTrack("spotify:track:A", accountCapability: true))
        XCTAssertTrue(coordinator.completeQuery(false, permit: initial, at: 0))
        let oldMutation = try XCTUnwrap(coordinator.beginMutation(desired: true))

        _ = coordinator.selectTrack("spotify:track:B", accountCapability: true)
        XCTAssertFalse(coordinator.failMutation(permit: oldMutation))
        XCTAssertEqual(coordinator.state, .checking(lastKnown: nil))
    }

    func testCurrentMutationFailureRollsBackAndKeepsExplicitFailureState() throws {
        var coordinator = LikedSongsCoordinator()
        let initial = try XCTUnwrap(coordinator.selectTrack("spotify:track:A", accountCapability: true))
        XCTAssertTrue(coordinator.completeQuery(true, permit: initial, at: 0))
        let mutation = try XCTUnwrap(coordinator.beginMutation(desired: false))

        XCTAssertTrue(coordinator.failMutation(permit: mutation))
        XCTAssertEqual(coordinator.state, .failed(lastKnown: true))
        XCTAssertEqual(coordinator.state.displayedValue, true)
    }
}
