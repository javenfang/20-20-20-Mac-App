import XCTest
@testable import TwentyGuardCore

final class SessionStateTests: XCTestCase {
    func testPostponeStateSurvivesEncodingRoundTrip() throws {
        let postponedAt = date("2026-05-08T08:02:43Z")
        let state = SessionState(
            workStartTime: nil,
            breakStartTime: nil,
            postponeStartTime: postponedAt,
            postponeDuration: 5 * 60,
            totalPostponedTime: 5 * 60,
            currentWorkDuration: 35 * 60,
            currentBreakDuration: 3 * 60,
            isCustomMode: true,
            lastSaved: date("2026-05-08T08:03:00Z"),
            pausedBySystemEvent: false
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)

        XCTAssertEqual(decoded.postponeStartTime, postponedAt)
        XCTAssertEqual(decoded.postponeDuration, 5 * 60)
        XCTAssertEqual(decoded.totalPostponedTime, 5 * 60)
    }

    func testActivePostponeRestoresAsPostponeInsteadOfFreshStart() {
        let postponedAt = date("2026-05-08T08:02:43Z")
        let state = SessionState(
            workStartTime: nil,
            breakStartTime: nil,
            postponeStartTime: postponedAt,
            postponeDuration: 5 * 60,
            totalPostponedTime: 5 * 60,
            currentWorkDuration: 35 * 60,
            currentBreakDuration: 3 * 60,
            isCustomMode: true,
            lastSaved: date("2026-05-08T08:04:01Z"),
            pausedBySystemEvent: false
        )

        let decision = SessionRecoveryPolicy().decision(
            for: state,
            now: date("2026-05-08T08:04:15Z")
        )

        XCTAssertEqual(decision, .continuePostpone(startTime: postponedAt, duration: 5 * 60, totalPostponedTime: 5 * 60))
    }

    func testExpiredPostponeRestoresAsImmediateBreak() {
        let state = SessionState(
            workStartTime: nil,
            breakStartTime: nil,
            postponeStartTime: date("2026-05-08T08:02:43Z"),
            postponeDuration: 5 * 60,
            totalPostponedTime: 5 * 60,
            currentWorkDuration: 35 * 60,
            currentBreakDuration: 3 * 60,
            isCustomMode: true,
            lastSaved: date("2026-05-08T08:08:00Z"),
            pausedBySystemEvent: false
        )

        let decision = SessionRecoveryPolicy().decision(
            for: state,
            now: date("2026-05-08T08:08:10Z")
        )

        XCTAssertEqual(decision, .startBreakAfterExpiredPostpone(totalPostponedTime: 5 * 60))
    }

    func testCompletingBreakStartsFreshWorkAndClearsStalePostponeState() {
        let completedAt = date("2026-05-08T08:10:00Z")
        let state = SessionState(
            workStartTime: nil,
            breakStartTime: date("2026-05-08T08:07:00Z"),
            postponeStartTime: date("2026-05-08T08:05:00Z"),
            postponeDuration: 10 * 60,
            totalPostponedTime: 5 * 60,
            currentWorkDuration: 35 * 60,
            currentBreakDuration: 3 * 60,
            isCustomMode: true,
            lastSaved: date("2026-05-08T08:09:55Z"),
            pausedBySystemEvent: false
        )

        let nextState = state.completedBreak(now: completedAt)

        XCTAssertEqual(nextState.workStartTime, completedAt)
        XCTAssertNil(nextState.breakStartTime)
        XCTAssertNil(nextState.postponeStartTime)
        XCTAssertEqual(nextState.postponeDuration, 0)
        XCTAssertEqual(nextState.totalPostponedTime, 0)
        XCTAssertEqual(nextState.currentWorkDuration, 35 * 60)
        XCTAssertEqual(nextState.currentBreakDuration, 3 * 60)
        XCTAssertTrue(nextState.isCustomMode)
        XCTAssertEqual(nextState.lastSaved, completedAt)
        XCTAssertFalse(nextState.pausedBySystemEvent)
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)!
    }
}
