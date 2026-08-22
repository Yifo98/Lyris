import Foundation

protocol SpotifyAuthorizationProfileStoring {
    func allProfiles() throws -> [SpotifyAuthorizationProfile]
    func profile(id: UUID) throws -> SpotifyAuthorizationProfile?
    func save(_ profile: SpotifyAuthorizationProfile) throws
    func delete(id: UUID) throws
}

protocol SpotifyAuthorizationSettingsStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func write(data: Data?, forKey key: String)
    func write(bool: Bool, forKey key: String)
}

final class SpotifyAuthorizationUserDefaultsSettingsStore: SpotifyAuthorizationSettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    func write(data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
    func write(bool: Bool, forKey key: String) { defaults.set(bool, forKey: key) }
}

enum SpotifyAuthorizationProfileStoreError: Error, Equatable {
    case unsupportedSchema(Int)
}

/// Versioned JSON storage for non-sensitive authorization profiles. The
/// profile model has no Secret or Token field, so this adapter cannot persist
/// either credential into UserDefaults.
final class SpotifyAuthorizationProfileStore: SpotifyAuthorizationProfileStoring {
    static let defaultStorageKey = "spotify.authorizationProfiles.v1"

    private struct Envelope: Codable {
        let schemaVersion: Int
        var profiles: [SpotifyAuthorizationProfile]
    }

    private let settings: any SpotifyAuthorizationSettingsStoring
    private let storageKey: String
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    convenience init(
        defaults: UserDefaults = .standard,
        storageKey: String = defaultStorageKey
    ) {
        self.init(
            settings: SpotifyAuthorizationUserDefaultsSettingsStore(defaults: defaults),
            storageKey: storageKey
        )
    }

    init(
        settings: any SpotifyAuthorizationSettingsStoring,
        storageKey: String = defaultStorageKey
    ) {
        self.settings = settings
        self.storageKey = storageKey
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func allProfiles() throws -> [SpotifyAuthorizationProfile] {
        try withLock { try readProfiles() }
    }

    func profile(id: UUID) throws -> SpotifyAuthorizationProfile? {
        try withLock { try readProfiles().first(where: { $0.id == id }) }
    }

    func save(_ profile: SpotifyAuthorizationProfile) throws {
        try withLock {
            var profiles = try readProfiles()
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }
            try writeProfiles(profiles)
        }
    }

    func delete(id: UUID) throws {
        try withLock {
            var profiles = try readProfiles()
            profiles.removeAll(where: { $0.id == id })
            try writeProfiles(profiles)
        }
    }

