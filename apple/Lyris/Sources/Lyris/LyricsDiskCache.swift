import CryptoKit
import Foundation

enum LyricsCacheSource: String, Codable, Sendable {
    case generated
    case manual
}

struct LyricsCacheFingerprint: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 2

    let trackID: String
    let lyricsSourceID: String
    let originalLyricsHash: String
    let targetLanguage: String
    let provider: String
    let model: String
    let thinkingEnabled: Bool
    let promptVersion: String
    let schemaVersion: Int
    let appVersion: String

    static func originalLyricsHash(for lyrics: [TimedLyric]) -> String {
        var canonical = Data()
        for lyric in lyrics {
            append(String(lyric.startTime.bitPattern, radix: 16), to: &canonical)
            append(lyric.isEstimated ? "1" : "0", to: &canonical)
            append(lyric.original, to: &canonical)
        }
        return digest(canonical)
    }

    fileprivate var storageKey: String {
        [
            trackID,
            lyricsSourceID,
            originalLyricsHash,
            targetLanguage,
            provider,
            model,
            thinkingEnabled ? "1" : "0",
            promptVersion,
            String(schemaVersion),
            appVersion,
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
    }

    fileprivate var isComplete: Bool {
        !trackID.isEmpty
            && !lyricsSourceID.isEmpty
            && !originalLyricsHash.isEmpty
            && !targetLanguage.isEmpty
            && !provider.isEmpty
            && !model.isEmpty
            && !promptVersion.isEmpty
            && !appVersion.isEmpty
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        data.append(Data("\(bytes.count):".utf8))
        data.append(bytes)
        data.append(0x1E)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct LyricsCacheLookupKey: Codable, Equatable, Hashable, Sendable {
    let trackID: String
    let targetLanguage: String
    let provider: String
    let model: String
    let thinkingEnabled: Bool
    let promptVersion: String
    let schemaVersion: Int
    let appVersion: String

    init(
        trackID: String,
        targetLanguage: String,
        provider: String,
        model: String,
        thinkingEnabled: Bool,
        promptVersion: String,
        schemaVersion: Int,
        appVersion: String
    ) {
        self.trackID = trackID
        self.targetLanguage = targetLanguage
        self.provider = provider
        self.model = model
        self.thinkingEnabled = thinkingEnabled
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
    }

    init(fingerprint: LyricsCacheFingerprint) {
        trackID = fingerprint.trackID
        targetLanguage = fingerprint.targetLanguage
        provider = fingerprint.provider
        model = fingerprint.model
        thinkingEnabled = fingerprint.thinkingEnabled
        promptVersion = fingerprint.promptVersion
        schemaVersion = fingerprint.schemaVersion
        appVersion = fingerprint.appVersion
    }

    fileprivate var storageKey: String {
        [
            trackID,
            targetLanguage,
            provider,
            model,
            thinkingEnabled ? "1" : "0",
            promptVersion,
            String(schemaVersion),
            appVersion,
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
    }

    fileprivate var compatibleStorageKey: String {
        [trackID, targetLanguage, String(schemaVersion)]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
    }

    fileprivate func matches(_ fingerprint: LyricsCacheFingerprint) -> Bool {
        self == Self(fingerprint: fingerprint)
    }

    fileprivate func isCompatibleFallback(_ fingerprint: LyricsCacheFingerprint) -> Bool {
        fingerprint.isComplete
            && fingerprint.schemaVersion == schemaVersion
            && fingerprint.trackID == trackID
            && fingerprint.targetLanguage == targetLanguage
    }
}

enum LyricsCacheError: Error, Equatable {
    case missingGeneratedFingerprint
    case incompleteFingerprint
    case unsupportedSchemaVersion
    case fingerprintEntryMismatch
}

struct LyricsCacheEntry: Codable, Sendable {
    let trackID: String
    let trackTitle: String
    let artist: String
    let trackDuration: TimeInterval?
    let translationTarget: String?
    let savedAt: Date
    let source: LyricsCacheSource
    let fingerprint: LyricsCacheFingerprint?
    let lyrics: [TimedLyric]
    let document: LyricDocument?

    init(
        trackID: String,
        trackTitle: String,
        artist: String,
        trackDuration: TimeInterval? = nil,
        translationTarget: String? = nil,
        savedAt: Date,
        source: LyricsCacheSource,
        fingerprint: LyricsCacheFingerprint? = nil,
        lyrics: [TimedLyric],
        document: LyricDocument? = nil
    ) {
        self.trackID = trackID
        self.trackTitle = trackTitle
        self.artist = artist
        self.trackDuration = trackDuration
        self.translationTarget = translationTarget
        self.savedAt = savedAt
        self.source = source
        self.fingerprint = fingerprint
        self.lyrics = lyrics
        self.document = document
    }
}

protocol LyricsCaching: Sendable {
    func loadManual(trackID: String) async -> LyricsCacheEntry?
    /// Returns only a cache whose translation configuration matches every lookup field.
    func loadLatestGenerated(matching key: LyricsCacheLookupKey) async -> LyricsCacheEntry?
    /// Offline/error fallback only. It may come from a different provider configuration.
    func loadCompatibleGeneratedFallback(matching key: LyricsCacheLookupKey) async -> LyricsCacheEntry?
    func loadGenerated(fingerprint: LyricsCacheFingerprint) async -> LyricsCacheEntry?
    func save(_ entry: LyricsCacheEntry) async throws
    func clearGenerated() async throws
    func clearManual() async throws
}

extension LyricsCaching {
    func loadCompatibleGeneratedFallback(
        matching key: LyricsCacheLookupKey
    ) async -> LyricsCacheEntry? {
        nil
    }
}

actor LyricsDiskCache: LyricsCaching {
    private let rootURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.rootURL = rootURL ?? LyrisDataLocation.rootURL(fileManager: fileManager)
            .appendingPathComponent("Lyrics", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadManual(trackID: String) async -> LyricsCacheEntry? {
        loadEntry(at: manualFileURL(trackID: trackID), trackID: trackID, source: .manual)
    }

    func loadGenerated(fingerprint: LyricsCacheFingerprint) async -> LyricsCacheEntry? {
        guard fingerprint.schemaVersion == LyricsCacheFingerprint.currentSchemaVersion,
              fingerprint.isComplete else { return nil }

        guard let generated = loadEntry(
            at: generatedFileURL(fingerprint: fingerprint),
            trackID: fingerprint.trackID,
            source: .generated
        ),
        isReusableGeneratedEntry(generated),
        generated.fingerprint == fingerprint else { return nil }
        return generated
    }

    func loadLatestGenerated(matching key: LyricsCacheLookupKey) async -> LyricsCacheEntry? {
        guard key.schemaVersion == LyricsCacheFingerprint.currentSchemaVersion else { return nil }

        guard let exact = loadEntry(
            at: latestGeneratedFileURL(key: key),
            trackID: key.trackID,
            source: .generated
        ), isReusableGeneratedEntry(exact),
        let fingerprint = exact.fingerprint,
        key.matches(fingerprint) else { return nil }
        return exact
    }

    func loadCompatibleGeneratedFallback(
        matching key: LyricsCacheLookupKey
    ) async -> LyricsCacheEntry? {
        guard key.schemaVersion == LyricsCacheFingerprint.currentSchemaVersion else { return nil }

        if let compatible = loadEntry(
            at: compatibleGeneratedFileURL(key: key),
            trackID: key.trackID,
            source: .generated
        ), isReusableGeneratedEntry(compatible),
           let fingerprint = compatible.fingerprint,
           key.isCompatibleFallback(fingerprint) {
            return compatible
        }

        guard let migrated = latestCompatibleGeneratedEntry(matching: key) else { return nil }
        persistCompatiblePointerBestEffort(migrated, key: key)
        return migrated
    }

    func save(_ entry: LyricsCacheEntry) async throws {
        try Task.checkCancellation()
        let url: URL
        switch entry.source {
        case .manual:
            url = manualFileURL(trackID: entry.trackID)
        case .generated:
            guard let fingerprint = entry.fingerprint else {
                throw LyricsCacheError.missingGeneratedFingerprint
            }
            guard fingerprint.isComplete else {
                throw LyricsCacheError.incompleteFingerprint
            }
            guard fingerprint.schemaVersion == LyricsCacheFingerprint.currentSchemaVersion else {
                throw LyricsCacheError.unsupportedSchemaVersion
            }
            guard fingerprint.trackID == entry.trackID,
                  entry.translationTarget == fingerprint.targetLanguage else {
                throw LyricsCacheError.fingerprintEntryMismatch
            }
            url = generatedFileURL(fingerprint: fingerprint)
        }

        let directory = directoryURL(for: entry.source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(entry)
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
        if let fingerprint = entry.fingerprint, entry.source == .generated {
            let latestURL = latestGeneratedFileURL(key: LyricsCacheLookupKey(fingerprint: fingerprint))
            try FileManager.default.createDirectory(
                at: latestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Task.checkCancellation()
            try data.write(to: latestURL, options: .atomic)

            let compatibleURL = compatibleGeneratedFileURL(
                key: LyricsCacheLookupKey(fingerprint: fingerprint)
            )
            try FileManager.default.createDirectory(
                at: compatibleURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Task.checkCancellation()
            try data.write(to: compatibleURL, options: .atomic)
        }
    }

    func clearGenerated() async throws {
        try clearDirectory(for: .generated)
    }

    func clearManual() async throws {
        try clearDirectory(for: .manual)
    }

    private func clearDirectory(for source: LyricsCacheSource) throws {
        let directory = directoryURL(for: source)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func manualFileURL(trackID: String) -> URL {
        directoryURL(for: .manual).appendingPathComponent("\(digest(trackID)).json")
    }

    private func generatedFileURL(fingerprint: LyricsCacheFingerprint) -> URL {
        directoryURL(for: .generated).appendingPathComponent("\(digest(fingerprint.storageKey)).json")
    }

    private func latestGeneratedFileURL(key: LyricsCacheLookupKey) -> URL {
        directoryURL(for: .generated)
            .appendingPathComponent("latest", isDirectory: true)
            .appendingPathComponent("\(digest(key.storageKey)).json")
    }

    private func compatibleGeneratedFileURL(key: LyricsCacheLookupKey) -> URL {
        directoryURL(for: .generated)
            .appendingPathComponent("latest-compatible", isDirectory: true)
            .appendingPathComponent("\(digest(key.compatibleStorageKey)).json")
    }

    private func directoryURL(for source: LyricsCacheSource) -> URL {
        rootURL.appendingPathComponent(source.rawValue, isDirectory: true)
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func loadEntry(
        at url: URL,
        trackID: String,
        source: LyricsCacheSource
    ) -> LyricsCacheEntry? {
        guard let data = try? Data(contentsOf: url),
              let entry = try? decoder.decode(LyricsCacheEntry.self, from: data),
              entry.trackID == trackID,
              entry.source == source else { return nil }
        return entry
    }

    private func latestCompatibleGeneratedEntry(
        matching key: LyricsCacheLookupKey
    ) -> LyricsCacheEntry? {
        let directory = directoryURL(for: .generated)
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return nil }

        return fileURLs
            .filter { $0.pathExtension == "json" }
            .compactMap { loadEntry(at: $0, trackID: key.trackID, source: .generated) }
            .filter { entry in
                guard isReusableGeneratedEntry(entry),
                      let fingerprint = entry.fingerprint else { return false }
                return key.isCompatibleFallback(fingerprint)
            }
            .max { $0.savedAt < $1.savedAt }
    }

    private func isReusableGeneratedEntry(_ entry: LyricsCacheEntry) -> Bool {
        guard entry.source == .generated,
              !entry.lyrics.isEmpty,
              let fingerprint = entry.fingerprint else { return false }
        return fingerprint.isComplete
            && fingerprint.schemaVersion == LyricsCacheFingerprint.currentSchemaVersion
            && fingerprint.trackID == entry.trackID
            && fingerprint.targetLanguage == entry.translationTarget
    }

    private func persistCompatiblePointerBestEffort(
        _ entry: LyricsCacheEntry,
        key: LyricsCacheLookupKey
    ) {
        guard let data = try? encoder.encode(entry) else { return }
        let url = compatibleGeneratedFileURL(key: key)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // A fallback pointer is only an index. The canonical fingerprinted entry remains valid.
        }
    }
}
