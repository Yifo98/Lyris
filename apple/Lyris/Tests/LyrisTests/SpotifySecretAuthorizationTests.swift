import Foundation
import XCTest
@testable import Lyris

final class SpotifySecretAuthorizationTests: XCTestCase {
    func testPerProfileCredentialAccountsNeverUseOrdinaryProfileFields() throws {
        let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let vault = AuthorizationFakeCredentialVault()
        let store = SpotifyTokenStore(vault: vault)

        try store.storeClientSecret("synthetic-private-value", for: profileID)
        try store.storeRefreshToken("synthetic-refresh-value", for: profileID)

        XCTAssertEqual(
            vault.values["spotify.clientSecret.\(profileID.uuidString)"],
            "synthetic-private-value"
        )
        XCTAssertEqual(
            vault.values["spotify.refreshToken.\(profileID.uuidString)"],
            "synthetic-refresh-value"
        )
    }

    func testDeletingProfileCredentialsAttemptsSecretAndRefreshTokenDeletion() throws {
        let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let vault = AuthorizationFakeCredentialVault()
        let store = SpotifyTokenStore(vault: vault)
        try store.storeClientSecret("synthetic-private-value", for: profileID)
        try store.storeRefreshToken("synthetic-refresh-value", for: profileID)

        try store.deleteProfileCredentials(for: profileID)

        let clientSecret = try store.clientSecret(for: profileID)
        let refreshToken = try store.refreshToken(for: profileID)
        XCTAssertNil(clientSecret)
        XCTAssertNil(refreshToken)
        XCTAssertEqual(
            Set(vault.deletedAccounts),
            [
                "spotify.clientSecret.\(profileID.uuidString)",
                "spotify.refreshToken.\(profileID.uuidString)",
            ]
        )
    }

    func testLegacyRefreshTokenMigrationCopiesThenDeletesTheGlobalAccount() throws {
        let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let vault = AuthorizationFakeCredentialVault()
        vault.values[SpotifyCredentialAccount.legacyRefreshToken] = "legacy-refresh-value"
        let store = SpotifyTokenStore(vault: vault)

        let migrated = try store.migrateLegacyRefreshToken(to: profileID)
        let migratedValue = try store.refreshToken(for: profileID)

        XCTAssertTrue(migrated)
        XCTAssertEqual(migratedValue, "legacy-refresh-value")
        XCTAssertNil(vault.values[SpotifyCredentialAccount.legacyRefreshToken])
        XCTAssertEqual(vault.deletedAccounts, [SpotifyCredentialAccount.legacyRefreshToken])
    }

    func testLegacyRefreshTokenMigrationKeepsGlobalAccountWhenProfileWriteFails() throws {
        let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let vault = AuthorizationFakeCredentialVault()
        vault.values[SpotifyCredentialAccount.legacyRefreshToken] = "legacy-refresh-value"
        vault.writeFailureAccount = SpotifyCredentialAccount.refreshToken(for: profileID)
        let store = SpotifyTokenStore(vault: vault)

        do {
            _ = try store.migrateLegacyRefreshToken(to: profileID)
            XCTFail("Expected the profile-scoped write to fail")
        } catch AuthorizationFakeCredentialVaultError.syntheticWriteFailure {
            // Expected: the legacy account must remain recoverable.
        }
        let destinationValue = try store.refreshToken(for: profileID)
        XCTAssertEqual(vault.values[SpotifyCredentialAccount.legacyRefreshToken], "legacy-refresh-value")
        XCTAssertNil(destinationValue)
        XCTAssertTrue(vault.deletedAccounts.isEmpty)
    }

    func testSecretFlowReadsCredentialOnlyWhenExchangingTheCode() async throws {
        let profile = makeSecretProfile()
        let vault = AuthorizationFakeCredentialVault()
        let tokenStore = SpotifyTokenStore(vault: vault)
        try tokenStore.storeClientSecret("synthetic-private-value", for: profile.id)
        vault.readAccounts.removeAll()
        let exchanger = AuthorizationFakeTokenExchanger()
        let flow = SpotifySecretAuthorizationFlow(
            exchanger: exchanger,
            tokenStore: tokenStore,
            stateGenerator: { "synthetic-state" }
        )

        let attempt = try flow.makeAttempt(for: profile, scopes: profile.authorizationMode.supportedScopes)
        let values = try queryValues(attempt.authorizationURL)
        XCTAssertTrue(vault.readAccounts.isEmpty)
        XCTAssertNil(values["code_challenge"])
        XCTAssertNil(values["code_challenge_method"])
        XCTAssertNil(values["client_secret"])

        let callback = try XCTUnwrap(URL(
            string: "http://127.0.0.1:43821/oauth/callback?code=synthetic-code&state=synthetic-state"
        ))
        _ = try await flow.exchange(callbackURL: callback, attempt: attempt)

        XCTAssertEqual(
            vault.readAccounts,
            ["spotify.clientSecret.\(profile.id.uuidString)"]
        )
        let request = try XCTUnwrap(exchanger.requests.last)
        guard case .clientSecret(let value) = request.authentication else {
            return XCTFail("Expected a client-secret token request")
        }
        XCTAssertEqual(value, "synthetic-private-value")
    }

