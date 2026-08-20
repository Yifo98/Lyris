import XCTest
@testable import Lyris

final class PlaybackClockTests: XCTestCase {
    func testPlayingPositionAdvancesWithoutAnotherSourceSnapshot() {
        var clock = PlaybackClock()
        clock.apply(.source(sample(position: 10, isPlaying: true)), at: 100)

        XCTAssertEqual(clock.position(at: 100.75), 10.75, accuracy: 0.000_1)
    }

    func testPauseFreezesAndResumeBuildsANewAnchor() {
        var clock = PlaybackClock()
        clock.apply(.source(sample(position: 10, isPlaying: true)), at: 100)
        clock.apply(.source(sample(position: 11, isPlaying: false)), at: 101)
        XCTAssertEqual(clock.position(at: 110), 11, accuracy: 0.000_1)

        clock.apply(.source(sample(position: 11, isPlaying: true)), at: 110)
        XCTAssertEqual(clock.position(at: 111.25), 12.25, accuracy: 0.000_1)
    }

    func testTrackChangeResetsPosition() {
        var clock = PlaybackClock()
        clock.apply(.source(sample(trackID: "A", position: 30, isPlaying: true)), at: 10)
        clock.apply(.source(sample(trackID: "B", position: 2, isPlaying: true)), at: 11)

        XCTAssertEqual(clock.position(at: 11), 2, accuracy: 0.000_1)
    }

    func testSeekUpdatesImmediatelyAndIgnoresTheOldPoll() {
        var clock = PlaybackClock()
        clock.apply(.source(sample(position: 20, isPlaying: true)), at: 100)
        clock.apply(.seek(to: 80), at: 101)

        XCTAssertEqual(clock.position(at: 101), 80, accuracy: 0.000_1)
        XCTAssertEqual(
            clock.apply(.source(sample(position: 21, isPlaying: true)), at: 101.2),
            .ignoredPendingSeek
        )
        XCTAssertEqual(clock.position(at: 101.2), 80.2, accuracy: 0.000_1)
    }

    func testSmallDriftIsSmoothedAndLargeDriftSnaps() {
        var clock = PlaybackClock(configuration: .init(smallDriftLimit: 0.8, smoothingFactor: 0.25))
        clock.apply(.source(sample(position: 10, isPlaying: true)), at: 0)

        XCTAssertEqual(clock.apply(.source(sample(position: 11.4, isPlaying: true)), at: 1), .smoothed)
        XCTAssertEqual(clock.position(at: 1), 11.1, accuracy: 0.000_1)
        XCTAssertEqual(clock.apply(.source(sample(position: 20, isPlaying: true)), at: 2), .snapped)
        XCTAssertEqual(clock.position(at: 2), 20, accuracy: 0.000_1)
    }

    private func sample(
        trackID: String = "A",
        position: TimeInterval,
        isPlaying: Bool,
        duration: TimeInterval = 180
    ) -> PlaybackClockSourceSample {
        PlaybackClockSourceSample(
            trackID: trackID,
            position: position,
            duration: duration,
            isPlaying: isPlaying
        )
    }
}
