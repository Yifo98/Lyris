import Foundation

/// Owns the ordinary-profile/Keychain split and routes both authorization
/// modes through one completion lifecycle. It never accepts a client secret as
/// part of a Codable profile.
final class SpotifyAuthorizationCoordinator {
    private let profileStore: any SpotifyAuthorizationProfileStoring
    private let tokenStore: SpotifyTokenStore
    private let pkceFlow: any SpotifyAuthorizationFlowing
    private let secretFlow: any SpotifyAuthorizationFlowing
    private let now: () -> Date

    init(
        profileStore: any SpotifyAuthorizationProfileStoring,
        tokenStore: SpotifyTokenStore,
        pkceFlow: any SpotifyAuthorizationFlowing,
        secretFlow: any SpotifyAuthorizationFlowing,
        now: @escaping () -> Date = { Date() }
    ) {
        self.profileStore = profileStore
        self.tokenStore = tokenStore
        self.pkceFlow = pkceFlow
        self.secretFlow = secretFlow
        self.now = now
    }

    func saveProfile(_ profile: SpotifyAuthorizationProfile) throws {
        try profileStore.save(profile)
        if profile.authorizationMode == .pkce {
            do {
                try tokenStore.deleteClientSecret(for: profile.id)
            } catch {
                throw SpotifyAuthorizationCoreError.credentialCleanupFailed
            }
        }
    }

    func installClientSecret(_ value: String, for profileID: UUID) throws {
        guard !value.isEmpty else {
            throw SpotifyAuthorizationCoreError.missingClientSecret
        }
        guard let profile = try profileStore.profile(id: profileID) else {
            throw SpotifyAuthorizationCoreError.profileNotFound
        }
        guard profile.authorizationMode == .authorizationCodeWithSecret else {
            throw SpotifyAuthorizationCoreError.profileModeMismatch
        }
        try tokenStore.storeClientSecret(value, for: profileID)
    }

    func beginAuthorization(
        profileID: UUID,
        scopes: Set<String>? = nil
    ) throws -> SpotifyAuthorizationAttempt {
        guard let profile = try profileStore.profile(id: profileID) else {
            throw SpotifyAuthorizationCoreError.profileNotFound
        }
        return try flow(for: profile.authorizationMode).makeAttempt(
            for: profile,
            scopes: scopes ?? profile.authorizationMode.supportedScopes
        )
    }

    func completeAuthorization(
        callbackURL: URL,
        attempt: SpotifyAuthorizationAttempt
    ) async throws -> SpotifyAuthorizationCompletion {
        guard var profile = try profileStore.profile(id: attempt.profileID) else {
            throw SpotifyAuthorizationCoreError.profileNotFound
        }
        guard profile.id == attempt.profileID,
              profile.clientID == attempt.clientID,
              profile.redirectURI == attempt.redirectURI,
              profile.authorizationMode == attempt.mode else {
            throw SpotifyAuthorizationCoreError.attemptProfileMismatch
        }

        let selectedFlow = flow(for: attempt.mode)
        let grant = try await selectedFlow.exchange(
            callbackURL: callbackURL,
            attempt: attempt
        )
        guard let refreshToken = grant.refreshToken, !refreshToken.isEmpty else {
            throw SpotifyAuthorizationCoreError.missingRefreshToken
        }

        try selectedFlow.withValidAuthorizationFence(attempt.authorizationFence) {
            guard let currentProfile = try profileStore.profile(id: attempt.profileID),
                  currentProfile.clientID == attempt.clientID,
                  currentProfile.redirectURI == attempt.redirectURI,
                  currentProfile.authorizationMode == attempt.mode else {
                throw SpotifyAuthorizationCoreError.attemptProfileMismatch
            }
            profile = currentProfile
            let previousRefreshToken = try tokenStore.refreshToken(for: profile.id)
            try tokenStore.storeRefreshToken(refreshToken, for: profile.id)
            profile.authorizedAt = now()
            profile.grantedScopes = grant.grantedScopes ?? attempt.requestedScopes
            do {
                try profileStore.save(profile)
            } catch {
                do {
                    if let previousRefreshToken {
                        try tokenStore.storeRefreshToken(previousRefreshToken, for: profile.id)
                    } else {
                        try tokenStore.deleteRefreshToken(for: profile.id)
                    }
                } catch {
                    throw SpotifyAuthorizationCoreError.credentialRollbackFailed
                }
                throw error
            }
        }

        return SpotifyAuthorizationCompletion(
            profile: profile,
            accessToken: grant.accessToken,
            expiresIn: grant.expiresIn,
            authorizationFence: attempt.authorizationFence
        )
    }

    func deleteProfile(id: UUID) throws {
        try tokenStore.deleteProfileCredentials(for: id)
        try profileStore.delete(id: id)
    }

    private func flow(for mode: SpotifyAuthorizationMode) -> any SpotifyAuthorizationFlowing {
        switch mode {
        case .pkce:
            precondition(pkceFlow.mode == .pkce, "PKCE flow registered with the wrong mode")
            return pkceFlow
        case .authorizationCodeWithSecret:
            precondition(
                secretFlow.mode == .authorizationCodeWithSecret,
                "Secret flow registered with the wrong mode"
            )
            return secretFlow
        }
    }
}
