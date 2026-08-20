import Foundation
import XCTest
@testable import Lyris

final class SpotifyPKCEAuthorizationTests: XCTestCase {
    func testProfileDefaultsToPKCEAndHasNoCredentialField() throws {
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            displayName: "Personal Spotify",
            clientID: "fixture-client-id",
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )

        XCTAssertEqual(profile.authorizationMode, .pkce)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            ["id", "displayName", "clientID", "authorizationMode", "redirectURI", "grantedScopes"]
        )
    }

    func testPKCEAuthorizationRequestContainsChallengeAndNoClientSecret() throws {
        let profile = makePKCEProfile()
        let flow = SpotifyPKCEAuthorizationFlow(
            exchanger: AuthorizationFakeTokenExchanger(),
            proofGenerator: {
                SpotifyPKCEProof(
                    verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                    challenge: "synthetic-challenge"
                )
            },
            stateGenerator: { "synthetic-state" }
        )

        let attempt = try flow.makeAttempt(
            for: profile,
            scopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let values = try queryValues(attempt.authorizationURL)

        XCTAssertEqual(attempt.mode, .pkce)
        XCTAssertEqual(attempt.profileID, profile.id)
        XCTAssertEqual(values["client_id"], profile.clientID)
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["redirect_uri"], profile.redirectURI)
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["code_challenge"], "synthetic-challenge")
        XCTAssertEqual(values["state"], "synthetic-state")
        XCTAssertNil(values["client_secret"])
    }

    func testPKCECallbackExchangesCodeWithTheEphemeralVerifier() async throws {
        let profile = makePKCEProfile()
        let exchanger = AuthorizationFakeTokenExchanger()
        let flow = SpotifyPKCEAuthorizationFlow(
            exchanger: exchanger,
            proofGenerator: {
                SpotifyPKCEProof(
                    verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                    challenge: "synthetic-challenge"
                )
            },
            stateGenerator: { "synthetic-state" }
        )
        let attempt = try flow.makeAttempt(for: profile, scopes: profile.authorizationMode.supportedScopes)
        let callback = try XCTUnwrap(URL(
            string: "http://127.0.0.1:43821/oauth/callback?code=synthetic-code&state=synthetic-state"
        ))

        _ = try await flow.exchange(callbackURL: callback, attempt: attempt)

        let request = try XCTUnwrap(exchanger.requests.last)
        XCTAssertEqual(request.profileID, profile.id)
        XCTAssertEqual(request.clientID, profile.clientID)
        XCTAssertEqual(request.authorizationCode, "synthetic-code")
        guard case .pkce(let verifier) = request.authentication else {
            return XCTFail("Expected a PKCE token request")
        }
        XCTAssertEqual(verifier, "synthetic-verifier-value-with-at-least-forty-three-characters")
    }

    func testPKCERejectsCallbackStateMismatchBeforeTokenExchange() async throws {
        let profile = makePKCEProfile()
        let exchanger = AuthorizationFakeTokenExchanger()
        let flow = SpotifyPKCEAuthorizationFlow(
            exchanger: exchanger,
            proofGenerator: {
                SpotifyPKCEProof(
                    verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                    challenge: "synthetic-challenge"
                )
            },
            stateGenerator: { "expected-state" }
        )
        let attempt = try flow.makeAttempt(for: profile, scopes: profile.authorizationMode.supportedScopes)
        let callback = try XCTUnwrap(URL(
            string: "http://127.0.0.1:43821/oauth/callback?code=synthetic-code&state=wrong-state"
        ))

        do {
            _ = try await flow.exchange(callbackURL: callback, attempt: attempt)
            XCTFail("Expected state validation to fail")
        } catch {
            XCTAssertEqual(error as? SpotifyAuthorizationCoreError, .stateMismatch)
        }
        XCTAssertTrue(exchanger.requests.isEmpty)
    }

    func testConcreteProfileStoreRoundTripsVersionedJSONWithoutCredentialFields() throws {
        let settings = AuthorizationFakeSettingsStore()
        let store = SpotifyAuthorizationProfileStore(settings: settings)
        let profile = makePKCEProfile()

        try store.save(profile)

        let restoredProfile = try store.profile(id: profile.id)
        XCTAssertEqual(restoredProfile, profile)
        let data = try XCTUnwrap(settings.dataValues[SpotifyAuthorizationProfileStore.defaultStorageKey])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("clientSecret"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("refreshToken"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("accessToken"))
    }

    func testLegacyClientIDMigratesOnceToDefaultPKCEProfileWithoutInventingAuthorizationDate() throws {
        let settings = AuthorizationFakeSettingsStore()
        settings.stringValues[SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey] = "  legacy-client-id  "
        let store = SpotifyAuthorizationProfileStore(settings: settings)
        let vault = AuthorizationFakeCredentialVault()
        vault.values[SpotifyCredentialAccount.legacyRefreshToken] = "legacy-refresh-value"
        let tokenStore = SpotifyTokenStore(vault: vault)
        let migratedID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let migrator = SpotifyLegacyClientIDProfileMigrator(
            settings: settings,
            profileStore: store,
            tokenStore: tokenStore,
            idGenerator: { migratedID }
        )

        let migrated = try XCTUnwrap(migrator.migrateIfNeeded())
        XCTAssertEqual(migrated.id, migratedID)
        XCTAssertEqual(migrated.clientID, "legacy-client-id")
        XCTAssertEqual(migrated.authorizationMode, .pkce)
        XCTAssertEqual(migrated.redirectURI, "http://127.0.0.1:43821/oauth/callback")
        XCTAssertNil(migrated.authorizedAt)
        XCTAssertEqual(migrated.grantedScopes, SpotifyAuthorizationScopes.accountEnhancement)
        let migratedRefreshToken = try tokenStore.refreshToken(for: migratedID)
        XCTAssertEqual(migratedRefreshToken, "legacy-refresh-value")
        XCTAssertNil(vault.values[SpotifyCredentialAccount.legacyRefreshToken])
        let repeatedMigration = try migrator.migrateIfNeeded()
        let profileCount = try store.allProfiles().count
        XCTAssertNil(repeatedMigration)
        XCTAssertEqual(profileCount, 1)
    }
}

final class AuthorizationFakeTokenExchanger: SpotifyAuthorizationTokenExchanging {
    private(set) var requests: [SpotifyAuthorizationTokenRequest] = []
    var result = SpotifyAuthorizationTokenGrant(
        accessToken: "synthetic-access-value",
        refreshToken: "synthetic-refresh-value",
        expiresIn: 3_600
    )

    func exchange(_ request: SpotifyAuthorizationTokenRequest) async throws -> SpotifyAuthorizationTokenGrant {
        requests.append(request)
        return result
    }
}

func makePKCEProfile() -> SpotifyAuthorizationProfile {
    SpotifyAuthorizationProfile(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        displayName: "Personal Spotify",
        clientID: "fixture-client-id",
        redirectURI: "http://127.0.0.1:43821/oauth/callback"
    )
}

func queryValues(_ url: URL) throws -> [String: String] {
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

final class AuthorizationFakeSettingsStore: SpotifyAuthorizationSettingsStoring {
    var dataValues: [String: Data] = [:]
    var stringValues: [String: String] = [:]
    var boolValues: [String: Bool] = [:]

    func data(forKey key: String) -> Data? { dataValues[key] }
    func string(forKey key: String) -> String? { stringValues[key] }
    func bool(forKey key: String) -> Bool { boolValues[key] ?? false }
    func write(data: Data?, forKey key: String) { dataValues[key] = data }
    func write(bool: Bool, forKey key: String) { boolValues[key] = bool }
}
