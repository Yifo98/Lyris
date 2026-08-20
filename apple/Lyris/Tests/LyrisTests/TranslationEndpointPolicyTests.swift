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

    private func components(_ value: String) throws -> URLComponents {
        try XCTUnwrap(URLComponents(string: value))
    }
}
