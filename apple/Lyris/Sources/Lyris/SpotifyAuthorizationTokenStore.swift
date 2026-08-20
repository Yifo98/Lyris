import Foundation

enum SpotifyCredentialAccount {
    static let legacyRefreshToken = "spotify.refreshToken"

    static func clientSecret(for profileID: UUID) -> String {
        "spotify.clientSecret.\(profileID.uuidString)"
    }

    static func refreshToken(for profileID: UUID) -> String {
        "spotify.refreshToken.\(profileID.uuidString)"
    }
}

/// Stores only high-value Spotify credentials. Passing a
/// `KeychainCredentialVault` keeps both values out of Codable profiles,
/// UserDefaults, and project-local configuration.
struct SpotifyTokenStore {
    private let vault: any CredentialVault

    init(vault: any CredentialVault) {
        self.vault = vault
    }

    func clientSecret(for profileID: UUID) throws -> String? {
        try vault.read(account: SpotifyCredentialAccount.clientSecret(for: profileID))
    }

    func refreshToken(for profileID: UUID) throws -> String? {
        try vault.read(account: SpotifyCredentialAccount.refreshToken(for: profileID))
    }

    func storeClientSecret(_ value: String, for profileID: UUID) throws {
        try store(value, account: SpotifyCredentialAccount.clientSecret(for: profileID))
    }

    func storeRefreshToken(_ value: String, for profileID: UUID) throws {
        try store(value, account: SpotifyCredentialAccount.refreshToken(for: profileID))
    }

    func deleteClientSecret(for profileID: UUID) throws {
        try vault.delete(account: SpotifyCredentialAccount.clientSecret(for: profileID))
    }

    func deleteRefreshToken(for profileID: UUID) throws {
        try vault.delete(account: SpotifyCredentialAccount.refreshToken(for: profileID))
    }

    /// Both removals are attempted even if one Keychain operation fails. The
    /// first error is rethrown after best-effort cleanup of the other account.
    func deleteProfileCredentials(for profileID: UUID) throws {
        var firstError: Error?
        for account in [
            SpotifyCredentialAccount.clientSecret(for: profileID),
            SpotifyCredentialAccount.refreshToken(for: profileID),
        ] {
            do {
                try vault.delete(account: account)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    /// Moves the pre-profile refresh token into the selected profile account.
    /// The legacy value is deleted only after the new value can be read back,
    /// so an interrupted or rejected Keychain write remains recoverable.
    @discardableResult
    func migrateLegacyRefreshToken(to profileID: UUID) throws -> Bool {
        let destination = SpotifyCredentialAccount.refreshToken(for: profileID)
        if let existing = try vault.read(account: destination), !existing.isEmpty {
            if try vault.read(account: SpotifyCredentialAccount.legacyRefreshToken) != nil {
                try vault.delete(account: SpotifyCredentialAccount.legacyRefreshToken)
            }
            return false
        }
        guard let legacy = try vault.read(account: SpotifyCredentialAccount.legacyRefreshToken),
              !legacy.isEmpty else { return false }

        try vault.write(legacy, account: destination)
        guard try vault.read(account: destination) == legacy else {
            try? vault.delete(account: destination)
            throw SpotifyTokenStoreError.migrationVerificationFailed
        }
        try vault.delete(account: SpotifyCredentialAccount.legacyRefreshToken)
        return true
    }

    private func store(_ value: String, account: String) throws {
        if value.isEmpty {
            try vault.delete(account: account)
        } else {
            try vault.write(value, account: account)
        }
    }
}

enum SpotifyTokenStoreError: Error, Equatable {
    case migrationVerificationFailed
}