    private func readProfiles() throws -> [SpotifyAuthorizationProfile] {
        guard let data = settings.data(forKey: storageKey) else { return [] }
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else {
            throw SpotifyAuthorizationProfileStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope.profiles
    }

    private func writeProfiles(_ profiles: [SpotifyAuthorizationProfile]) throws {
        let ordered = profiles.sorted { $0.id.uuidString < $1.id.uuidString }
        let data = try encoder.encode(Envelope(schemaVersion: 1, profiles: ordered))
        settings.write(data: data, forKey: storageKey)
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

struct SpotifyAuthorizationProfileRotation {
    let previousProfile: SpotifyAuthorizationProfile?
    let candidateProfile: SpotifyAuthorizationProfile

    static func begin(
        profileStore: any SpotifyAuthorizationProfileStoring,
        previousProfile: SpotifyAuthorizationProfile?,
        clientID: String,
        redirectURI: String,
        idGenerator: () -> UUID = { UUID() }
    ) throws -> Self {
        let candidateID = idGenerator()
        guard candidateID != previousProfile?.id else {
            throw SpotifyAuthorizationCoreError.attemptProfileMismatch
        }
        let candidate = SpotifyAuthorizationProfile(
            id: candidateID,
            displayName: previousProfile?.displayName ?? "Spotify",
            clientID: clientID,
            authorizationMode: .pkce,
            redirectURI: redirectURI,
            authorizedAt: nil,
            grantedScopes: []
        )

        if let previousProfile {
            try profileStore.delete(id: previousProfile.id)
        }
        do {
            try profileStore.save(candidate)
        } catch {
            if let previousProfile {
                do {
                    try profileStore.save(previousProfile)
                } catch {
                    throw SpotifyAuthorizationCoreError.credentialRollbackFailed
                }
            }
            throw error
        }
        return Self(
            previousProfile: previousProfile,
            candidateProfile: candidate
        )
    }

    func rollback(
        profileStore: any SpotifyAuthorizationProfileStoring
    ) throws {
        guard let previousProfile else { return }
        try profileStore.delete(id: candidateProfile.id)
        try profileStore.save(previousProfile)
    }
}

struct SpotifyLegacyClientIDProfileMigrator {
    static let legacyClientIDKey = "spotifyClientID"
    static let migrationMarkerKey = "spotify.authorizationProfiles.migratedLegacyClientID.v1"
    static let defaultRedirectURI = "http://127.0.0.1:43821/oauth/callback"

    private let settings: any SpotifyAuthorizationSettingsStoring
    private let profileStore: any SpotifyAuthorizationProfileStoring
    private let tokenStore: SpotifyTokenStore?
    private let idGenerator: () -> UUID

    init(
        settings: any SpotifyAuthorizationSettingsStoring,
        profileStore: any SpotifyAuthorizationProfileStoring,
        tokenStore: SpotifyTokenStore? = nil,
        idGenerator: @escaping () -> UUID = { UUID() }
    ) {
        self.settings = settings
        self.profileStore = profileStore
        self.tokenStore = tokenStore
        self.idGenerator = idGenerator
    }

    /// Migrates only the legacy Client ID. It deliberately leaves
    /// `authorizedAt` nil because an old timestamp cannot prove that the
    /// current refresh credential is still valid.
    func migrateIfNeeded() throws -> SpotifyAuthorizationProfile? {
        let didMigrateClientID = settings.bool(forKey: Self.migrationMarkerKey)
        let clientID = settings.string(forKey: Self.legacyClientIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clientID.isEmpty else { return nil }

        let existingProfile = try profileStore.allProfiles().first(where: { $0.clientID == clientID })
        if didMigrateClientID, existingProfile == nil {
            // A user may have deliberately deleted the migrated profile. Do
            // not recreate it merely because the legacy display value remains.
            return nil
        }

        let createdProfile: SpotifyAuthorizationProfile?
        let profile: SpotifyAuthorizationProfile
        if let existingProfile {
            profile = existingProfile
            createdProfile = nil
        } else {
            let value = SpotifyAuthorizationProfile(
                id: idGenerator(),
                displayName: "Spotify",
                clientID: clientID,
                authorizationMode: .pkce,
                redirectURI: Self.defaultRedirectURI,
                authorizedAt: nil,
                grantedScopes: []
            )
            try profileStore.save(value)
            profile = value
            createdProfile = value
        }

        // This runs even if an earlier build already set the Client-ID marker;
        // that lets the profile-token migration safely repair partial rollout.
        try tokenStore?.migrateLegacyRefreshToken(to: profile.id)
        var migratedProfile = profile
        if migratedProfile.grantedScopes.isEmpty,
           let refreshToken = try tokenStore?.refreshToken(for: profile.id),
           !refreshToken.isEmpty {
            // The legacy Lyris authorization URL requested this exact set.
            // Preserve those known capabilities when moving its token into the
            // profile store; otherwise the new scope gate would disable a
            // previously working account until an unnecessary reauthorization.
            migratedProfile.grantedScopes = SpotifyAuthorizationScopes.accountEnhancement
            try profileStore.save(migratedProfile)
        }
        settings.write(bool: true, forKey: Self.migrationMarkerKey)
        return createdProfile == nil ? nil : migratedProfile
    }
}
