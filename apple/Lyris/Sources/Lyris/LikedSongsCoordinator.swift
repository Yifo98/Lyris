import Foundation

struct LikedSongsRequestPermit: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case query
        case mutation(desired: Bool, previous: Bool?)
    }

    let trackID: String
    let trackGeneration: UInt64
    let requestGeneration: UInt64
    let kind: Kind
}

struct LikedSongsCoordinator: Sendable {
    private(set) var state: LikedSongsState = .unavailable

    private var currentTrackID: String?
    private var trackGeneration: UInt64 = 0
    private var requestGeneration: UInt64 = 0
    private var hasAccountCapability = false
    private var lastConfirmedAt: TimeInterval?
    private var lastAttemptAt: TimeInterval?

    mutating func selectTrack(
        _ trackID: String?,
        accountCapability: Bool
    ) -> LikedSongsRequestPermit? {
        trackGeneration &+= 1
        requestGeneration &+= 1
        let validTrackID = trackID.flatMap { $0.hasPrefix("spotify:track:") ? $0 : nil }
        currentTrackID = validTrackID
        hasAccountCapability = accountCapability && validTrackID != nil
        lastConfirmedAt = nil
        lastAttemptAt = nil

        guard hasAccountCapability, let trackID = validTrackID else {
            state = .unavailable
            return nil
        }
        state = .checking(lastKnown: nil)
        return permit(trackID: trackID, kind: .query)
    }

    mutating func beginRefresh() -> LikedSongsRequestPermit? {
        guard hasAccountCapability,
              let trackID = currentTrackID,
              trackID.hasPrefix("spotify:track:") else { return nil }
        switch state {
        case .checking, .updating:
            return nil
        case .unavailable, .unknown, .value, .failed:
            break
        }
        requestGeneration &+= 1
        state = .checking(lastKnown: state.displayedValue)
        return permit(trackID: trackID, kind: .query)
    }

    mutating func beginMutation(desired: Bool) -> LikedSongsRequestPermit? {
        guard hasAccountCapability, let trackID = currentTrackID else { return nil }
        let previous = state.displayedValue
        requestGeneration &+= 1
        state = .updating(desired: desired, previous: previous)
        return permit(trackID: trackID, kind: .mutation(desired: desired, previous: previous))
    }

    mutating func completeQuery(
        _ value: Bool,
        permit: LikedSongsRequestPermit,
        at monotonicTime: TimeInterval
    ) -> Bool {
        guard accepts(permit), permit.kind == .query else { return false }
        state = .value(value)
        lastConfirmedAt = monotonicTime
        return true
    }

    mutating func failQuery(
        permit: LikedSongsRequestPermit,
        at monotonicTime: TimeInterval = 0
    ) -> Bool {
        guard accepts(permit), permit.kind == .query else { return false }
        state = .failed(lastKnown: state.displayedValue)
        lastAttemptAt = monotonicTime
        return true
    }

    mutating func completeMutation(
        permit: LikedSongsRequestPermit
    ) -> LikedSongsRequestPermit? {
        guard accepts(permit),
              case .mutation(let desired, _) = permit.kind,
              let trackID = currentTrackID else { return nil }
        requestGeneration &+= 1
        state = .checking(lastKnown: desired)
        return self.permit(trackID: trackID, kind: .query)
    }

    mutating func failMutation(permit: LikedSongsRequestPermit) -> Bool {
        guard accepts(permit),
              case .mutation(_, let previous) = permit.kind else { return false }
        state = .failed(lastKnown: previous)
        return true
    }

    func shouldRefresh(
        at monotonicTime: TimeInterval,
        interval: TimeInterval = 10
    ) -> Bool {
        guard hasAccountCapability, currentTrackID != nil else { return false }
        switch state {
        case .checking, .updating:
            return false
        case .unavailable, .unknown:
            return true
        case .value, .failed:
            guard let referenceTime = lastConfirmedAt ?? lastAttemptAt else { return true }
            return monotonicTime - referenceTime >= max(0, interval)
        }
    }

    private func permit(
        trackID: String,
        kind: LikedSongsRequestPermit.Kind
    ) -> LikedSongsRequestPermit {
        LikedSongsRequestPermit(
            trackID: trackID,
            trackGeneration: trackGeneration,
            requestGeneration: requestGeneration,
            kind: kind
        )
    }

    private func accepts(_ permit: LikedSongsRequestPermit) -> Bool {
        permit.trackID == currentTrackID
            && permit.trackGeneration == trackGeneration
            && permit.requestGeneration == requestGeneration
    }
}
