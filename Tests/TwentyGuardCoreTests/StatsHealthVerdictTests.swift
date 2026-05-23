import XCTest
@testable import TwentyGuardCore

final class StatsHealthVerdictTests: XCTestCase {
    func testLongWorkTakesPriority() {
        let day = makeDay(longestWorkSeconds: 96 * 60, breakCompletionRate: 0.95, postponeSessionRate: 0.1)

        let verdict = StatsHealthVerdictEvaluator().verdict(for: day, localize: zhHans)

        XCTAssertEqual(verdict.title, "工作过长")
        XCTAssertEqual(verdict.reason, "最长连续工作 1 小时 36 分钟，超过建议上限")
        XCTAssertEqual(verdict.severity, .warning)
    }

    func testLowBreakCompletionIsRestProblem() {
        let day = makeDay(longestWorkSeconds: 30 * 60, breakCompletionRate: 0.5, postponeSessionRate: 0.1)

        let verdict = StatsHealthVerdictEvaluator().verdict(for: day, localize: zhHans)

        XCTAssertEqual(verdict.title, "休息不足")
        XCTAssertEqual(verdict.reason, "休息完成率 50%，低于 80%")
        XCTAssertEqual(verdict.severity, .warning)
    }

    func testHighPostponeRateIsPostponeProblem() {
        let day = makeDay(longestWorkSeconds: 30 * 60, breakCompletionRate: 0.9, postponeSessionRate: 0.5)

        let verdict = StatsHealthVerdictEvaluator().verdict(for: day, localize: zhHans)

        XCTAssertEqual(verdict.title, "推迟过多")
        XCTAssertEqual(verdict.reason, "推迟会话占比 50%，高于 30%")
        XCTAssertEqual(verdict.severity, .warning)
    }

    func testProtectionBypassTakesPriorityAfterLongWorkAndBreakProblems() {
        let day = makeDay(
            longestWorkSeconds: 30 * 60,
            breakCompletionRate: 0.9,
            postponeSessionRate: 0.1,
            appExitCount: 1,
            temporaryDisableCount: 1
        )

        let verdict = StatsHealthVerdictEvaluator().verdict(for: day, localize: zhHans)

        XCTAssertEqual(verdict.title, "保护被绕过")
        XCTAssertEqual(verdict.reason, "今天有 2 次例外或中断，统计会把它们单独标出")
        XCTAssertEqual(verdict.severity, .warning)
    }

    func testHealthyDayIsNormalRhythm() {
        let day = makeDay(longestWorkSeconds: 35 * 60, breakCompletionRate: 0.9, postponeSessionRate: 0.1)

        let verdict = StatsHealthVerdictEvaluator().verdict(for: day, localize: zhHans)

        XCTAssertEqual(verdict.title, "节奏正常")
        XCTAssertEqual(verdict.reason, "休息完成率达标，连续工作没有明显超长")
        XCTAssertEqual(verdict.severity, .good)
    }

    func testNoDataIsNeutral() {
        let day = makeDay(workSessions: 0, breakOpportunities: 0, completedBreaks: 0, longestWorkSeconds: 0, postponedSessions: 0)

        let verdict = StatsHealthVerdictEvaluator().verdict(for: day, localize: zhHans)

        XCTAssertEqual(verdict.title, "暂无记录")
        XCTAssertEqual(verdict.reason, "今天还没有有效工作会话")
        XCTAssertEqual(verdict.severity, .neutral)
    }

    private func makeDay(
        workSessions: Int = 4,
        breakOpportunities: Int = 4,
        completedBreaks: Int? = nil,
        longestWorkSeconds: Int,
        postponedSessions: Int? = nil,
        breakCompletionRate: Double? = nil,
        postponeSessionRate: Double? = nil,
        appExitCount: Int = 0,
        temporaryDisableCount: Int = 0,
        nightOverrideCount: Int = 0
    ) -> StatsDaySnapshot {
        let completedBreaks = completedBreaks ?? Int(((breakCompletionRate ?? 1.0) * Double(max(1, breakOpportunities))).rounded())
        let postponedSessions = postponedSessions ?? Int(((postponeSessionRate ?? 0.0) * Double(max(1, breakOpportunities))).rounded())

        return StatsDaySnapshot(
            date: Date(timeIntervalSince1970: 0),
            workSessions: workSessions,
            breakOpportunities: breakOpportunities,
            completedBreaks: completedBreaks,
            postponedSessions: postponedSessions,
            totalPostpones: postponedSessions,
            postponesByMinutes: [:],
            totalWorkSeconds: workSessions * 30 * 60,
            longestWorkSeconds: longestWorkSeconds,
            appExitCount: appExitCount,
            appOffSeconds: appExitCount * 10 * 60,
            temporaryDisableCount: temporaryDisableCount,
            temporaryDisableSeconds: temporaryDisableCount * 60 * 60,
            nightOverrideCount: nightOverrideCount,
            nightOverrideSeconds: nightOverrideCount * 30 * 60,
            quality: StatsQualitySummary()
        )
    }

    private func zhHans(_ key: String) -> String {
        AppLocalization.localized(key, language: "zh-Hans")
    }
}
