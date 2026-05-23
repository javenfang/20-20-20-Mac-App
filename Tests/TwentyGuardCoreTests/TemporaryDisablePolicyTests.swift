import XCTest
@testable import TwentyGuardCore

final class TemporaryDisablePolicyTests: XCTestCase {
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

    private func nightStatus(
        now: Date,
        settings: NightRestrictionSettings = NightRestrictionSettings(isEnabled: true)
    ) -> NightRestrictionStatus {
        NightRestrictionPolicy(calendar: calendar).status(
            now: now,
            baseWorkDurationSeconds: 20 * 60,
            settings: settings
        )
    }

    func testGrantCreatesOneHourDisableState() {
        let policy = TemporaryDisablePolicy()
        let now = date("2026-05-23T10:00:00Z")

        let state = policy.grant(now: now)

        XCTAssertEqual(state.startedAt, now)
        XCTAssertEqual(state.until, date("2026-05-23T11:00:00Z"))
        XCTAssertTrue(policy.isActive(state, now: date("2026-05-23T10:59:59Z")))
        XCTAssertFalse(policy.isActive(state, now: date("2026-05-23T11:00:00Z")))
        XCTAssertEqual(policy.remainingSeconds(state, now: date("2026-05-23T10:30:00Z")), 30 * 60)
    }

    func testCanStartOnlyOutsideNightLockAndNightOverride() {
        let policy = TemporaryDisablePolicy()
        let normalStatus = nightStatus(now: date("2026-05-23T10:00:00Z"))
        let lockedStatus = nightStatus(now: date("2026-05-23T22:00:00Z"))
        let overrideStatus = NightRestrictionPolicy(calendar: calendar).status(
            now: date("2026-05-23T22:00:00Z"),
            baseWorkDurationSeconds: 20 * 60,
            settings: NightRestrictionSettings(isEnabled: true),
            overrideUntil: date("2026-05-23T22:30:00Z")
        )

        XCTAssertTrue(policy.canStart(in: normalStatus))
        XCTAssertFalse(policy.canStart(in: lockedStatus))
        XCTAssertFalse(policy.canStart(in: overrideStatus))
    }

    func testNightLockInterruptsActiveDisable() {
        let policy = TemporaryDisablePolicy()
        let lockedStatus = nightStatus(now: date("2026-05-23T22:00:00Z"))
        let normalStatus = nightStatus(now: date("2026-05-23T10:00:00Z"))
        let overrideStatus = NightRestrictionPolicy(calendar: calendar).status(
            now: date("2026-05-23T22:00:00Z"),
            baseWorkDurationSeconds: 20 * 60,
            settings: NightRestrictionSettings(isEnabled: true),
            overrideUntil: date("2026-05-23T22:30:00Z")
        )

        XCTAssertTrue(policy.shouldInterruptActiveDisable(for: lockedStatus))
        XCTAssertTrue(policy.shouldInterruptActiveDisable(for: overrideStatus))
        XCTAssertFalse(policy.shouldInterruptActiveDisable(for: normalStatus))
    }
}
