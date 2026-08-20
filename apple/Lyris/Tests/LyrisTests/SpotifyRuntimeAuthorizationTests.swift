import Foundation
import XCTest
@testable import Lyris

@MainActor
final class SpotifyRuntimeAuthorizationTests: XCTestCase {
    func testSuccessfulAuthorizationCompletionDoesNotWaitForProfileLookup() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let vault = RuntimeAuthorizationVault()
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            persistentSessionDefaults: defaults
        )
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults
        )
        let profile = try runtime.saveConfiguration(
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )
        let completion = SpotifyAuthorizationCompletion(
            profile: SpotifyAuthorizationProfile(
                id: profile.id,
                displayName: "Spotify",
                clientID: profile.clientID,
                redirectURI: profile.redirectURI,
                authorizedAt: Date(),
                grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
            ),
            accessToken: "fixture-access",
            expiresIn: 3_600,
            authorizationFence: broker.authorizationFence(for: profile.id)
        )

        let report = try await runtime.finishAuthorization(completion)

        XCTAssertEqual(report.displayName, "Spotify")
        XCTAssertEqual(report.profile?.authorizedAt, completion.profile.authorizedAt)
    }

    func testProductionRuntimeMigratesLegacyClientAndRefreshTokenTogether() throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-client", forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey)
        let vault = RuntimeAuthorizationVault(values: [
            SpotifyCredentialAccount.legacyRefreshToken: "legacy-refresh",
        ])
        let broker = SpotifySessionBroker(credentialVault: vault)
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults
        )

        let profile = try XCTUnwrap(runtime.configuredProfile())
        let migratedRefreshToken = vault.value(
            for: SpotifyCredentialAccount.refreshToken(for: profile.id)
        )
        let playbackAccount = try runtime.currentPlaybackAccount()

        XCTAssertEqual(profile.clientID, "legacy-client")
        XCTAssertEqual(profile.authorizationMode, .pkce)
        XCTAssertNil(profile.authorizedAt)
        XCTAssertEqual(profile.grantedScopes, SpotifyAuthorizationScopes.accountEnhancement)
        XCTAssertEqual(migratedRefreshToken, "legacy-refresh")
        XCTAssertNil(vault.value(for: SpotifyCredentialAccount.legacyRefreshToken))
        XCTAssertNil(defaults.string(forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey))
        XCTAssertEqual(playbackAccount?.profileID, profile.id)
    }

    func testChangingClientIdentityClearsOnlyThatProfilesCredentials() throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let vault = RuntimeAuthorizationVault()
        let broker = SpotifySessionBroker(credentialVault: vault)
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults
        )
        let original = try runtime.saveConfiguration(
            clientID: "client-a",
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )
        try vault.write(
            "refresh-a",
            account: SpotifyCredentialAccount.refreshToken(for: original.id)
        )

        let updated = try runtime.saveConfiguration(
            clientID: "client-b",
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.clientID, "client-b")
        XCTAssertNil(updated.authorizedAt)
        XCTAssertNil(vault.value(for: SpotifyCredentialAccount.refreshToken(for: original.id)))
    }

    func testSuccessfulRestoreNotifiesOnceAndSavingConfigurationDoesNotNotify() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let vault = RuntimeAuthorizationVault()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeRestoreURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration)
        )
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults
        )
        var notificationCount = 0
        runtime.onAuthorizationChanged = { notificationCount += 1 }
        let redirectURI = "http://127.0.0.1:43821/oauth/callback"

        let profile = try runtime.saveConfiguration(
            clientID: "fixture-client",
            redirectURI: redirectURI
        )
        XCTAssertEqual(notificationCount, 0)
        try vault.write(
            "fixture-refresh",
            account: SpotifyCredentialAccount.refreshToken(for: profile.id)
        )

        _ = try await runtime.restoreConnection(
            clientID: profile.clientID,
            redirectURI: redirectURI
        )
        _ = try await runtime.restoreConnection(
            clientID: profile.clientID,
            redirectURI: redirectURI
        )

        XCTAssertEqual(notificationCount, 1)
    }

    func testOldAuthorizationTimestampIsAdvisoryAndStoredRefreshTokenRestoresImmediately() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "a11ce000-0000-4000-8000-000000000001")!,
            displayName: "Fixture",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        try SpotifyAuthorizationProfileStore(defaults: defaults).save(profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [
            refreshAccount: "synthetic-refresh",
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeRestoreURLProtocol.self]
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: SpotifySessionBroker(
                credentialVault: vault,
                session: URLSession(configuration: configuration)
            ),
            credentialVault: vault,
            defaults: defaults
        )

        let report = try await runtime.restoreConnection(
            clientID: profile.clientID,
            redirectURI: profile.redirectURI
        )

        XCTAssertEqual(report?.displayName, "Fixture")
        XCTAssertEqual(vault.value(for: refreshAccount), "synthetic-refresh")
    }

    func testPersistedSecretProfileCannotEnterProductionPlaybackOrRestore() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-000000000001")!,
            displayName: "Experimental",
            clientID: "fixture-client",
            authorizationMode: .authorizationCodeWithSecret,
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        try SpotifyAuthorizationProfileStore(defaults: defaults).save(profile)
        let vault = RuntimeAuthorizationVault(values: [
            SpotifyCredentialAccount.refreshToken(for: profile.id): "synthetic-refresh",
            SpotifyCredentialAccount.clientSecret(for: profile.id): "synthetic-secret",
        ])
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: SpotifySessionBroker(credentialVault: vault),
            credentialVault: vault,
            defaults: defaults
        )

        do {
            _ = try runtime.currentPlaybackAccount()
            XCTFail("A persisted experimental profile must not enter the production playback runtime")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .authorizationModeUnavailable(.authorizationCodeWithSecret)
            )
        }
        do {
            _ = try await runtime.restoreConnection(
                clientID: profile.clientID,
                redirectURI: profile.redirectURI
            )
            XCTFail("A persisted experimental profile must not enter production restore")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .authorizationModeUnavailable(.authorizationCodeWithSecret)
            )
        }
        XCTAssertEqual(
            vault.value(for: SpotifyCredentialAccount.refreshToken(for: profile.id)),
            "synthetic-refresh"
        )
        XCTAssertEqual(
            vault.value(for: SpotifyCredentialAccount.clientSecret(for: profile.id)),
            "synthetic-secret"
        )
    }

    func testExplicitSaveConvertsAnExperimentalProfileToPKCEAndClearsItsCredentials() throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-000000000002")!,
            displayName: "Experimental",
            clientID: "fixture-client",
            authorizationMode: .authorizationCodeWithSecret,
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        try SpotifyAuthorizationProfileStore(defaults: defaults).save(profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let secretAccount = SpotifyCredentialAccount.clientSecret(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [
            refreshAccount: "synthetic-refresh",
            secretAccount: "synthetic-secret",
        ])
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: SpotifySessionBroker(credentialVault: vault),
            credentialVault: vault,
            defaults: defaults
        )

        let saved = try runtime.saveConfiguration(
            clientID: profile.clientID,
            redirectURI: profile.redirectURI
        )

        XCTAssertEqual(saved.authorizationMode, .pkce)
        XCTAssertNil(saved.authorizedAt)
        XCTAssertTrue(saved.grantedScopes.isEmpty)
        XCTAssertNil(vault.value(for: refreshAccount))
        XCTAssertNil(vault.value(for: secretAccount))
        XCTAssertFalse(vault.readAccounts.contains(secretAccount))
        XCTAssertEqual(try runtime.currentPlaybackAccount()?.authorizationMode, .pkce)
    }

    func testSecretToPKCEConversionRestoresCredentialsWhenProfileSaveFails() throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-000000000004")!,
            displayName: "Experimental",
            clientID: "fixture-client",
            authorizationMode: .authorizationCodeWithSecret,
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let profileStore = RuntimeAuthorizationProfileStore(profile: profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let secretAccount = SpotifyCredentialAccount.clientSecret(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [
            refreshAccount: "synthetic-refresh",
            secretAccount: "synthetic-secret",
        ])
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: SpotifySessionBroker(credentialVault: vault),
            credentialVault: vault,
            defaults: defaults,
            profileStore: profileStore
        )
        profileStore.saveError = RuntimeAuthorizationProfileStoreError.syntheticFailure

        do {
            _ = try runtime.saveConfiguration(
                clientID: profile.clientID,
                redirectURI: profile.redirectURI
            )
            XCTFail("Expected profile persistence to fail")
        } catch RuntimeAuthorizationProfileStoreError.syntheticFailure {
            // Expected: credentials and the prior profile must remain recoverable.
        }

        XCTAssertEqual(try profileStore.profile(id: profile.id), profile)
        XCTAssertEqual(vault.value(for: refreshAccount), "synthetic-refresh")
        XCTAssertEqual(vault.value(for: secretAccount), "synthetic-secret")
        XCTAssertFalse(vault.readAccounts.contains(secretAccount))
    }

    func testSecretCleanupFailureLeavesPKCEProfileFailClosedAndRetriesOnNextSave() throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-000000000006")!,
            displayName: "Experimental",
            clientID: "fixture-client",
            authorizationMode: .authorizationCodeWithSecret,
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let profileStore = SpotifyAuthorizationProfileStore(defaults: defaults)
        try profileStore.save(profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let secretAccount = SpotifyCredentialAccount.clientSecret(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [
            refreshAccount: "synthetic-refresh",
            secretAccount: "synthetic-secret",
        ])
        vault.failDelete(for: secretAccount)
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: SpotifySessionBroker(credentialVault: vault),
            credentialVault: vault,
            defaults: defaults
        )

        do {
            _ = try runtime.saveConfiguration(
                clientID: profile.clientID,
                redirectURI: profile.redirectURI
            )
            XCTFail("Expected Client Secret cleanup to fail")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .credentialCleanupFailed
            )
        }

        let persisted = try XCTUnwrap(profileStore.profile(id: profile.id))
        XCTAssertEqual(persisted.authorizationMode, .pkce)
        XCTAssertNil(persisted.authorizedAt)
        XCTAssertTrue(persisted.grantedScopes.isEmpty)
        XCTAssertNil(vault.value(for: refreshAccount))
        XCTAssertEqual(vault.value(for: secretAccount), "synthetic-secret")
        XCTAssertFalse(vault.readAccounts.contains(secretAccount))

        vault.clearDeleteFailure(for: secretAccount)
        let retried = try runtime.saveConfiguration(
            clientID: profile.clientID,
            redirectURI: profile.redirectURI
        )

        XCTAssertEqual(retried.authorizationMode, .pkce)
        XCTAssertNil(vault.value(for: secretAccount))
        XCTAssertFalse(vault.readAccounts.contains(secretAccount))
    }

    func testSamePKCEConfigurationCleanupFailureBlocksCachedSession() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-00000000000e")!,
            displayName: "Authorized PKCE",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let profileStore = SpotifyAuthorizationProfileStore(defaults: defaults)
        try profileStore.save(profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let secretAccount = SpotifyCredentialAccount.clientSecret(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [
            refreshAccount: "authorized-refresh",
            secretAccount: "stale-secret",
        ])
        vault.failDelete(for: secretAccount)
        SessionIdentityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionIdentityURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        try await broker.adoptAuthorization(
            SpotifyAuthorizationCompletion(
                profile: profile,
                accessToken: "cached-access",
                expiresIn: 3_600,
                authorizationFence: broker.authorizationFence(for: profile.id)
            )
        )
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults
        )

        do {
            _ = try runtime.saveConfiguration(
                clientID: profile.clientID,
                redirectURI: profile.redirectURI
            )
            XCTFail("Expected Client Secret cleanup to fail")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .credentialCleanupFailed
            )
        }

        do {
            _ = try await broker.currentPlayback(
                account: SpotifyPlaybackAccount(profile: profile)
            )
            XCTFail("A cleanup failure must block the already cached PKCE session")
        } catch {
            XCTAssertEqual(error as? SpotifySessionError, .reauthorizationRequired)
        }
        XCTAssertTrue(SessionIdentityURLProtocol.paths.isEmpty)
        XCTAssertEqual(vault.value(for: refreshAccount), "authorized-refresh")
        XCTAssertEqual(vault.value(for: secretAccount), "stale-secret")
    }

    func testRefreshRollbackFailurePersistsSessionBlockAcrossBrokerReconstruction() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-000000000007")!,
            displayName: "Cached identity",
            clientID: "old-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let profileStore = RuntimeAuthorizationProfileStore(profile: profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [
            refreshAccount: "synthetic-refresh",
        ])
        SessionIdentityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionIdentityURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        try await broker.adoptAuthorization(
            SpotifyAuthorizationCompletion(
                profile: profile,
                accessToken: "cached-access",
                expiresIn: 3_600
            )
        )
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults,
            profileStore: profileStore
        )
        profileStore.saveError = RuntimeAuthorizationProfileStoreError.syntheticFailure
        vault.failDelete(for: refreshAccount)
        vault.failWrite(for: refreshAccount)

        do {
            _ = try runtime.saveConfiguration(
                clientID: "new-client",
                redirectURI: profile.redirectURI
            )
            XCTFail("Expected Refresh Token compensation to fail")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .credentialRollbackFailed
            )
        }
        do {
            _ = try await broker.currentPlayback(
                account: SpotifyPlaybackAccount(profile: profile)
            )
            XCTFail("A blocked stale session must not use its cached Access Token")
        } catch {
            XCTAssertEqual(error as? SpotifySessionError, .reauthorizationRequired)
        }

        XCTAssertTrue(SessionIdentityURLProtocol.paths.isEmpty)
        XCTAssertEqual(vault.value(for: refreshAccount), "synthetic-refresh")
        XCTAssertEqual(try profileStore.profile(id: profile.id), profile)

        SessionIdentityURLProtocol.reset()
        let reconstructedBroker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        do {
            _ = try await reconstructedBroker.currentPlayback(
                account: SpotifyPlaybackAccount(profile: profile)
            )
            XCTFail("A persistent session block must survive broker reconstruction")
        } catch {
            XCTAssertEqual(error as? SpotifySessionError, .reauthorizationRequired)
        }
        XCTAssertTrue(SessionIdentityURLProtocol.paths.isEmpty)
    }

    func testStaleAuthorizationCompletionCannotClearANewerSessionFence() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-000000000008")!,
            displayName: "Stale authorization",
            clientID: "old-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let profileStore = RuntimeAuthorizationProfileStore(profile: profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [refreshAccount: "old-refresh"])
        SessionIdentityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionIdentityURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        let staleCompletion = SpotifyAuthorizationCompletion(
            profile: profile,
            accessToken: "stale-access",
            expiresIn: 3_600,
            authorizationFence: broker.authorizationFence(for: profile.id)
        )
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults,
            profileStore: profileStore
        )

        let updated = try runtime.saveConfiguration(
            clientID: "new-client",
            redirectURI: profile.redirectURI
        )
        XCTAssertEqual(updated.clientID, "new-client")

        do {
            try await broker.adoptAuthorization(staleCompletion)
            XCTFail("A stale completion must not clear a newer session fence")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .attemptProfileMismatch
            )
        }
        let reconstructedBroker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        do {
            try await reconstructedBroker.adoptAuthorization(staleCompletion)
            XCTFail("A reconstructed broker must retain the newer fence generation")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .attemptProfileMismatch
            )
        }
        do {
            _ = try await broker.currentPlayback(
                account: SpotifyPlaybackAccount(profile: profile)
            )
            XCTFail("The newer fence must remain blocked")
        } catch {
            XCTAssertEqual(error as? SpotifySessionError, .reauthorizationRequired)
        }
        XCTAssertTrue(SessionIdentityURLProtocol.paths.isEmpty)
        XCTAssertNil(vault.value(for: refreshAccount))
    }

    func testOlderBrokerCannotOverwriteNewerPersistentSessionFence() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-00000000000c")!,
            displayName: "Cross-broker fence",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [refreshAccount: "surviving-refresh"])
        SessionIdentityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionIdentityURLProtocol.self]
        let olderBroker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )

        olderBroker.blockSession(profileID: profile.id)
        let firstBlockedFence = olderBroker.authorizationFence(for: profile.id)
        XCTAssertEqual(firstBlockedFence.generation, 1)
        let completionFromFirstGeneration = SpotifyAuthorizationCompletion(
            profile: profile,
            accessToken: "generation-one-access",
            expiresIn: 3_600,
            authorizationFence: firstBlockedFence
        )

        let newerBroker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        newerBroker.blockSession(profileID: profile.id)
        XCTAssertEqual(olderBroker.authorizationFence(for: profile.id).generation, 2)

        do {
            try await olderBroker.adoptAuthorization(completionFromFirstGeneration)
            XCTFail("An older broker must not overwrite a newer persistent fence")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .attemptProfileMismatch
            )
        }

        XCTAssertEqual(newerBroker.authorizationFence(for: profile.id).generation, 2)
        do {
            _ = try await newerBroker.restoreConnection(
                account: SpotifyPlaybackAccount(profile: profile)
            )
            XCTFail("The newer generation must remain blocked")
        } catch {
            XCTAssertEqual(error as? SpotifySessionError, .reauthorizationRequired)
        }
        XCTAssertTrue(SessionIdentityURLProtocol.paths.isEmpty)
    }

    func testAuthorizationCompletionRollbackFailurePersistsSessionBlock() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-00000000000d")!,
            displayName: "Authorization rollback",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )
        let profileStore = RuntimeAuthorizationProfileStore(profile: profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [refreshAccount: "previous-refresh"])
        SessionIdentityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionIdentityURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        let tokenStore = SpotifyTokenStore(vault: vault)
        let coordinator = SpotifyAuthorizationCoordinator(
            profileStore: profileStore,
            tokenStore: tokenStore,
            pkceFlow: SpotifyPKCEAuthorizationFlow(
                exchanger: broker,
                proofGenerator: {
                    SpotifyPKCEProof(
                        verifier: "synthetic-verifier-value-with-at-least-forty-three-characters",
                        challenge: "synthetic-challenge"
                    )
                },
                stateGenerator: { "authorization-rollback-state" }
            ),
            secretFlow: SpotifySecretAuthorizationFlow(
                exchanger: broker,
                tokenStore: tokenStore,
                stateGenerator: { "unused-secret-state" }
            )
        )
        let attempt = try coordinator.beginAuthorization(profileID: profile.id)
        profileStore.saveError = RuntimeAuthorizationProfileStoreError.syntheticFailure
        vault.failWrite("previous-refresh", for: refreshAccount)
        var callback = URLComponents(string: profile.redirectURI)!
        callback.queryItems = [
            URLQueryItem(name: "code", value: "synthetic-code"),
            URLQueryItem(name: "state", value: attempt.state),
        ]

        do {
            _ = try await coordinator.completeAuthorization(
                callbackURL: try XCTUnwrap(callback.url),
                attempt: attempt
            )
            XCTFail("A failed Refresh Token rollback must fail authorization")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .credentialRollbackFailed
            )
        }

        XCTAssertEqual(vault.value(for: refreshAccount), "new-refresh")
        XCTAssertEqual(SessionIdentityURLProtocol.paths, ["/api/token"])
        let reconstructedBroker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        do {
            _ = try await reconstructedBroker.restoreConnection(
                account: SpotifyPlaybackAccount(profile: profile)
            )
            XCTFail("A reconstructed broker must remain blocked after rollback failure")
        } catch {
            XCTAssertEqual(error as? SpotifySessionError, .reauthorizationRequired)
        }
        XCTAssertEqual(SessionIdentityURLProtocol.paths, ["/api/token"])
    }

    func testCurrentAuthorizationClearsPersistentFenceAcrossBrokerReconstruction() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-00000000000a")!,
            displayName: "Current authorization",
            clientID: "current-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 2),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [refreshAccount: "current-refresh"])
        SessionIdentityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionIdentityURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )

        broker.blockSession(profileID: profile.id)
        let currentFence = broker.authorizationFence(for: profile.id)
        try await broker.adoptAuthorization(
            SpotifyAuthorizationCompletion(
                profile: profile,
                accessToken: "current-access",
                expiresIn: 3_600,
                authorizationFence: currentFence
            )
        )

        let reconstructedBroker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        let report = try await reconstructedBroker.restoreConnection(
            account: SpotifyPlaybackAccount(profile: profile)
        )

        XCTAssertEqual(report?.displayName, "Identity User")
        XCTAssertEqual(SessionIdentityURLProtocol.paths, ["/api/token", "/v1/me"])
    }

    func testBlockedInFlightRefreshCannotPersistRotatedTokenOrReachSpotifyAPI() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5ec2e700-0000-4000-8000-00000000000b")!,
            displayName: "In-flight refresh",
            clientID: "old-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            authorizedAt: Date(timeIntervalSince1970: 1),
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let profileStore = RuntimeAuthorizationProfileStore(profile: profile)
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [refreshAccount: "old-refresh"])
        ControlledRefreshURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledRefreshURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            persistentSessionDefaults: defaults
        )
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: broker,
            credentialVault: vault,
            defaults: defaults,
            profileStore: profileStore
        )
        let refreshTask = Task {
            try await broker.currentPlayback(account: SpotifyPlaybackAccount(profile: profile))
        }
        for _ in 0..<200 where ControlledRefreshURLProtocol.tokenRequestCount == 0 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(ControlledRefreshURLProtocol.tokenRequestCount, 1)

        let updated = try runtime.saveConfiguration(
            clientID: "new-client",
            redirectURI: profile.redirectURI
        )
        ControlledRefreshURLProtocol.releaseTokenResponse()
        do {
            _ = try await refreshTask.value
            XCTFail("A blocked refresh flight must not complete")
        } catch {
            XCTAssertTrue(
                error is CancellationError
                    || (error as? SpotifySessionError) == .reauthorizationRequired
            )
        }

        XCTAssertNil(vault.value(for: refreshAccount))
        XCTAssertEqual(ControlledRefreshURLProtocol.apiRequestCount, 0)
        do {
            _ = try await broker.restoreConnection(
                account: SpotifyPlaybackAccount(profile: updated)
            )
            XCTFail("The replacement profile must remain blocked until authorization succeeds")
        } catch {
            XCTAssertEqual(error as? SpotifySessionError, .reauthorizationRequired)
        }
        XCTAssertEqual(ControlledRefreshURLProtocol.tokenRequestCount, 1)
        XCTAssertEqual(ControlledRefreshURLProtocol.apiRequestCount, 0)
    }

    func testMultipleProfilesFailClosedWithoutMutatingProfilesOrCredentials() async throws {
        let suiteName = "SpotifyRuntimeAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "stale-legacy-client",
            forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey
        )
        let first = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            displayName: "First",
            clientID: "first-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let second = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!,
            displayName: "Second",
            clientID: "second-client",
            authorizationMode: .authorizationCodeWithSecret,
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let profileStore = SpotifyAuthorizationProfileStore(defaults: defaults)
        try profileStore.save(first)
        try profileStore.save(second)
        let firstRefreshAccount = SpotifyCredentialAccount.refreshToken(for: first.id)
        let secondRefreshAccount = SpotifyCredentialAccount.refreshToken(for: second.id)
        let secondSecretAccount = SpotifyCredentialAccount.clientSecret(for: second.id)
        let vault = RuntimeAuthorizationVault(values: [
            firstRefreshAccount: "first-refresh",
            secondRefreshAccount: "second-refresh",
            secondSecretAccount: "second-secret",
        ])
        RuntimeAuthorizationURLProtocol.reset(status: 500, body: #"{"error":"unexpected_network"}"#)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeAuthorizationURLProtocol.self]
        let runtime = SpotifyAuthorizationRuntime(
            sessionBroker: SpotifySessionBroker(
                credentialVault: vault,
                session: URLSession(configuration: configuration)
            ),
            credentialVault: vault,
            defaults: defaults
        )

        assertProfileSelectionRequired { try runtime.configuredProfile() }
        assertProfileSelectionRequired { try runtime.currentPlaybackAccount() }
        assertProfileSelectionRequired {
            try runtime.saveConfiguration(
                clientID: first.clientID,
                redirectURI: first.redirectURI
            )
        }
        do {
            _ = try await runtime.restoreConnection(
                clientID: first.clientID,
                redirectURI: first.redirectURI
            )
            XCTFail("Multiple profiles must not reach Spotify restore")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .profileSelectionRequired
            )
        }

        XCTAssertEqual(try profileStore.allProfiles(), [first, second])
        XCTAssertEqual(vault.value(for: firstRefreshAccount), "first-refresh")
        XCTAssertEqual(vault.value(for: secondRefreshAccount), "second-refresh")
        XCTAssertEqual(vault.value(for: secondSecretAccount), "second-secret")
        XCTAssertEqual(
            defaults.string(forKey: SpotifyLegacyClientIDProfileMigrator.legacyClientIDKey),
            "stale-legacy-client"
        )
        XCTAssertEqual(RuntimeAuthorizationURLProtocol.requestCount, 0)
    }

    private func assertProfileSelectionRequired<T>(
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected profile selection to fail closed")
        } catch {
            XCTAssertEqual(
                error as? SpotifyAuthorizationCoreError,
                .profileSelectionRequired
            )
        }
    }
}

