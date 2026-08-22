import Foundation
import XCTest
@testable import Lyris

final class SpotifyAuthModeParityTests: XCTestCase {
    func testBothModesExposeTheSameScopeBoundProductRange() throws {
        let vault = AuthorizationFakeCredentialVault()
        let tokenStore = SpotifyTokenStore(vault: vault)
        let pkce = SpotifyPKCEAuthorizationFlow(
            exchanger: AuthorizationFakeTokenExchanger(),
            proofGenerator: {
                SpotifyPKCEProof(
                    verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                    challenge: "synthetic-challenge"
                )
            },
            stateGenerator: { "pkce-state" }
        )
        let secret = SpotifySecretAuthorizationFlow(
            exchanger: AuthorizationFakeTokenExchanger(),
            tokenStore: tokenStore,
            stateGenerator: { "secret-state" }
        )
        let pkceProfile = makePKCEProfile()
        let secretProfile = makeSecretProfile()

        let pkceAttempt = try pkce.makeAttempt(
            for: pkceProfile,
            scopes: pkceProfile.authorizationMode.supportedScopes
        )
        let secretAttempt = try secret.makeAttempt(
            for: secretProfile,
            scopes: secretProfile.authorizationMode.supportedScopes
        )

        XCTAssertEqual(
            SpotifyAuthorizationMode.pkce.supportedScopes,
            SpotifyAuthorizationMode.authorizationCodeWithSecret.supportedScopes
        )
        XCTAssertEqual(pkceAttempt.requestedScopes, secretAttempt.requestedScopes)
        let pkceScope = try queryValues(pkceAttempt.authorizationURL)["scope"]
        let secretScope = try queryValues(secretAttempt.authorizationURL)["scope"]
        XCTAssertEqual(pkceScope, secretScope)
    }

    func testCoordinatorPersistsRefreshTokensAndEqualGrantedScopesForBothModes() async throws {
        let profileStore = AuthorizationFakeProfileStore()
        let vault = AuthorizationFakeCredentialVault()
        let tokenStore = SpotifyTokenStore(vault: vault)
        let pkceExchanger = AuthorizationFakeTokenExchanger()
        let secretExchanger = AuthorizationFakeTokenExchanger()
        let pkce = SpotifyPKCEAuthorizationFlow(
            exchanger: pkceExchanger,
            proofGenerator: {
                SpotifyPKCEProof(
                    verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                    challenge: "synthetic-challenge"
                )
            },
            stateGenerator: { "pkce-state" }
        )
        let secret = SpotifySecretAuthorizationFlow(
            exchanger: secretExchanger,
            tokenStore: tokenStore,
            stateGenerator: { "secret-state" }
        )
        let authorizedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let coordinator = SpotifyAuthorizationCoordinator(
            profileStore: profileStore,
            tokenStore: tokenStore,
            pkceFlow: pkce,
            secretFlow: secret,
            now: { authorizedAt }
        )
        let pkceProfile = makePKCEProfile()
        let secretProfile = makeSecretProfile()
        try coordinator.saveProfile(pkceProfile)
        try coordinator.saveProfile(secretProfile)
        try coordinator.installClientSecret("synthetic-private-value", for: secretProfile.id)

        let pkceAttempt = try coordinator.beginAuthorization(profileID: pkceProfile.id)
        let pkceCompletion = try await coordinator.completeAuthorization(
            callbackURL: try XCTUnwrap(URL(
                string: "http://127.0.0.1:43821/oauth/callback?code=pkce-code&state=pkce-state"
            )),
            attempt: pkceAttempt
        )
        let secretAttempt = try coordinator.beginAuthorization(profileID: secretProfile.id)
        let secretCompletion = try await coordinator.completeAuthorization(
            callbackURL: try XCTUnwrap(URL(
                string: "http://127.0.0.1:43821/oauth/callback?code=secret-code&state=secret-state"
            )),
            attempt: secretAttempt
        )

        XCTAssertEqual(pkceCompletion.profile.grantedScopes, secretCompletion.profile.grantedScopes)
        XCTAssertEqual(pkceCompletion.profile.authorizedAt, authorizedAt)
        XCTAssertEqual(secretCompletion.profile.authorizedAt, authorizedAt)
        let pkceRefreshToken = try tokenStore.refreshToken(for: pkceProfile.id)
        let secretRefreshToken = try tokenStore.refreshToken(for: secretProfile.id)
        XCTAssertEqual(pkceRefreshToken, "synthetic-refresh-value")
        XCTAssertEqual(secretRefreshToken, "synthetic-refresh-value")
    }

    func testDeletingSecretProfileDeletesProfileAndBothKeychainAccounts() throws {
        let profileStore = AuthorizationFakeProfileStore()
        let vault = AuthorizationFakeCredentialVault()
        let tokenStore = SpotifyTokenStore(vault: vault)
        let coordinator = makeCoordinator(profileStore: profileStore, tokenStore: tokenStore)
        let profile = makeSecretProfile()
        try coordinator.saveProfile(profile)
        try coordinator.installClientSecret("synthetic-private-value", for: profile.id)
        try tokenStore.storeRefreshToken("synthetic-refresh-value", for: profile.id)

        try coordinator.deleteProfile(id: profile.id)

        let deletedProfile = try profileStore.profile(id: profile.id)
        let deletedClientSecret = try tokenStore.clientSecret(for: profile.id)
        let deletedRefreshToken = try tokenStore.refreshToken(for: profile.id)
        XCTAssertNil(deletedProfile)
        XCTAssertNil(deletedClientSecret)
        XCTAssertNil(deletedRefreshToken)
    }

