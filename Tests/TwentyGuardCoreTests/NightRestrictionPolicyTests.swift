import XCTest
@testable import TwentyGuardCore

final class NightRestrictionPolicyTests: XCTestCase {
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

    private func enabledSettings() -> NightRestrictionSettings {
        NightRestrictionSettings(
            isEnabled: true,
            windDownStart: ClockTime(hour: 20, minute: 0),
            lockStart: ClockTime(hour: 21, minute: 0),
            unlockTime: ClockTime(hour: 7, minute: 0)
        )
    }

    func testDisabledSettingsKeepBaseWorkDuration() {
        let policy = NightRestrictionPolicy(calendar: calendar)
        let status = policy.status(
            now: date("2026-05-03T22:30:00Z"),
            baseWorkDurationSeconds: 35 * 60,
            settings: NightRestrictionSettings(isEnabled: false),
            overrideUntil: nil
        )

        XCTAssertEqual(status.phase, .normal)
        XCTAssertEqual(status.effectiveWorkDurationSeconds, 35 * 60)
        XCTAssertFalse(status.isOverrideActive)
    }

    func testNormalBeforeWindDownUsesBaseDuration() {
        let policy = NightRestrictionPolicy(calendar: calendar)
        let status = policy.status(
            now: date("2026-05-03T19:59:00Z"),
            baseWorkDurationSeconds: 35 * 60,
            settings: enabledSettings(),
            overrideUntil: nil
        )

        XCTAssertEqual(status.phase, .normal)
        XCTAssertEqual(status.effectiveWorkDurationSeconds, 35 * 60)
    }

    func testWindDownUsesThreeProportionalStagesForThirtyFiveMinutes() {
        let policy = NightRestrictionPolicy(calendar: calendar)
        let settings = enabledSettings()

        let first = policy.status(now: date("2026-05-03T20:05:00Z"), baseWorkDurationSeconds: 35 * 60, settings: settings, overrideUntil: nil)
        let second = policy.status(now: date("2026-05-03T20:25:00Z"), baseWorkDurationSeconds: 35 * 60, settings: settings, overrideUntil: nil)
        let third = policy.status(now: date("2026-05-03T20:45:00Z"), baseWorkDurationSeconds: 35 * 60, settings: settings, overrideUntil: nil)

        XCTAssertEqual(first.effectiveWorkDurationSeconds, 25 * 60)
        XCTAssertEqual(second.effectiveWorkDurationSeconds, 15 * 60)
        XCTAssertEqual(third.effectiveWorkDurationSeconds, 5 * 60)
    }

    func testWindDownStagesScaleWithSixtyMinuteBase() {
        let policy = NightRestrictionPolicy(calendar: calendar)
        let settings = enabledSettings()

        let first = policy.status(now: date("2026-05-03T20:05:00Z"), baseWorkDurationSeconds: 60 * 60, settings: settings, overrideUntil: nil)
        let second = policy.status(now: date("2026-05-03T20:25:00Z"), baseWorkDurationSeconds: 60 * 60, settings: settings, overrideUntil: nil)
        let third = policy.status(now: date("2026-05-03T20:45:00Z"), baseWorkDurationSeconds: 60 * 60, settings: settings, overrideUntil: nil)

        XCTAssertEqual(first.effectiveWorkDurationSeconds, 45 * 60)
        XCTAssertEqual(second.effectiveWorkDurationSeconds, 30 * 60)
        XCTAssertEqual(third.effectiveWorkDurationSeconds, 15 * 60)
    }

    func testFullLockCrossesMidnightUntilMorningUnlock() {
        let policy = NightRestrictionPolicy(calendar: calendar)
        let settings = enabledSettings()

        let evening = policy.status(now: date("2026-05-03T21:00:00Z"), baseWorkDurationSeconds: 35 * 60, settings: settings, overrideUntil: nil)
        let overnight = policy.status(now: date("2026-05-04T02:00:00Z"), baseWorkDurationSeconds: 35 * 60, settings: settings, overrideUntil: nil)
        let unlocked = policy.status(now: date("2026-05-04T07:00:00Z"), baseWorkDurationSeconds: 35 * 60, settings: settings, overrideUntil: nil)

        XCTAssertTrue(evening.isLocked)
        XCTAssertTrue(overnight.isLocked)
        XCTAssertEqual(unlocked.phase, .normal)
    }

    func testActiveOverrideSuppressesLockUntilUnlock() {
        let policy = NightRestrictionPolicy(calendar: calendar)
        let settings = enabledSettings()
        let overrideUntil = date("2026-05-04T07:00:00Z")

        let status = policy.status(
            now: date("2026-05-03T22:30:00Z"),
            baseWorkDurationSeconds: 35 * 60,
            settings: settings,
            overrideUntil: overrideUntil
        )

        XCTAssertEqual(status.phase, .normal)
        XCTAssertEqual(status.effectiveWorkDurationSeconds, 35 * 60)
        XCTAssertTrue(status.isOverrideActive)
    }
}