final class SpotifySessionBrokerInvalidGrantTests: XCTestCase {
    func testCachedAccessTokenIsBoundToProfileClientAndAuthorizationMode() async throws {
        let profileID = UUID(uuidString: "5c0fe000-0000-4000-8000-000000000009")!
        let oldProfile = SpotifyAuthorizationProfile(
            id: profileID,
            displayName: "Old identity",
            clientID: "old-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let newProfile = SpotifyAuthorizationProfile(
            id: profileID,
            displayName: "New identity",
            clientID: "new-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
        )
        let vault = RuntimeAuthorizationVault(values: [
            SpotifyCredentialAccount.refreshToken(for: profileID): "new-refresh",
        ])
        SessionIdentityURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionIdentityURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration)
        )
        try await broker.adoptAuthorization(
            SpotifyAuthorizationCompletion(
                profile: oldProfile,
                accessToken: "old-access",
                expiresIn: 3_600
            )
        )

        let report = try await broker.restoreConnection(
            account: SpotifyPlaybackAccount(profile: newProfile)
        )

        XCTAssertEqual(report?.displayName, "Identity User")
        XCTAssertEqual(SessionIdentityURLProtocol.paths, ["/api/token", "/v1/me"])
        XCTAssertTrue(SessionIdentityURLProtocol.tokenRequestBody.contains("client_id=new-client"))
        XCTAssertEqual(SessionIdentityURLProtocol.profileAuthorization, "Bearer new-access")
    }

    func testPlaybackSnapshotCapabilitiesFollowGrantedScopes() async throws {
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "5c0fe000-0000-4000-8000-000000000001")!,
            displayName: "Playback only",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback",
            grantedScopes: [
                "user-read-playback-state",
                "user-read-currently-playing",
                "user-modify-playback-state",
            ]
        )
        let vault = RuntimeAuthorizationVault(values: [
            SpotifyCredentialAccount.refreshToken(for: profile.id): "synthetic-refresh",
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScopeBoundPlaybackURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration)
        )

        let currentPlayback = try await broker.currentPlayback(
            account: SpotifyPlaybackAccount(profile: profile)
        )
        let snapshot = try XCTUnwrap(currentPlayback)

        XCTAssertTrue(snapshot.capabilities.contains(.transport))
        XCTAssertFalse(snapshot.capabilities.contains(.likedSongsRead))
        XCTAssertFalse(snapshot.capabilities.contains(.likedSongsWrite))
        XCTAssertEqual(snapshot.likedState, .unavailable)
    }

    func testInvalidGrantDeletesOnlyProfileRefreshTokenAndDoesNotRetry() async throws {
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            displayName: "Compatibility",
            clientID: "fixture-client",
            authorizationMode: .authorizationCodeWithSecret,
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )
        let refreshAccount = SpotifyCredentialAccount.refreshToken(for: profile.id)
        let secretAccount = SpotifyCredentialAccount.clientSecret(for: profile.id)
        let vault = RuntimeAuthorizationVault(values: [
            refreshAccount: "synthetic-refresh",
            secretAccount: "synthetic-secret",
        ])
        RuntimeAuthorizationURLProtocol.reset(
            status: 400,
            body: #"{"error":"invalid_grant"}"#
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeAuthorizationURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            retryPolicy: SpotifyRetryPolicy(jitter: { _ in 0 }),
            sleep: { _ in XCTFail("invalid_grant must not be retried") }
        )
        let account = SpotifyPlaybackAccount(profile: profile)

        do {
            _ = try await broker.restoreConnection(account: account)
            XCTFail("Expected reauthorization")
        } catch SpotifySessionError.reauthorizationRequired {
            // Expected.
        }

        XCTAssertNil(vault.value(for: refreshAccount))
        XCTAssertEqual(vault.value(for: secretAccount), "synthetic-secret")
        XCTAssertEqual(RuntimeAuthorizationURLProtocol.requestCount, 1)

        do {
            _ = try await broker.restoreConnection(account: account)
            XCTFail("A blocked profile must not retry its deleted token")
        } catch SpotifySessionError.reauthorizationRequired {
            // Expected.
        }
        XCTAssertEqual(RuntimeAuthorizationURLProtocol.requestCount, 1)
    }

    func testRefreshTokenRetriesExplicitServerFailureThenRestoresProfile() async throws {
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            displayName: "Retry",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )
        let vault = RuntimeAuthorizationVault(values: [
            SpotifyCredentialAccount.refreshToken(for: profile.id): "synthetic-refresh",
        ])
        RuntimeAuthorizationURLProtocol.reset(responses: [
            .init(status: 503, body: #"{"error":"temporarily_unavailable"}"#),
            .init(status: 200, body: #"{"access_token":"fixture-access","expires_in":3600}"#),
            .init(status: 200, body: #"{"id":"fixture-user","display_name":"Fixture User"}"#),
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeAuthorizationURLProtocol.self]
        let sleeps = RuntimeAuthorizationSleepRecorder()
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            retryPolicy: SpotifyRetryPolicy(
                configuration: .init(
                    maximumRetryCount: 2,
                    baseDelay: 0.25,
                    maximumDelay: 2,
                    jitterFraction: 0
                ),
                jitter: { _ in 0 }
            ),
            sleep: { delay in sleeps.record(delay) }
        )

        let report = try await broker.restoreConnection(
            account: SpotifyPlaybackAccount(profile: profile)
        )

        XCTAssertEqual(report?.displayName, "Fixture User")
        XCTAssertEqual(RuntimeAuthorizationURLProtocol.requestCount, 3)
        XCTAssertEqual(sleeps.values, [0.25])
    }

    func testRefreshTokenServerRetriesAreBounded() async throws {
        let profile = SpotifyAuthorizationProfile(
            id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
            displayName: "Bounded retry",
            clientID: "fixture-client",
            redirectURI: "http://127.0.0.1:43821/oauth/callback"
        )
        let vault = RuntimeAuthorizationVault(values: [
            SpotifyCredentialAccount.refreshToken(for: profile.id): "synthetic-refresh",
        ])
        RuntimeAuthorizationURLProtocol.reset(
            status: 503,
            body: #"{"error":"temporarily_unavailable"}"#
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeAuthorizationURLProtocol.self]
        let sleeps = RuntimeAuthorizationSleepRecorder()
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            session: URLSession(configuration: configuration),
            retryPolicy: SpotifyRetryPolicy(
                configuration: .init(
                    maximumRetryCount: 2,
                    baseDelay: 0.25,
                    maximumDelay: 2,
                    jitterFraction: 0
                ),
                jitter: { _ in 0 }
            ),
            sleep: { delay in sleeps.record(delay) }
        )

        do {
            _ = try await broker.restoreConnection(
                account: SpotifyPlaybackAccount(profile: profile)
            )
            XCTFail("Expected a bounded server failure")
        } catch let failure as SpotifyNetworkFailure {
            XCTAssertEqual(failure, .server(statusCode: 503))
        }

        XCTAssertEqual(RuntimeAuthorizationURLProtocol.requestCount, 3)
        XCTAssertEqual(sleeps.values, [0.25, 0.5])
        XCTAssertEqual(
            vault.value(for: SpotifyCredentialAccount.refreshToken(for: profile.id)),
            "synthetic-refresh"
        )
    }
}

