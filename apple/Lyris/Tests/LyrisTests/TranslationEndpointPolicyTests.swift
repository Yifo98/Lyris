import Foundation
import XCTest
@testable import Lyris

final class TranslationEndpointPolicyTests: XCTestCase {
    func testAllowsHTTPSAndLoopbackHTTP() throws {
        XCTAssertTrue(TranslationEndpointPolicy.allows(try components("https://api.example.com/v1")))
        XCTAssertTrue(TranslationEndpointPolicy.allows(try components("http://127.0.0.1:11434/v1")))
        XCTAssertTrue(TranslationEndpointPolicy.allows(try components("http://localhost:11434/v1")))
    }

    func testRejectsRemoteHTTPAndNonHTTPURLs() throws {
        XCTAssertFalse(TranslationEndpointPolicy.allows(try components("http://api.example.com/v1")))
        XCTAssertFalse(TranslationEndpointPolicy.allows(try components("file:///tmp/provider")))
    }

    func testCacheIdentityNormalizesEquivalentURLsWithoutStoringPrivateURLData() {
        let canonical = TranslationEndpointPolicy.cacheIdentity(for: "https://api.example.com/v1")
        XCTAssertEqual(canonical, TranslationEndpointPolicy.cacheIdentity(for: " HTTPS://API.EXAMPLE.COM:443/v1/ "))
        for other in ["https://other.example.com/v1", "https://api.example.com/v2", "https://api.example.com/v1?tenant=two"] {
            XCTAssertNotEqual(canonical, TranslationEndpointPolicy.cacheIdentity(for: other))
        }
        let privateEndpoint = TranslationEndpointPolicy.cacheIdentity(for: "https://api.example.com/v1?key=fixture-secret")
        XCTAssertEqual(privateEndpoint.count, 64)
        XCTAssertFalse(privateEndpoint.contains("fixture-secret"))
    }

    private func components(_ value: String) throws -> URLComponents {
        try XCTUnwrap(URLComponents(string: value))
    }
}