    func testSecretFlowFailsBeforeExchangeWhenCredentialIsMissing() async throws {
        let profile = makeSecretProfile()
        let exchanger = AuthorizationFakeTokenExchanger()
        let flow = SpotifySecretAuthorizationFlow(
            exchanger: exchanger,
            tokenStore: SpotifyTokenStore(vault: AuthorizationFakeCredentialVault()),
            stateGenerator: { "synthetic-state" }
        )
        let attempt = try flow.makeAttempt(for: profile, scopes: profile.authorizationMode.supportedScopes)
        let callback = try XCTUnwrap(URL(
            string: "http://127.0.0.1:43821/oauth/callback?code=synthetic-code&state=synthetic-state"
        ))

        do {
            _ = try await flow.exchange(callbackURL: callback, attempt: attempt)
            XCTFail("Expected missing client credential to fail")
        } catch {
            XCTAssertEqual(error as? SpotifyAuthorizationCoreError, .missingClientSecret)
        }
        XCTAssertTrue(exchanger.requests.isEmpty)
    }

    func testExchangeModelsDoNotExposeCredentialValuesInDescriptions() throws {
        let profile = makePKCEProfile()
        let attempt = try SpotifyPKCEAuthorizationFlow(
            exchanger: AuthorizationFakeTokenExchanger(),
            proofGenerator: {
                SpotifyPKCEProof(
                    verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                    challenge: "synthetic-challenge"
                )
            },
            stateGenerator: { "synthetic-state-value" }
        ).makeAttempt(for: profile, scopes: profile.authorizationMode.supportedScopes)
        let request = SpotifyAuthorizationTokenRequest(
            profileID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            clientID: "fixture-client-id",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizationCode: "synthetic-code-value",
            authentication: .clientSecret("synthetic-private-value")
        )
        let grant = SpotifyAuthorizationTokenGrant(
            accessToken: "synthetic-access-value",
            refreshToken: "synthetic-refresh-value",
            expiresIn: 3_600
        )
        let completion = SpotifyAuthorizationCompletion(
            profile: profile,
            accessToken: "synthetic-access-value",
            expiresIn: 3_600
        )
        let descriptions = [
            String(reflecting: attempt),
            String(describing: request),
            String(reflecting: request),
            String(describing: grant),
            String(reflecting: grant),
            String(reflecting: completion),
        ]

        for description in descriptions {
            XCTAssertFalse(description.contains("synthetic-verifier-value"))
            XCTAssertFalse(description.contains("synthetic-state-value"))
            XCTAssertFalse(description.contains("synthetic-code-value"))
            XCTAssertFalse(description.contains("synthetic-private-value"))
            XCTAssertFalse(description.contains("synthetic-access-value"))
            XCTAssertFalse(description.contains("synthetic-refresh-value"))
        }
    }
}

final class AuthorizationFakeCredentialVault: CredentialVault {
    var values: [String: String] = [:]
    var readAccounts: [String] = []
    private(set) var deletedAccounts: [String] = []
    var writeFailureAccount: String?

    func read(account: String) throws -> String? {
        readAccounts.append(account)
        return values[account]
    }

    func write(_ secret: String, account: String) throws {
        if account == writeFailureAccount {
            throw AuthorizationFakeCredentialVaultError.syntheticWriteFailure
        }
        values[account] = secret
    }

    func delete(account: String) throws {
        deletedAccounts.append(account)
        values.removeValue(forKey: account)
    }
}

private enum AuthorizationFakeCredentialVaultError: Error {
    case syntheticWriteFailure
}

func makeSecretProfile() -> SpotifyAuthorizationProfile {
    SpotifyAuthorizationProfile(
        id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        displayName: "Compatibility Profile",
        clientID: "fixture-client-id",
        authorizationMode: .authorizationCodeWithSecret,
        redirectURI: "http://127.0.0.1:43821/oauth/callback"
    )
}