private final class RuntimeAuthorizationVault: CredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var recordedReadAccounts: [String] = []
    private var deleteFailureAccounts: Set<String> = []
    private var writeFailureAccounts: Set<String> = []
    private var writeFailureValues: [String: Set<String>] = [:]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func read(account: String) throws -> String? {
        lock.withLock {
            recordedReadAccounts.append(account)
            return values[account]
        }
    }

    func write(_ secret: String, account: String) throws {
        try lock.withLock {
            if writeFailureAccounts.contains(account)
                || writeFailureValues[account]?.contains(secret) == true {
                throw RuntimeAuthorizationVaultError.syntheticWriteFailure
            }
            values[account] = secret
        }
    }

    func delete(account: String) throws {
        _ = try lock.withLock {
            if deleteFailureAccounts.contains(account) {
                throw RuntimeAuthorizationVaultError.syntheticDeleteFailure
            }
            values.removeValue(forKey: account)
        }
    }

    func value(for account: String) -> String? {
        lock.withLock { values[account] }
    }

    var readAccounts: [String] {
        lock.withLock { recordedReadAccounts }
    }

    func failDelete(for account: String) {
        _ = lock.withLock { deleteFailureAccounts.insert(account) }
    }

    func clearDeleteFailure(for account: String) {
        _ = lock.withLock { deleteFailureAccounts.remove(account) }
    }

    func failWrite(for account: String) {
        _ = lock.withLock { writeFailureAccounts.insert(account) }
    }

    func failWrite(_ secret: String, for account: String) {
        _ = lock.withLock {
            writeFailureValues[account, default: []].insert(secret)
        }
    }
}

