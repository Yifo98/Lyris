import Foundation

struct AsyncTranslationRequest: Equatable, Sendable {
    let trackID: String
    let generation: UInt64
}

enum AsyncTranslationCompletion: Equatable, Sendable {
    case translated([String])
    case superseded
}

/// Serializes translation requests at the presentation boundary.
///
/// Cancellation is cooperative at the provider layer, so the coordinator also
/// validates its own generation after every suspension. A provider that ignores
/// cancellation may still finish, but its late value can never be presented.
@MainActor
final class AsyncTranslationCoordinator {
    private struct PendingRequest {
        let generation: UInt64
        let request: AsyncTranslationRequest
        let task: Task<[String], Error>
    }

    private let clock = ContinuousClock()
    private var generation: UInt64 = 0
    private var highestAcceptedRequestGeneration: UInt64?
    private var pending: PendingRequest?

    var pendingRequest: AsyncTranslationRequest? {
        pending?.request
    }

    func translate(
        request: AsyncTranslationRequest,
        debounce: Duration = .milliseconds(250),
        operation: @escaping @MainActor () async throws -> [String]
    ) async throws -> AsyncTranslationCompletion {
        if let highestAcceptedRequestGeneration,
           request.generation < highestAcceptedRequestGeneration {
            return .superseded
        }
        highestAcceptedRequestGeneration = request.generation
        supersedePendingRequest()
        let requestGeneration = generation
        let task = Task { @MainActor [clock] in
            if debounce > .zero {
                try await clock.sleep(for: debounce)
            }
            try Task.checkCancellation()
            return try await operation()
        }
        pending = PendingRequest(
            generation: requestGeneration,
            request: request,
            task: task
        )

        do {
            let translated = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled,
                  pending?.generation == requestGeneration,
                  generation == requestGeneration else {
                return .superseded
            }
            pending = nil
            return .translated(translated)
        } catch {
            let wasSuperseded = pending?.generation != requestGeneration
                || generation != requestGeneration
                || Task.isCancelled
                || error is CancellationError
                || (error as? URLError)?.code == .cancelled
            if pending?.generation == requestGeneration {
                pending = nil
                if wasSuperseded {
                    generation &+= 1
                }
            }
            if wasSuperseded {
                return .superseded
            }
            throw error
        }
    }

    func cancel() {
        supersedePendingRequest()
    }

    private func supersedePendingRequest() {
        generation &+= 1
        pending?.task.cancel()
        pending = nil
    }
}
