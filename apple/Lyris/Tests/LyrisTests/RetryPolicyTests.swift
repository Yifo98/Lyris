import Foundation
import XCTest
@testable import Lyris

final class RetryPolicyTests: XCTestCase {
    func testClassifiesSpotifyHTTPAndTransportFailures() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-22T00:00:00Z"))

        XCTAssertEqual(
            SpotifyNetworkFailureClassifier.classify(statusCode: 401),
            .unauthorized
        )
        XCTAssertEqual(
            SpotifyNetworkFailureClassifier.classify(statusCode: 403),
            .forbidden
        )
        XCTAssertEqual(
            SpotifyNetworkFailureClassifier.classify(
                statusCode: 429,
                headers: ["Retry-After": "7"],
                now: now
            ),
            .rateLimited(retryAfter: 7)
        )
        XCTAssertEqual(
            SpotifyNetworkFailureClassifier.classify(statusCode: 503),
            .server(statusCode: 503)
        )
        XCTAssertEqual(
            SpotifyNetworkFailureClassifier.classify(
                underlyingError: URLError(.notConnectedToInternet)
            ),
            .offline
        )
        XCTAssertEqual(
            SpotifyNetworkFailureClassifier.classify(
                underlyingError: URLError(.cancelled)
            ),
            .cancelled
        )
    }

    func testClassifiesInvalidGrantBeforeGenericClientFailure() {
        let body = Data(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#.utf8)

        XCTAssertEqual(
            SpotifyNetworkFailureClassifier.classify(statusCode: 400, responseBody: body),
            .invalidGrant
        )
    }

    func testParsesRetryAfterDeltaSecondsAndHTTPDate() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-22T00:00:00Z"))

        XCTAssertEqual(SpotifyRetryAfter.parse("12", now: now), 12)
        XCTAssertEqual(
            SpotifyRetryAfter.parse("Wed, 22 Jul 2026 00:00:09 GMT", now: now),
            9
        )
        XCTAssertEqual(SpotifyRetryAfter.parse("-10", now: now), 0)
        XCTAssertNil(SpotifyRetryAfter.parse("inf", now: now))
        XCTAssertNil(SpotifyRetryAfter.parse("not-a-delay", now: now))
    }

    func testUsesBoundedExponentialBackoffWithDeterministicJitterSeam() {
        let policy = SpotifyRetryPolicy(
            configuration: .init(
                maximumRetryCount: 4,
                baseDelay: 2,
                maximumDelay: 10,
                jitterFraction: 0.25
            ),
            jitter: { _ in 0 }
        )

        XCTAssertEqual(policy.delay(for: .server(statusCode: 500), retryNumber: 1), 2)
        XCTAssertEqual(policy.delay(for: .server(statusCode: 500), retryNumber: 2), 4)
        XCTAssertEqual(policy.delay(for: .server(statusCode: 500), retryNumber: 3), 8)
        XCTAssertEqual(policy.delay(for: .server(statusCode: 500), retryNumber: 4), 10)
        XCTAssertNil(policy.delay(for: .server(statusCode: 500), retryNumber: 5))
    }

    func testRetryAfterIsHonoredWithoutShorteningServerMinimum() {
        let policy = SpotifyRetryPolicy(
            configuration: .init(maximumRetryCount: 2, baseDelay: 1, maximumDelay: 30),
            jitter: { _ in 0 }
        )

        XCTAssertEqual(policy.delay(for: .rateLimited(retryAfter: 9), retryNumber: 1), 9)
        XCTAssertEqual(policy.delay(for: .rateLimited(retryAfter: 300), retryNumber: 1), 300)
    }

    func testInvalidGrantClearsTokenRequestsReauthorizationAndNeverRetries() {
        let policy = SpotifyRetryPolicy(jitter: { _ in 0 })

        XCTAssertNil(policy.delay(for: .invalidGrant, retryNumber: 1))
        XCTAssertEqual(
            SpotifyNetworkRecovery.decision(for: .invalidGrant),
            .clearRefreshTokenAndReauthorize
        )
    }

    func testCancellationNeverRetries() {
        let policy = SpotifyRetryPolicy(jitter: { _ in 0 })

        XCTAssertNil(policy.delay(for: .cancelled, retryNumber: 1))
        XCTAssertEqual(SpotifyNetworkRecovery.decision(for: .cancelled), .doNotRetry)
    }
}
