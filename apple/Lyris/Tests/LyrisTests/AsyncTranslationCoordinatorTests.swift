import XCTest
@testable import Lyris

@MainActor
final class AsyncTranslationCoordinatorTests: XCTestCase {
    func testSupersededRequestCannotDeliverALateTranslation() async throws {
        let coordinator = AsyncTranslationCoordinator()
        let controlled = ControlledTranslationOperation()
        let oldRequest = AsyncTranslationRequest(trackID: "track-a", generation: 1)

        let oldTask = Task { @MainActor in
            try await coordinator.translate(request: oldRequest, debounce: .zero) {
                try await controlled.perform()
            }
        }
        await controlled.waitUntilStarted()

        let current = try await coordinator.translate(
            request: AsyncTranslationRequest(trackID: "track-b", generation: 2),
            debounce: .zero
        ) {
            ["current-translation"]
        }
        await controlled.resolve(["stale-translation"])

        let oldCompletion = try await oldTask.value
        XCTAssertEqual(current, .translated(["current-translation"]))
        XCTAssertEqual(oldCompletion, .superseded)
    }

    func testCancellationDuringDebounceNeverStartsTheProviderRequest() async throws {
        let coordinator = AsyncTranslationCoordinator()
        let counter = TranslationCallCounter()
        let request = AsyncTranslationRequest(trackID: "track-a", generation: 1)

        let task = Task { @MainActor in
            try await coordinator.translate(request: request, debounce: .seconds(30)) {
                await counter.recordCall()
                return ["must-not-run"]
            }
        }
        await waitUntil { coordinator.pendingRequest == request }

        coordinator.cancel()

        let completion = try await task.value
        let callCount = await counter.callCount()
        XCTAssertEqual(completion, .superseded)
        XCTAssertEqual(callCount, 0)
    }

    func testNewRequestCancelsAnOlderDebounceBeforeOnlyNewRequestUsesTheProvider() async throws {
        let coordinator = AsyncTranslationCoordinator()
        let counter = TranslationCallCounter()
        let oldRequest = AsyncTranslationRequest(trackID: "track-a", generation: 1)

        let oldTask = Task { @MainActor in
            try await coordinator.translate(request: oldRequest, debounce: .seconds(30)) {
                await counter.recordCall()
                return ["old"]
            }
        }
        await waitUntil { coordinator.pendingRequest == oldRequest }

        let current = try await coordinator.translate(
            request: AsyncTranslationRequest(trackID: "track-b", generation: 2),
            debounce: .zero
        ) {
            await counter.recordCall()
            return ["new"]
        }

        let oldCompletion = try await oldTask.value
        XCTAssertEqual(oldCompletion, .superseded)
        XCTAssertEqual(current, .translated(["new"]))
        let callCount = await counter.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testOlderGenerationArrivingAfterCurrentCompletionNeverStartsProvider() async throws {
        let coordinator = AsyncTranslationCoordinator()
        let counter = TranslationCallCounter()

        let current = try await coordinator.translate(
            request: AsyncTranslationRequest(trackID: "track-b", generation: 2),
            debounce: .zero
        ) {
            ["current"]
        }
        let stale = try await coordinator.translate(
            request: AsyncTranslationRequest(trackID: "track-a", generation: 1),
            debounce: .zero
        ) {
            await counter.recordCall()
            return ["stale"]
        }

        let staleCallCount = await counter.callCount()
        XCTAssertEqual(current, .translated(["current"]))
        XCTAssertEqual(stale, .superseded)
        XCTAssertEqual(staleCallCount, 0)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<500 {
            if condition() { return }
            await Task.yield()
        }
        XCTAssertTrue(false, "Condition did not become true")
    }
}

private actor ControlledTranslationOperation {
    private var continuation: CheckedContinuation<[String], Never>?
    private var started = false

    func perform() async throws -> [String] {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resolve(_ lines: [String]) {
        continuation?.resume(returning: lines)
        continuation = nil
    }
}

private actor TranslationCallCounter {
    private var count = 0

    func recordCall() {
        count += 1
    }

    func callCount() -> Int {
        count
    }
}
