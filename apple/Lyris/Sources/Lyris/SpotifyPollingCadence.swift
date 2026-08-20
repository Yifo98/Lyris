import Foundation

struct SpotifyPollingCadence: Sendable {
    enum Outcome: Equatable, Sendable {
        case playbackAvailable
        case idle
        case noAccount
        case offline
        case failure
    }

    private var consecutiveUnavailableResults = 0

    mutating func nextDelay(after outcome: Outcome) -> TimeInterval {
        switch outcome {
        case .playbackAvailable:
            consecutiveUnavailableResults = 0
            return 1.5
        case .idle:
            consecutiveUnavailableResults = 0
            return 3
        case .noAccount, .offline, .failure:
            let exponent = min(consecutiveUnavailableResults, 4)
            consecutiveUnavailableResults = min(consecutiveUnavailableResults + 1, 5)
            return min(4 * pow(2, Double(exponent)), 60)
        }
    }
}
