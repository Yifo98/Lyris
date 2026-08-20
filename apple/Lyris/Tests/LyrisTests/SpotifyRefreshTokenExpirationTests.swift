import Foundation
import XCTest
@testable import Lyris

final class SpotifyRefreshTokenExpirationTests: XCTestCase {
    func testTokenIsValidBeforeTheFourteenDayReminderWindow() throws {
        let dates = try TestDates()
        let policy = SpotifyRefreshTokenLifetimePolicy(
            calendar: dates.calendar,
            now: { dates.date("2026-06-30T23:59:59Z") }
        )

        XCTAssertEqual(
            policy.status(originalAuthorizationDate: dates.date("2026-01-15T00:00:00Z")),
            .valid(expiresAt: dates.date("2026-07-15T00:00:00Z"))
        )
    }

    func testReminderBecomesDueFourteenDaysBeforeSixMonthExpiry() throws {
        let dates = try TestDates()
        let policy = SpotifyRefreshTokenLifetimePolicy(
            calendar: dates.calendar,
            now: { dates.date("2026-07-01T00:00:00Z") }
        )

        XCTAssertEqual(
            policy.status(originalAuthorizationDate: dates.date("2026-01-15T00:00:00Z")),
            .reauthorizationReminderDue(expiresAt: dates.date("2026-07-15T00:00:00Z"))
        )
    }

    func testTokenIsExpiredAtTheSixCalendarMonthBoundary() throws {
        let dates = try TestDates()
        let policy = SpotifyRefreshTokenLifetimePolicy(
            calendar: dates.calendar,
            now: { dates.date("2026-07-15T00:00:00Z") }
        )

        XCTAssertEqual(
            policy.status(originalAuthorizationDate: dates.date("2026-01-15T00:00:00Z")),
            .expired(at: dates.date("2026-07-15T00:00:00Z"))
        )
    }
}

private struct TestDates {
    let calendar: Calendar
    private let formatter: ISO8601DateFormatter

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        self.calendar = calendar
        formatter = ISO8601DateFormatter()
    }

    func date(_ value: String) -> Date {
        guard let date = formatter.date(from: value) else {
            preconditionFailure("Invalid test date: \(value)")
        }
        return date
    }
}