    func testSwitchingASecretProfileToPKCERemovesStoredClientSecret() throws {
        let profileStore = AuthorizationFakeProfileStore()
        let vault = AuthorizationFakeCredentialVault()
        let tokenStore = SpotifyTokenStore(vault: vault)
        let coordinator = makeCoordinator(profileStore: profileStore, tokenStore: tokenStore)
        var profile = makeSecretProfile()
        try coordinator.saveProfile(profile)
        try coordinator.installClientSecret("synthetic-private-value", for: profile.id)

        profile.authorizationMode = .pkce
        try coordinator.saveProfile(profile)

        let deletedClientSecret = try tokenStore.clientSecret(for: profile.id)
        XCTAssertNil(deletedClientSecret)
    }

    func testReauthorizationCanReplaceTokenWithoutReadingAnOldBuildCredential() async throws {
        let profileStore = AuthorizationFakeProfileStore()
        let vault = AuthorizationReadDeniedCredentialVault()
        let tokenStore = SpotifyTokenStore(vault: vault)
        let coordinator = makeCoordinator(profileStore: profileStore, tokenStore: tokenStore)
        let profile = makePKCEProfile()
        try coordinator.saveProfile(profile)

        let attempt = try coordinator.beginAuthorization(profileID: profile.id)
        let completion = try await coordinator.completeAuthorization(
            callbackURL: try XCTUnwrap(URL(
                string: "http://127.0.0.1:43821/oauth/callback?code=pkce-code&state=pkce-state"
            )),
            attempt: attempt,
            refreshCredentialPolicy: .replaceWithoutReadingExisting
        )

        XCTAssertEqual(completion.profile.id, profile.id)
        XCTAssertEqual(vault.readAccounts, [])
        XCTAssertEqual(
            vault.writtenValues[SpotifyCredentialAccount.refreshToken(for: profile.id)],
            "synthetic-refresh-value"
        )
    }

    func testAuthorizationProfileRotationUsesFreshIdentityAndCanRollback() throws {
        let profileStore = AuthorizationFakeProfileStore()
        let previous = makePKCEProfile()
        try profileStore.save(previous)
        let candidateID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!

        let rotation = try SpotifyAuthorizationProfileRotation.begin(
            profileStore: profileStore,
            previousProfile: previous,
            clientID: previous.clientID,
            redirectURI: previous.redirectURI,
            idGenerator: { candidateID }
        )

        let candidate = try XCTUnwrap(profileStore.profile(id: candidateID))
        XCTAssertNotEqual(candidate.id, previous.id)
        XCTAssertNil(candidate.authorizedAt)
        XCTAssertEqual(candidate.grantedScopes, [])
        XCTAssertEqual(try profileStore.allProfiles(), [candidate])

        try rotation.rollback(profileStore: profileStore)
        XCTAssertEqual(try profileStore.allProfiles(), [previous])
    }

    func testFirstAuthorizationFailureKeepsTheNewClientConfiguration() throws {
        let profileStore = AuthorizationFakeProfileStore()
        let candidateID = UUID(uuidString: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff")!

        let rotation = try SpotifyAuthorizationProfileRotation.begin(
            profileStore: profileStore,
            previousProfile: nil,
            clientID: "new-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            idGenerator: { candidateID }
        )

        try rotation.rollback(profileStore: profileStore)
        XCTAssertEqual(try profileStore.allProfiles(), [rotation.candidateProfile])
    }
}

final class AuthorizationFakeProfileStore: SpotifyAuthorizationProfileStoring {
    private(set) var profiles: [UUID: SpotifyAuthorizationProfile] = [:]

    func allProfiles() throws -> [SpotifyAuthorizationProfile] { Array(profiles.values) }
    func profile(id: UUID) throws -> SpotifyAuthorizationProfile? { profiles[id] }
    func save(_ profile: SpotifyAuthorizationProfile) throws { profiles[profile.id] = profile }
    func delete(id: UUID) throws { profiles.removeValue(forKey: id) }
}

private final class AuthorizationReadDeniedCredentialVault: CredentialVault {
    private(set) var readAccounts: [String] = []
    private(set) var writtenValues: [String: String] = [:]

    func read(account: String) throws -> String? {
        readAccounts.append(account)
        throw KeychainError.authorizationRequired
    }

    func write(_ secret: String, account: String) throws {
        writtenValues[account] = secret
    }

    func delete(account: String) throws {}
}

private func makeCoordinator(
    profileStore: AuthorizationFakeProfileStore,
    tokenStore: SpotifyTokenStore
) -> SpotifyAuthorizationCoordinator {
    SpotifyAuthorizationCoordinator(
        profileStore: profileStore,
        tokenStore: tokenStore,
        pkceFlow: SpotifyPKCEAuthorizationFlow(
            exchanger: AuthorizationFakeTokenExchanger(),
            proofGenerator: {
                SpotifyPKCEProof(
                    verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                    challenge: "synthetic-challenge"
                )
            },
            stateGenerator: { "pkce-state" }
        ),
        secretFlow: SpotifySecretAuthorizationFlow(
            exchanger: AuthorizationFakeTokenExchanger(),
            tokenStore: tokenStore,
            stateGenerator: { "secret-state" }
        )
    )
}
