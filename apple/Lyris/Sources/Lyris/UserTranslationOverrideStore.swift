import CryptoKit
import Foundation

struct UserTranslationOverrideKey: Hashable, Codable, Sendable {
    let rawValue: String

    static func make(trackID: String, lyric: TimedLyric) -> Self {
        var data = Data()
        append(trackID, to: &data)
        append(String(lyric.startTime.bitPattern, radix: 16), to: &data)
        append(lyric.original, to: &data)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Self(rawValue: digest)
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        data.append(Data("\(bytes.count):".utf8))
        data.append(bytes)
        data.append(0x1E)
    }
}

protocol UserTranslationOverrideStoring: Sendable {
    func load(trackID: String) async -> [UserTranslationOverrideKey: String]
    func set(_ translation: String, for key: UserTranslationOverrideKey, trackID: String) async throws
    func remove(_ key: UserTranslationOverrideKey, trackID: String) async throws
    func clearAll() async throws
}

struct UserTranslationOverrideMutationReceipt {
    let sequence: UInt64
    fileprivate let task: Task<Void, Error>

    func wait() async throws {
        try await task.value
    }
}

/// Owns the ordering boundary for user-edited translations.
///
/// Calls to `set`, `remove`, and `clearAll` are synchronous and main-actor
/// isolated so UI events receive a deterministic sequence before any
/// unstructured task can reorder them. Disk mutations then follow that exact
/// sequence. The latest optimistic intent is also overlaid on every load, so a
/// late generated translation never replaces a user's edit while persistence
/// is still in flight.
@MainActor
final class UserTranslationOverrideCoordinator {
    private enum Intent {
        case set(String)
        case remove
    }

    private let store: any UserTranslationOverrideStoring
    private var sequence: UInt64 = 0
    private var tail: Task<Void, Never>?
    private var intentsByTrack: [String: [UserTranslationOverrideKey: Intent]] = [:]
    private var ignoresPersistedValues = false

    init(store: any UserTranslationOverrideStoring) {
        self.store = store
    }

    @discardableResult
    func set(
        _ translation: String,
        for key: UserTranslationOverrideKey,
        trackID: String
    ) -> UserTranslationOverrideMutationReceipt {
        intentsByTrack[trackID, default: [:]][key] = .set(translation)
        return enqueue { [store] in
            try await store.set(translation, for: key, trackID: trackID)
        }
    }

    @discardableResult
    func remove(
        _ key: UserTranslationOverrideKey,
        trackID: String
    ) -> UserTranslationOverrideMutationReceipt {
        intentsByTrack[trackID, default: [:]][key] = .remove
        return enqueue { [store] in
            try await store.remove(key, trackID: trackID)
        }
    }

    @discardableResult
    func clearAll() -> UserTranslationOverrideMutationReceipt {
        intentsByTrack = [:]
        ignoresPersistedValues = true
        return enqueue { [store] in
            try await store.clearAll()
        }
    }

    func load(trackID: String) async -> [UserTranslationOverrideKey: String] {
        var values = ignoresPersistedValues ? [:] : await store.load(trackID: trackID)
        for (key, intent) in intentsByTrack[trackID, default: [:]] {
            switch intent {
            case .set(let translation):
                values[key] = translation
            case .remove:
                values.removeValue(forKey: key)
            }
        }
        return values
    }

    func applyingOverrides(
        to baseLyrics: [TimedLyric],
        trackID: String
    ) async -> [TimedLyric] {
        let overrides = await load(trackID: trackID)
        return baseLyrics.map { lyric in
            let key = UserTranslationOverrideKey.make(trackID: trackID, lyric: lyric)
            guard let translation = overrides[key] else { return lyric }
            var presented = lyric
            presented.translation = translation
            return presented
        }
    }

    private func enqueue(
        _ operation: @escaping @MainActor () async throws -> Void
    ) -> UserTranslationOverrideMutationReceipt {
        sequence &+= 1
        let mutationSequence = sequence
        let predecessor = tail
        let task = Task { @MainActor in
            await predecessor?.value
            try await operation()
        }
        tail = Task { @MainActor in
            _ = try? await task.value
        }
        return UserTranslationOverrideMutationReceipt(
            sequence: mutationSequence,
            task: task
        )
    }
}

actor UserTranslationOverrideDiskStore: UserTranslationOverrideStoring {
    private struct Document: Codable {
        var trackID: String
        var values: [String: String]
    }

    private let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.rootURL = rootURL ?? LyrisDataLocation.rootURL(fileManager: fileManager)
            .appendingPathComponent("Lyrics/overrides", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(trackID: String) async -> [UserTranslationOverrideKey: String] {
        guard let document = read(trackID: trackID) else { return [:] }
        return Dictionary(uniqueKeysWithValues: document.values.map {
            (UserTranslationOverrideKey(rawValue: $0.key), $0.value)
        })
    }

    func set(
        _ translation: String,
        for key: UserTranslationOverrideKey,
        trackID: String
    ) async throws {
        try Task.checkCancellation()
        var document = read(trackID: trackID) ?? Document(trackID: trackID, values: [:])
        document.values[key.rawValue] = translation
        try write(document)
    }

    func remove(_ key: UserTranslationOverrideKey, trackID: String) async throws {
        try Task.checkCancellation()
        guard var document = read(trackID: trackID) else { return }
        document.values.removeValue(forKey: key.rawValue)
        if document.values.isEmpty {
            let url = fileURL(trackID: trackID)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } else {
            try write(document)
        }
    }

    func clearAll() async throws {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        try FileManager.default.removeItem(at: rootURL)
    }

    private func read(trackID: String) -> Document? {
        guard let data = try? Data(contentsOf: fileURL(trackID: trackID)),
              let document = try? decoder.decode(Document.self, from: data),
              document.trackID == trackID else { return nil }
        return document
    }

    private func write(_ document: Document) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try Task.checkCancellation()
        try data.write(to: fileURL(trackID: document.trackID), options: .atomic)
    }

    private func fileURL(trackID: String) -> URL {
        let digest = SHA256.hash(data: Data(trackID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return rootURL.appendingPathComponent("\(digest).json")
    }
}
