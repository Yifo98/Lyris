import Foundation
import XCTest
@testable import Lyris

final class CredentialRedactionTests: XCTestCase {
    func testAdHocBuildNeverTouchesAnUnapprovedKeychainItemDuringSilentRestore() throws {
        let suiteName = "Lyris.CredentialAccessIdentityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let vault = KeychainCredentialVault(defaults: defaults)

        XCTAssertThrowsError(
            try vault.read(account: "fixture.account", interaction: .silent)
        ) { error in
            XCTAssertTrue((error as? KeychainError)?.requiresUserInteraction == true)
        }
    }

    func testRedactsSensitiveFieldsAcrossCommonLogFormats() {
        let log = #"client_secret=SECRET_FIXTURE access_token":"ACCESS_FIXTURE" refresh_token=REFRESH_FIXTURE code=AUTH_CODE_FIXTURE code_verifier=VERIFIER_FIXTURE api_key: API_FIXTURE"#

        let redacted = SpotifyCredentialRedactor.redact(log)

        for sensitiveFixture in [
            "SECRET_FIXTURE",
            "ACCESS_FIXTURE",
            "REFRESH_FIXTURE",
            "AUTH_CODE_FIXTURE",
            "VERIFIER_FIXTURE",
            "API_FIXTURE",
        ] {
            XCTAssertFalse(redacted.contains(sensitiveFixture))
        }
        XCTAssertTrue(redacted.contains(SpotifyCredentialRedactor.placeholder))
    }

    func testRedactsAuthorizationHeaderWithoutDestroyingSafeHeaders() {
        let headers = [
            "Authorization": "Bearer ACCESS_FIXTURE",
            "Content-Type": "application/json",
            "X-Request-ID": "safe-request-id",
        ]

        let redacted = SpotifyCredentialRedactor.redact(headers: headers)

        XCTAssertEqual(redacted["Authorization"], SpotifyCredentialRedactor.placeholder)
        XCTAssertEqual(redacted["Content-Type"], "application/json")
        XCTAssertEqual(redacted["X-Request-ID"], "safe-request-id")
    }

    func testRedactionIsCaseInsensitiveAndPreservesFieldNamesForDiagnosis() {
        let redacted = SpotifyCredentialRedactor.redact(
            "CLIENT_SECRET=SECRET_FIXTURE&API-KEY=API_FIXTURE&Authorization: Basic BASIC_FIXTURE"
        )

        XCTAssertTrue(redacted.localizedCaseInsensitiveContains("client_secret="))
        XCTAssertTrue(redacted.localizedCaseInsensitiveContains("api-key="))
        XCTAssertTrue(redacted.localizedCaseInsensitiveContains("authorization:"))
        XCTAssertFalse(redacted.contains("SECRET_FIXTURE"))
        XCTAssertFalse(redacted.contains("API_FIXTURE"))
        XCTAssertFalse(redacted.contains("BASIC_FIXTURE"))
    }

    func testRedactsAuthorizationFromJSONLogs() {
        let redacted = SpotifyCredentialRedactor.redact(
            #"{"Authorization":"Bearer JSON_BEARER_FIXTURE"}"#
        )

        XCTAssertTrue(redacted.contains(#""Authorization""#))
        XCTAssertFalse(redacted.contains("JSON_BEARER_FIXTURE"))
    }

    func testRedactsVendorHeadersAndSeparatorVariants() {
        let headers = [
            "X-API-Key": "HEADER_API_FIXTURE",
            "x_client_secret": "HEADER_SECRET_FIXTURE",
            "X.Access.Token": "HEADER_ACCESS_FIXTURE",
            "X-Auth-Token": "HEADER_AUTH_TOKEN_FIXTURE",
            "Refresh-Token": "HEADER_REFRESH_FIXTURE",
            "Token": "HEADER_TOKEN_FIXTURE",
            "X-Request-ID": "safe-request-id",
        ]

        let redacted = SpotifyCredentialRedactor.redact(headers: headers)

        for key in ["X-API-Key", "x_client_secret", "X.Access.Token", "X-Auth-Token", "Refresh-Token", "Token"] {
            XCTAssertEqual(redacted[key], SpotifyCredentialRedactor.placeholder)
        }
        XCTAssertEqual(redacted["X-Request-ID"], "safe-request-id")
    }

    func testRedactsCredentialKeysWithSpacesDotsDashesAndUnderscores() {
        let log = #"code verifier=SPACE_VERIFIER access.token=DOT_ACCESS refresh-token=DASH_REFRESH authorization.token=AUTH_TOKEN session_token=SESSION_TOKEN access=BARE_ACCESS refresh=BARE_REFRESH token=PLAIN_TOKEN X_API_KEY=VENDOR_API x-client-secret=VENDOR_SECRET AUTHORIZATION_CODE=AUTH_CODE"#

        let redacted = SpotifyCredentialRedactor.redact(log)

        for fixture in [
            "SPACE_VERIFIER",
            "DOT_ACCESS",
            "DASH_REFRESH",
            "AUTH_TOKEN",
            "SESSION_TOKEN",
            "BARE_ACCESS",
            "BARE_REFRESH",
            "PLAIN_TOKEN",
            "VENDOR_API",
            "VENDOR_SECRET",
            "AUTH_CODE",
        ] {
            XCTAssertFalse(redacted.contains(fixture))
        }
    }

    func testCredentialComponentKeysAreCaseAndSeparatorInsensitive() {
        let componentKeys = [
            ["client", "secret"],
            ["x", "client", "secret"],
            ["access", "token"],
            ["refresh", "token"],
            ["authorization", "code"],
            ["code", "verifier"],
            ["api", "key"],
            ["x", "api", "key"],
        ]

        for separator in ["", "_", "-", ".", " "] {
            for components in componentKeys {
                for key in [
                    components.joined(separator: separator),
                    components.map { $0.uppercased() }.joined(separator: separator),
                ] {
                    let fixture = "SENSITIVE_\(UUID().uuidString)"
                    let redacted = SpotifyCredentialRedactor.redact("\(key)=\(fixture)")
                    XCTAssertFalse(redacted.contains(fixture), "Failed to redact key: \(key)")
                }
            }
        }
    }
}