private enum RuntimeAuthorizationVaultError: Error {
    case syntheticDeleteFailure
    case syntheticWriteFailure
}

private enum RuntimeAuthorizationProfileStoreError: Error {
    case syntheticFailure
}

private final class RuntimeAuthorizationProfileStore: SpotifyAuthorizationProfileStoring {
    var saveError: Error?
    private var profiles: [SpotifyAuthorizationProfile]

    init(profile: SpotifyAuthorizationProfile) {
        profiles = [profile]
    }

    func allProfiles() throws -> [SpotifyAuthorizationProfile] {
        profiles
    }

    func profile(id: UUID) throws -> SpotifyAuthorizationProfile? {
        profiles.first(where: { $0.id == id })
    }

    func save(_ profile: SpotifyAuthorizationProfile) throws {
        if let saveError { throw saveError }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    func delete(id: UUID) throws {
        profiles.removeAll(where: { $0.id == id })
    }
}

private final class SessionIdentityURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var recordedPaths: [String] = []
    private static var recordedTokenRequestBody = ""
    private static var recordedProfileAuthorization: String?

    static var paths: [String] { lock.withLock { recordedPaths } }
    static var tokenRequestBody: String { lock.withLock { recordedTokenRequestBody } }
    static var profileAuthorization: String? { lock.withLock { recordedProfileAuthorization } }

