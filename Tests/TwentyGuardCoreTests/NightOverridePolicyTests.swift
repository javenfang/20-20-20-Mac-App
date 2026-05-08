import XCTest
@testable import TwentyGuardCore

final class NightOverridePolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)!
    }

    func testFirstOverrideRequiresSixtySecondsAndGrantsThirtyMinutes() {
        let policy = NightOverridePolicy(calendar: calendar)
        let request = policy.request(overrideNumberForNight: 1)

        XCTAssertEqual(request.waitSeconds, 60)
        XCTAssertEqual(request.unlockSeconds, 30 * 60)
        XCTAssertEqual(request.confirmationLocalizationKey, "nightOverrideConfirmationFirst")
    }

    func testSecondOverrideRequiresNinetySeconds() {
        let policy = NightOverridePolicy(calendar: calendar)
        let request = policy.request(overrideNumberForNight: 2)

        XCTAssertEqual(request.waitSeconds, 90)
        XCTAssertEqual(request.unlockSeconds, 30 * 60)
        XCTAssertEqual(request.confirmationLocalizationKey, "nightOverrideConfirmationSecond")
    }

    func testThirdAndLaterOverridesRequireTwoMinutes() {
        let policy = NightOverridePolicy(calendar: calendar)

        XCTAssertEqual(policy.request(overrideNumberForNight: 3).waitSeconds, 120)
        XCTAssertEqual(policy.request(overrideNumberForNight: 10).waitSeconds, 120)
        XCTAssertEqual(policy.request(overrideNumberForNight: 10).confirmationLocalizationKey, "nightOverrideConfirmationRepeated")
    }

    func testGrantCreatesThirtyMinuteActiveState() {
        let policy = NightOverridePolicy(calendar: calendar)
        let now = date("2026-05-08T22:15:00Z")

        let state = policy.grant(
            now: now,
            reason: .urgentWork,
            nightKey: "2026-05-08",
            overrideNumberForNight: 1
        )

        XCTAssertEqual(state.grantedAt, now)
        XCTAssertEqual(state.until, date("2026-05-08T22:45:00Z"))
        XCTAssertEqual(state.reason, .urgentWork)
        XCTAssertEqual(state.nightKey, "2026-05-08")
        XCTAssertEqual(state.overrideNumberForNight, 1)
        XCTAssertTrue(policy.isActive(state, now: date("2026-05-08T22:44:59Z")))
        XCTAssertFalse(policy.isActive(state, now: date("2026-05-08T22:45:00Z")))
    }

    func testNightKeyUsesScheduleWindDownDayAcrossMidnight() {
        let nightPolicy = NightRestrictionPolicy(calendar: calendar)
        let overridePolicy = NightOverridePolicy(calendar: calendar)
        let settings = NightRestrictionSettings(
            isEnabled: true,
            windDownStart: ClockTime(hour: 20, minute: 0),
            lockStart: ClockTime(hour: 21, minute: 0),
            unlockTime: ClockTime(hour: 7, minute: 0)
        )

        let beforeMidnight = nightPolicy.status(
            now: date("2026-05-08T22:30:00Z"),
            baseWorkDurationSeconds: 20 * 60,
            settings: settings
        )
        let afterMidnight = nightPolicy.status(
            now: date("2026-05-09T02:30:00Z"),
            baseWorkDurationSeconds: 20 * 60,
            settings: settings
        )

        XCTAssertEqual(
            overridePolicy.nightKey(for: beforeMidnight.schedule),
            overridePolicy.nightKey(for: afterMidnight.schedule)
        )
        XCTAssertEqual(overridePolicy.nightKey(for: afterMidnight.schedule), "2026-05-08")
    }
}
