import XCTest
@testable import Lyris

final class SpotifyPollingCadenceTests: XCTestCase {
    func testHealthyPlaybackKeepsFastCadenceAndResetsBackoff() {
        var cadence = SpotifyPollingCadence()

        XCTAssertEqual(cadence.nextDelay(after: .noAccount), 4)
        XCTAssertEqual(cadence.nextDelay(after: .noAccount), 8)
        XCTAssertEqual(cadence.nextDelay(after: .playbackAvailable), 1.5)
        XCTAssertEqual(cadence.nextDelay(after: .offline), 4)
    }

    func testUnavailableAndFailedPollingBacksOffWithAnUpperBound() {
        var cadence = SpotifyPollingCadence()

        let delays = (0..<8).map { _ in cadence.nextDelay(after: .failure) }

        XCTAssertEqual(delays, [4, 8, 16, 32, 60, 60, 60, 60])
    }

    func testIdleSpotifyUsesAQuietSuccessfulCadence() {
        var cadence = SpotifyPollingCadence()

        XCTAssertEqual(cadence.nextDelay(after: .idle), 3)
        XCTAssertEqual(cadence.nextDelay(after: .playbackAvailable), 1.5)
    }
}
