import Foundation
import XCTest
@testable import Lyris

final class LyricsPipelineStateTests: XCTestCase {
    func testFailureClassifierKeepsRateLimitOfflineAndAuthorizationDistinct() {
        XCTAssertEqual(
            LyricsPipelineFailureClassifier.state(
                for: LRCLibError.rateLimited(retryAfter: 12),
                trackID: "spotify:track:fixture"
            ),
            .rateLimited(trackID: "spotify:track:fixture", retryAfter: 12)
        )
        XCTAssertEqual(
            LyricsPipelineFailureClassifier.state(
                for: URLError(.notConnectedToInternet),
                trackID: "spotify:track:fixture"
            ),
            .offline(trackID: "spotify:track:fixture")
        )
        XCTAssertEqual(
            LyricsPipelineFailureClassifier.state(
                for: LRCLibError.unauthorized(statusCode: 403),
                trackID: "spotify:track:fixture"
            ),
            .unauthorized(trackID: "spotify:track:fixture")
        )
    }

    func testRetryGateAllowsOnlyOnePlanUntilItIsConsumedOrCancelled() {
        var gate = LyricsRetryGate()
        let first = LyricsRetryKey(trackID: "spotify:track:a", generation: 1)
        let second = LyricsRetryKey(trackID: "spotify:track:a", generation: 2)

        XCTAssertTrue(gate.reserve(first))
        XCTAssertFalse(gate.reserve(first))
        XCTAssertFalse(gate.reserve(second))
        XCTAssertFalse(gate.consume(second))
        XCTAssertTrue(gate.consume(first))
        XCTAssertTrue(gate.reserve(second))
        gate.cancel()
        XCTAssertNil(gate.reservation)
    }

    func testRateLimitPresentationExplainsTheSingleBackoffPlan() throws {
        let presentation = try XCTUnwrap(
            LyricsPipelineState.rateLimited(
                trackID: "spotify:track:fixture",
                retryAfter: 9
            ).presentation(language: .simplifiedChinese)
        )

        XCTAssertEqual(presentation.title, "歌词服务限流")
        XCTAssertTrue(presentation.detail.contains("9 秒"))
        XCTAssertTrue(presentation.detail.contains("一个退避计划"))
        XCTAssertTrue(presentation.showsProgress)
        XCTAssertFalse(presentation.canRetry)
    }
}
