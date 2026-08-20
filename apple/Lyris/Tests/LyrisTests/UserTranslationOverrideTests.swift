import Foundation
import XCTest
@testable import Lyris

final class UserTranslationOverrideTests: XCTestCase {
    func testStableKeyAndPersistenceAcrossStoreInstances() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisOverrideTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let line = TimedLyric(startTime: 12.5, original: "same line", translation: "base")
        let key = UserTranslationOverrideKey.make(trackID: "spotify:track:a", lyric: line)

        try await UserTranslationOverrideDiskStore(rootURL: root)
            .set("用户译文", for: key, trackID: "spotify:track:a")
        let reloaded = await UserTranslationOverrideDiskStore(rootURL: root)
            .load(trackID: "spotify:track:a")

        XCTAssertEqual(reloaded[key], "用户译文")
        XCTAssertEqual(
            key,
            UserTranslationOverrideKey.make(trackID: "spotify:track:a", lyric: line)
        )
    }

    func testKeyChangesWithTrackTimingOrOriginalText() {
        let baseline = TimedLyric(startTime: 12.5, original: "line", translation: "")
        XCTAssertNotEqual(
            UserTranslationOverrideKey.make(trackID: "spotify:track:a", lyric: baseline),
            UserTranslationOverrideKey.make(trackID: "spotify:track:b", lyric: baseline)
        )
        XCTAssertNotEqual(
            UserTranslationOverrideKey.make(trackID: "spotify:track:a", lyric: baseline),
            UserTranslationOverrideKey.make(
                trackID: "spotify:track:a",
                lyric: TimedLyric(startTime: 13, original: "line", translation: "")
            )
        )
        XCTAssertNotEqual(
            UserTranslationOverrideKey.make(trackID: "spotify:track:a", lyric: baseline),
            UserTranslationOverrideKey.make(
                trackID: "spotify:track:a",
                lyric: TimedLyric(startTime: 12.5, original: "changed", translation: "")
            )
        )
    }

    func testRemoveAndClearAll() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisOverrideTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UserTranslationOverrideDiskStore(rootURL: root)
        let line = TimedLyric(startTime: 1, original: "line", translation: "")
        let key = UserTranslationOverrideKey.make(trackID: "track", lyric: line)
        try await store.set("override", for: key, trackID: "track")
        try await store.remove(key, trackID: "track")
        let afterRemove = await store.load(trackID: "track")
        XCTAssertTrue(afterRemove.isEmpty)

        try await store.set("override", for: key, trackID: "track")
        try await store.clearAll()
        let afterClear = await store.load(trackID: "track")
        XCTAssertTrue(afterClear.isEmpty)
    }
}

@MainActor
final class UserTranslationOverrideCoordinatorTests: XCTestCase {
    func testEditsArePersistedInTheSameOrderTheyWereSubmitted() async throws {
        let store = DelayedFirstOverrideStore()
        let coordinator = UserTranslationOverrideCoordinator(store: store)
        let key = UserTranslationOverrideKey(rawValue: "line-key")

        _ = coordinator.set("first", for: key, trackID: "track")
        let latest = coordinator.set("latest", for: key, trackID: "track")
        await store.waitUntilFirstWriteStarted()

        let eventsWhileBlocked = await store.events()
        XCTAssertEqual(eventsWhileBlocked, ["start:first"])

        await store.releaseFirstWrite()
        try await latest.wait()

        let persisted = await store.load(trackID: "track")
        let events = await store.events()
        XCTAssertEqual(persisted[key], "latest")
        XCTAssertEqual(
            events,
            ["start:first", "finish:first", "start:latest", "finish:latest"]
        )
    }

    func testPendingUserEditAlwaysOverridesLateGeneratedTranslation() async throws {
        let store = DelayedFirstOverrideStore()
        let coordinator = UserTranslationOverrideCoordinator(store: store)
        let trackID = "track"
        let generated = TimedLyric(
            startTime: 5,
            original: "original",
            translation: "generated"
        )
        let key = UserTranslationOverrideKey.make(trackID: trackID, lyric: generated)

        let saved = coordinator.set("user-edit", for: key, trackID: trackID)
        await store.waitUntilFirstWriteStarted()
        let presented = await coordinator.applyingOverrides(to: [generated], trackID: trackID)

        XCTAssertEqual(presented.first?.translation, "user-edit")

        await store.releaseFirstWrite()
        try await saved.wait()
    }

    func testSetThenRestoreUsesOneSerialMutationOrderAndRemovesTheOverride() async throws {
        let store = DelayedFirstOverrideStore()
        let coordinator = UserTranslationOverrideCoordinator(store: store)
        let key = UserTranslationOverrideKey(rawValue: "line-key")

        _ = coordinator.set("user-edit", for: key, trackID: "track")
        let restored = coordinator.remove(key, trackID: "track")
        await store.waitUntilFirstWriteStarted()
        await store.releaseFirstWrite()
        try await restored.wait()

        let presented = await coordinator.load(trackID: "track")
        let persisted = await store.load(trackID: "track")
        XCTAssertNil(presented[key])
        XCTAssertNil(persisted[key])
    }
}

private actor DelayedFirstOverrideStore: UserTranslationOverrideStoring {
    private var valuesByTrack: [String: [UserTranslationOverrideKey: String]] = [:]
    private var recordedEvents: [String] = []
    private var shouldDelayFirstWrite = true
    private var firstWriteStarted = false
    private var mayFinishFirstWrite = false

    func load(trackID: String) async -> [UserTranslationOverrideKey: String] {
        valuesByTrack[trackID, default: [:]]
    }

    func set(
        _ translation: String,
        for key: UserTranslationOverrideKey,
        trackID: String
    ) async throws {
        recordedEvents.append("start:\(translation)")
        if shouldDelayFirstWrite {
            shouldDelayFirstWrite = false
            firstWriteStarted = true
            while !mayFinishFirstWrite { await Task.yield() }
        }
        valuesByTrack[trackID, default: [:]][key] = translation
        recordedEvents.append("finish:\(translation)")
    }

    func remove(_ key: UserTranslationOverrideKey, trackID: String) async throws {
        recordedEvents.append("start:remove")
        valuesByTrack[trackID, default: [:]].removeValue(forKey: key)
        recordedEvents.append("finish:remove")
    }

    func clearAll() async throws {
        valuesByTrack = [:]
    }

    func waitUntilFirstWriteStarted() async {
        while !firstWriteStarted { await Task.yield() }
    }

    func releaseFirstWrite() {
        mayFinishFirstWrite = true
    }

    func events() -> [String] {
        recordedEvents
    }
}