    static func reset() {
        lock.withLock {
            recordedPaths = []
            recordedTokenRequestBody = ""
            recordedProfileAuthorization = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let isTokenRequest = request.url?.host == "accounts.spotify.com"
        let requestBody = isTokenRequest
            ? Self.readBody(from: request)
            : nil
        Self.lock.withLock {
            Self.recordedPaths.append(path)
            if isTokenRequest {
                Self.recordedTokenRequestBody = requestBody.map {
                    String(decoding: $0, as: UTF8.self)
                } ?? ""
            } else {
                Self.recordedProfileAuthorization = request.value(
                    forHTTPHeaderField: "Authorization"
                )
            }
        }
        let body = isTokenRequest
            ? #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#
            : #"{"id":"identity-user","display_name":"Identity User"}"#
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                body.append(contentsOf: buffer.prefix(bytesRead))
            } else if bytesRead == 0 {
                return body
            } else {
                return nil
            }
        }
    }
}

private final class ControlledRefreshURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var pendingTokenProtocol: ControlledRefreshURLProtocol?
    private static var tokenRequests = 0
    private static var apiRequests = 0

    static var tokenRequestCount: Int { lock.withLock { tokenRequests } }
    static var apiRequestCount: Int { lock.withLock { apiRequests } }

    static func reset() {
        lock.withLock {
            pendingTokenProtocol = nil
            tokenRequests = 0
            apiRequests = 0
        }
    }

    static func releaseTokenResponse() {
        let pending = lock.withLock { () -> ControlledRefreshURLProtocol? in
            defer { pendingTokenProtocol = nil }
            return pendingTokenProtocol
        }
        pending?.sendTokenResponse()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.path == "/api/token" {
            Self.lock.withLock {
                Self.tokenRequests += 1
                Self.pendingTokenProtocol = self
            }
            return
        }
        Self.lock.withLock { Self.apiRequests += 1 }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"unexpected_api_request"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func sendTokenResponse() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(
            #"{"access_token":"late-access","refresh_token":"late-refresh","expires_in":3600}"#.utf8
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class RuntimeAuthorizationURLProtocol: URLProtocol, @unchecked Sendable {
    struct StubResponse {
        let status: Int
        let body: Data

        init(status: Int, body: String) {
            self.status = status
            self.body = Data(body.utf8)
        }
    }

    private static let lock = NSLock()
    private static var responses = [StubResponse(status: 500, body: "")]
    private static var requests = 0

    static var requestCount: Int { lock.withLock { requests } }

    static func reset(status: Int, body: String) {
        reset(responses: [.init(status: status, body: body)])
    }

    static func reset(responses newResponses: [StubResponse]) {
        lock.withLock {
            responses = newResponses.isEmpty
                ? [StubResponse(status: 500, body: "")]
                : newResponses
            requests = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = Self.lock.withLock { () -> StubResponse in
            Self.requests += 1
            if Self.responses.count > 1 {
                return Self.responses.removeFirst()
            }
            return Self.responses[0]
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: result.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class RuntimeAuthorizationSleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [TimeInterval] = []

    var values: [TimeInterval] { lock.withLock { recordedValues } }

    func record(_ value: TimeInterval) {
        lock.withLock { recordedValues.append(value) }
    }
}

private final class RuntimeRestoreURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: Data
        if request.url?.host == "accounts.spotify.com" {
            body = Data(#"{"access_token":"fixture-access","expires_in":3600}"#.utf8)
        } else {
            body = Data(#"{"id":"fixture-user","display_name":"Fixture User"}"#.utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ScopeBoundPlaybackURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: Data
        if request.url?.host == "accounts.spotify.com" {
            body = Data(#"{"access_token":"fixture-access","expires_in":3600}"#.utf8)
        } else {
            body = Data(#"{"progress_ms":42000,"is_playing":true,"shuffle_state":false,"repeat_state":"off","currently_playing_type":"track","item":{"id":"track-fixture","uri":"spotify:track:track-fixture","name":"Fixture Song","duration_ms":180000,"artists":[{"name":"Fixture Artist"}],"album":{"name":"Fixture Album","images":[]},"show":null,"images":null}}"#.utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
