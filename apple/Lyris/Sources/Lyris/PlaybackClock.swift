import Foundation

struct PlaybackClockSourceSample: Equatable, Sendable {
    let trackID: String
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
}

enum PlaybackClockEvent: Equatable, Sendable {
    case source(PlaybackClockSourceSample)
    case seek(to: TimeInterval)
    case setPlaying(Bool)
    case clear
}

enum PlaybackClockAdjustment: Equatable, Sendable {
    case reset
    case smoothed
    case snapped
    case ignoredPendingSeek
    case ignoredStaleSource
    case unchanged
}

struct PlaybackClock: Sendable {
    struct Configuration: Equatable, Sendable {
        var smallDriftLimit: TimeInterval = 0.75
        var smoothingFactor: Double = 0.25
        var seekConfirmationWindow: TimeInterval = 1.5
        var seekAcknowledgementTolerance: TimeInterval = 1.5
        var staleSourcePositionTolerance: TimeInterval = 0.05
        var staleSourceMinimumLead: TimeInterval = 0.25
    }

    private struct Anchor: Sendable {
        var trackID: String
        var position: TimeInterval
        var duration: TimeInterval
        var isPlaying: Bool
        var monotonicTime: TimeInterval
        var lastSourcePosition: TimeInterval
        var lastSourceMonotonicTime: TimeInterval
    }

    private struct PendingSeek: Sendable {
        var target: TimeInterval
        var initiatedAt: TimeInterval
    }

    private let configuration: Configuration
    private var anchor: Anchor?
    private var pendingSeek: PendingSeek?

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    @discardableResult
    mutating func apply(
        _ event: PlaybackClockEvent,
        at monotonicTime: TimeInterval
    ) -> PlaybackClockAdjustment {
        switch event {
        case .source(let sample):
            return applySource(sample, at: monotonicTime)
        case .seek(let requestedPosition):
            guard var anchor else { return .unchanged }
            let target = clamp(requestedPosition, duration: anchor.duration)
            anchor.position = target
            anchor.monotonicTime = monotonicTime
            self.anchor = anchor
            pendingSeek = PendingSeek(target: target, initiatedAt: monotonicTime)
            return .reset
        case .setPlaying(let isPlaying):
            guard var anchor, anchor.isPlaying != isPlaying else { return .unchanged }
            anchor.position = position(at: monotonicTime)
            anchor.monotonicTime = monotonicTime
            anchor.isPlaying = isPlaying
            self.anchor = anchor
            return .reset
        case .clear:
            anchor = nil
            pendingSeek = nil
            return .reset
        }
    }

    func position(at monotonicTime: TimeInterval) -> TimeInterval {
        guard let anchor else { return 0 }
        let elapsed = anchor.isPlaying ? max(0, monotonicTime - anchor.monotonicTime) : 0
        return clamp(anchor.position + elapsed, duration: anchor.duration)
    }

    private mutating func applySource(
        _ sample: PlaybackClockSourceSample,
        at monotonicTime: TimeInterval
    ) -> PlaybackClockAdjustment {
        let normalizedDuration = max(0, sample.duration)
        let normalizedPosition = clamp(sample.position, duration: normalizedDuration)

        guard var anchor, anchor.trackID == sample.trackID else {
            self.anchor = Anchor(
                trackID: sample.trackID,
                position: normalizedPosition,
                duration: normalizedDuration,
                isPlaying: sample.isPlaying,
                monotonicTime: monotonicTime,
                lastSourcePosition: normalizedPosition,
                lastSourceMonotonicTime: monotonicTime
            )
            pendingSeek = nil
            return .reset
        }

        if let pendingSeek {
            let projected = position(at: monotonicTime)
            let age = max(0, monotonicTime - pendingSeek.initiatedAt)
            let acknowledgementTolerance = max(0, configuration.seekAcknowledgementTolerance)
            let sourceAcknowledgedSeek = abs(normalizedPosition - projected) <= acknowledgementTolerance
                || abs(normalizedPosition - pendingSeek.target) <= acknowledgementTolerance
            if age < max(0, configuration.seekConfirmationWindow), !sourceAcknowledgedSeek {
                return .ignoredPendingSeek
            }
            self.pendingSeek = nil
        }

        if anchor.isPlaying != sample.isPlaying {
            let projected = position(at: monotonicTime)
            let staleTolerance = max(0, configuration.staleSourcePositionTolerance)
            let minimumLead = max(0, configuration.staleSourceMinimumLead)
            let sourcePositionIsStillFrozen = abs(
                normalizedPosition - anchor.lastSourcePosition
            ) <= staleTolerance
            let projectedPositionIsAhead = projected - normalizedPosition >= minimumLead
            anchor.position = sourcePositionIsStillFrozen && projectedPositionIsAhead
                ? projected
                : normalizedPosition
            anchor.duration = normalizedDuration
            anchor.isPlaying = sample.isPlaying
            anchor.monotonicTime = monotonicTime
            anchor.lastSourcePosition = normalizedPosition
            anchor.lastSourceMonotonicTime = monotonicTime
            self.anchor = anchor
            return .reset
        }

        let projected = position(at: monotonicTime)
        let drift = normalizedPosition - projected
        let sourceDelta = normalizedPosition - anchor.lastSourcePosition
        let sourceAge = max(0, monotonicTime - anchor.lastSourceMonotonicTime)
        let staleTolerance = max(0, configuration.staleSourcePositionTolerance)
        let minimumLead = max(0, configuration.staleSourceMinimumLead)
        let isFrozenPlayingSource = sample.isPlaying
            && sourceAge > 0
            && abs(sourceDelta) <= staleTolerance
            && projected - normalizedPosition >= minimumLead

        anchor.lastSourcePosition = normalizedPosition
        anchor.lastSourceMonotonicTime = monotonicTime
        if isFrozenPlayingSource {
            anchor.duration = normalizedDuration
            self.anchor = anchor
            return .ignoredStaleSource
        }

        anchor.duration = normalizedDuration
        anchor.monotonicTime = monotonicTime
        anchor.isPlaying = sample.isPlaying

        if abs(drift) >= max(0, configuration.smallDriftLimit) {
            anchor.position = normalizedPosition
            self.anchor = anchor
            return .snapped
        }

        let smoothing = min(max(configuration.smoothingFactor, 0), 1)
        anchor.position = clamp(projected + drift * smoothing, duration: normalizedDuration)
        self.anchor = anchor
        return abs(drift) > .ulpOfOne ? .smoothed : .unchanged
    }

    private func clamp(_ position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        let lowerBounded = max(0, position.isFinite ? position : 0)
        guard duration.isFinite, duration > 0 else { return lowerBounded }
        return min(lowerBounded, duration)
    }
}
