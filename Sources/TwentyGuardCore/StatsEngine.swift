import Foundation

public enum StatsRecordStatus: String, Codable, Equatable, Sendable {
    case active
    case completed
    case interrupted
    case unknown
}

public enum StatsSessionStatus: String, Codable, Equatable, Sendable {
    case active
    case completed
    case interrupted
    case unknown
}

public enum StatsEventType: String, Codable, Equatable, Sendable {
    case appLaunched = "app_launched"
    case appTerminated = "app_terminated"
    case temporaryDisableStarted = "temporary_disable_started"
    case temporaryDisableEnded = "temporary_disable_ended"
    case temporaryDisableExpired = "temporary_disable_expired"
    case nightOverrideRequested = "night_override_requested"
    case nightOverrideGranted = "night_override_granted"
    case nightOverrideCancelled = "night_override_cancelled"
    case nightOverrideExpired = "night_override_expired"
    case unknown
}

public struct StatsPostponeRecord: Equatable, Sendable {
    public let durationSeconds: Int
    public let startTime: Date
    public let endTime: Date?
    public let status: StatsRecordStatus

    public init(durationSeconds: Int, startTime: Date, endTime: Date?, status: StatsRecordStatus) {
        self.durationSeconds = durationSeconds
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
    }
}

public struct StatsBreakRecord: Equatable, Sendable {
    public let plannedDurationSeconds: Int
    public let actualDurationSeconds: Int?
    public let startTime: Date
    public let endTime: Date?
    public let status: StatsRecordStatus

    public init(
        plannedDurationSeconds: Int,
        actualDurationSeconds: Int?,
        startTime: Date,
        endTime: Date?,
        status: StatsRecordStatus
    ) {
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
    }
}

public struct StatsEventRecord: Equatable, Sendable {
    public let id: Int64
    public let type: StatsEventType
    public let timestamp: Date
    public let durationSeconds: Int?
    public let endTime: Date?
    public let nightKey: String?
    public let context: [String: String]

    public init(
        id: Int64,
        type: StatsEventType,
        timestamp: Date,
        durationSeconds: Int?,
        endTime: Date?,
        nightKey: String?,
        context: [String: String]
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.endTime = endTime
        self.nightKey = nightKey
        self.context = context
    }
}

public struct StatsSessionRecord: Equatable, Sendable {
    public let id: Int64
    public let startTime: Date
    public let endTime: Date?
    public let plannedDurationSeconds: Int
    public let actualWorkDurationSeconds: Int?
    public let recordedPostponeCount: Int?
    public let postponeTotalDurationSeconds: Int
    public let postpones: [StatsPostponeRecord]
    public let breakRecord: StatsBreakRecord?
    public let breakCompleted: Bool
    public let status: StatsSessionStatus

    public init(
        id: Int64,
        startTime: Date,
        endTime: Date?,
        plannedDurationSeconds: Int,
        actualWorkDurationSeconds: Int?,
        recordedPostponeCount: Int? = nil,
        postponeTotalDurationSeconds: Int,
        postpones: [StatsPostponeRecord],
        breakRecord: StatsBreakRecord?,
        breakCompleted: Bool,
        status: StatsSessionStatus
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualWorkDurationSeconds = actualWorkDurationSeconds
        self.recordedPostponeCount = recordedPostponeCount
        self.postponeTotalDurationSeconds = postponeTotalDurationSeconds
        self.postpones = postpones
        self.breakRecord = breakRecord
        self.breakCompleted = breakCompleted
        self.status = status
    }
}

public struct StatsQualitySummary: Equatable, Sendable {
    public var ignoredShortSessions: Int
    public var excludedStaleSessions: Int
    public var excludedStaleSessionIDs: [Int64]
    public var activeBreakRecords: Int
    public var activeBreakSessionIDs: [Int64]
    public var interruptedBreakRecords: Int
    public var interruptedBreakSessionIDs: [Int64]
    public var unclosedPostponeRecords: Int
    public var unclosedPostponeSessionIDs: [Int64]

    public init(
        ignoredShortSessions: Int = 0,
        excludedStaleSessions: Int = 0,
        excludedStaleSessionIDs: [Int64] = [],
        activeBreakRecords: Int = 0,
        activeBreakSessionIDs: [Int64] = [],
        interruptedBreakRecords: Int = 0,
        interruptedBreakSessionIDs: [Int64] = [],
        unclosedPostponeRecords: Int = 0,
        unclosedPostponeSessionIDs: [Int64] = []
    ) {
        self.ignoredShortSessions = ignoredShortSessions
        self.excludedStaleSessions = excludedStaleSessions
        self.excludedStaleSessionIDs = excludedStaleSessionIDs
        self.activeBreakRecords = activeBreakRecords
        self.activeBreakSessionIDs = activeBreakSessionIDs
        self.interruptedBreakRecords = interruptedBreakRecords
        self.interruptedBreakSessionIDs = interruptedBreakSessionIDs
        self.unclosedPostponeRecords = unclosedPostponeRecords
        self.unclosedPostponeSessionIDs = unclosedPostponeSessionIDs
    }

    public var hasIssues: Bool {
        excludedStaleSessions > 0 ||
            activeBreakRecords > 0 ||
            interruptedBreakRecords > 0 ||
            unclosedPostponeRecords > 0
    }

    public var diagnosticSessionIDs: [Int64] {
        var seen = Set<Int64>()
        let all = excludedStaleSessionIDs +
            activeBreakSessionIDs +
            interruptedBreakSessionIDs +
            unclosedPostponeSessionIDs
        return all.filter { seen.insert($0).inserted }
    }

    public mutating func merge(_ other: StatsQualitySummary) {
        ignoredShortSessions += other.ignoredShortSessions
        excludedStaleSessions += other.excludedStaleSessions
        excludedStaleSessionIDs.append(contentsOf: other.excludedStaleSessionIDs)
        activeBreakRecords += other.activeBreakRecords
        activeBreakSessionIDs.append(contentsOf: other.activeBreakSessionIDs)
        interruptedBreakRecords += other.interruptedBreakRecords
        interruptedBreakSessionIDs.append(contentsOf: other.interruptedBreakSessionIDs)
        unclosedPostponeRecords += other.unclosedPostponeRecords
        unclosedPostponeSessionIDs.append(contentsOf: other.unclosedPostponeSessionIDs)
    }
}

public struct StatsDaySnapshot: Equatable, Sendable {
    public let date: Date
    public let workSessions: Int
    public let breakOpportunities: Int
    public let completedBreaks: Int
    public let postponedSessions: Int
    public let totalPostpones: Int
    public let postponesByMinutes: [Int: Int]
    public let totalWorkSeconds: Int
    public let longestWorkSeconds: Int
    public let appExitCount: Int
    public let appOffSeconds: Int
    public let temporaryDisableCount: Int
    public let temporaryDisableSeconds: Int
    public let nightOverrideCount: Int
    public let nightOverrideSeconds: Int
    public let quality: StatsQualitySummary

    public init(
        date: Date,
        workSessions: Int,
        breakOpportunities: Int,
        completedBreaks: Int,
        postponedSessions: Int,
        totalPostpones: Int,
        postponesByMinutes: [Int: Int],
        totalWorkSeconds: Int,
        longestWorkSeconds: Int,
        appExitCount: Int = 0,
        appOffSeconds: Int = 0,
        temporaryDisableCount: Int = 0,
        temporaryDisableSeconds: Int = 0,
        nightOverrideCount: Int = 0,
        nightOverrideSeconds: Int = 0,
        quality: StatsQualitySummary
    ) {
        self.date = date
        self.workSessions = workSessions
        self.breakOpportunities = breakOpportunities
        self.completedBreaks = completedBreaks
        self.postponedSessions = postponedSessions
        self.totalPostpones = totalPostpones
        self.postponesByMinutes = postponesByMinutes
        self.totalWorkSeconds = totalWorkSeconds
        self.longestWorkSeconds = longestWorkSeconds
        self.appExitCount = appExitCount
        self.appOffSeconds = appOffSeconds
        self.temporaryDisableCount = temporaryDisableCount
        self.temporaryDisableSeconds = temporaryDisableSeconds
        self.nightOverrideCount = nightOverrideCount
        self.nightOverrideSeconds = nightOverrideSeconds
        self.quality = quality
    }

    public var breakCompletionRate: Double {
        guard breakOpportunities > 0 else { return 0 }
        return Double(completedBreaks) / Double(breakOpportunities)
    }

    public var postponeSessionRate: Double {
        guard breakOpportunities > 0 else { return 0 }
        return Double(postponedSessions) / Double(breakOpportunities)
    }

    public var exceptionCount: Int {
        appExitCount + temporaryDisableCount + nightOverrideCount
    }

    public var hasProtectionBypass: Bool {
        exceptionCount > 0
    }

    public var isHealthyDay: Bool {
        breakOpportunities > 0 &&
            breakCompletionRate >= 0.8 &&
            postponeSessionRate <= 0.3 &&
            longestWorkSeconds <= 90 * 60 &&
            !hasProtectionBypass &&
            quality.excludedStaleSessions == 0
    }
}

public struct StatsWeekSnapshot: Equatable, Sendable {
    public let days: [StatsDaySnapshot]

    public init(days: [StatsDaySnapshot]) {
        self.days = days
    }

    public var totalWorkSeconds: Int {
        days.reduce(0) { $0 + $1.totalWorkSeconds }
    }

    public var totalWorkSessions: Int {
        days.reduce(0) { $0 + $1.workSessions }
    }

    public var totalBreakOpportunities: Int {
        days.reduce(0) { $0 + $1.breakOpportunities }
    }

    public var totalCompletedBreaks: Int {
        days.reduce(0) { $0 + $1.completedBreaks }
    }

    public var totalPostponedSessions: Int {
        days.reduce(0) { $0 + $1.postponedSessions }
    }

    public var totalPostpones: Int {
        days.reduce(0) { $0 + $1.totalPostpones }
    }

    public var totalAppExits: Int {
        days.reduce(0) { $0 + $1.appExitCount }
    }

    public var totalAppOffSeconds: Int {
        days.reduce(0) { $0 + $1.appOffSeconds }
    }

    public var totalTemporaryDisableSeconds: Int {
        days.reduce(0) { $0 + $1.temporaryDisableSeconds }
    }

    public var totalNightOverrideSeconds: Int {
        days.reduce(0) { $0 + $1.nightOverrideSeconds }
    }

    public var activeDays: Int {
        days.filter { $0.workSessions > 0 || $0.breakOpportunities > 0 || $0.exceptionCount > 0 }.count
    }

    public var healthyDays: Int {
        days.filter(\.isHealthyDay).count
    }

    public var breakCompletionRate: Double {
        guard totalBreakOpportunities > 0 else { return 0 }
        return Double(totalCompletedBreaks) / Double(totalBreakOpportunities)
    }

    public var quality: StatsQualitySummary {
        days.reduce(into: StatsQualitySummary()) { result, day in
            result.merge(day.quality)
        }
    }
}

public struct StatsMonthSnapshot: Equatable, Sendable {
    public let monthStart: Date
    public let previousMonthStart: Date
    public let nextMonthStart: Date
    public let days: [StatsDaySnapshot]

    public init(monthStart: Date, previousMonthStart: Date, nextMonthStart: Date, days: [StatsDaySnapshot]) {
        self.monthStart = monthStart
        self.previousMonthStart = previousMonthStart
        self.nextMonthStart = nextMonthStart
        self.days = days
    }

    public var totalWorkSeconds: Int {
        days.reduce(0) { $0 + $1.totalWorkSeconds }
    }

    public var totalBreakOpportunities: Int {
        days.reduce(0) { $0 + $1.breakOpportunities }
    }

    public var totalCompletedBreaks: Int {
        days.reduce(0) { $0 + $1.completedBreaks }
    }

    public var activeDays: Int {
        days.filter { $0.workSessions > 0 || $0.breakOpportunities > 0 || $0.exceptionCount > 0 }.count
    }

    public var healthyDays: Int {
        days.filter(\.isHealthyDay).count
    }

    public var exceptionDays: Int {
        days.filter { $0.exceptionCount > 0 }.count
    }

    public var breakCompletionRate: Double {
        guard totalBreakOpportunities > 0 else { return 0 }
        return Double(totalCompletedBreaks) / Double(totalBreakOpportunities)
    }

    public var appExitCount: Int {
        days.reduce(0) { $0 + $1.appExitCount }
    }

    public var appOffSeconds: Int {
        days.reduce(0) { $0 + $1.appOffSeconds }
    }

    public var temporaryDisableSeconds: Int {
        days.reduce(0) { $0 + $1.temporaryDisableSeconds }
    }

    public var nightOverrideSeconds: Int {
        days.reduce(0) { $0 + $1.nightOverrideSeconds }
    }

    public var longestWorkSeconds: Int {
        days.map(\.longestWorkSeconds).max() ?? 0
    }
}

public struct StatsDashboardSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let today: StatsDaySnapshot
    public let week: StatsWeekSnapshot
    public let month: StatsMonthSnapshot

    public init(generatedAt: Date, today: StatsDaySnapshot, week: StatsWeekSnapshot, month: StatsMonthSnapshot) {
        self.generatedAt = generatedAt
        self.today = today
        self.week = week
        self.month = month
    }
}

public struct StatsEngine: Sendable {
    private let calendar: Calendar
    private let now: Date
    private let minimumSessionDurationSeconds: Int
    private let staleSessionDurationSeconds: Int
    private let staleSessionGraceSeconds: Int

    public init(
        calendar: Calendar = .current,
        now: Date = Date(),
        minimumSessionDurationSeconds: Int = 60,
        staleSessionDurationSeconds: Int = 4 * 60 * 60,
        staleSessionGraceSeconds: Int = 30 * 60
    ) {
        self.calendar = calendar
        self.now = now
        self.minimumSessionDurationSeconds = minimumSessionDurationSeconds
        self.staleSessionDurationSeconds = staleSessionDurationSeconds
        self.staleSessionGraceSeconds = staleSessionGraceSeconds
    }

    public func dashboard(from records: [StatsSessionRecord], events: [StatsEventRecord] = []) -> StatsDashboardSnapshot {
        let todayStart = calendar.startOfDay(for: now)
        let weekDays = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayStart)
        }
        let days = weekDays.map { daySnapshot(for: $0, from: records, events: events) }
        let today = days.last ?? daySnapshot(for: todayStart, from: records, events: events)

        return StatsDashboardSnapshot(
            generatedAt: now,
            today: today,
            week: StatsWeekSnapshot(days: days),
            month: monthSnapshot(for: now, from: records, events: events)
        )
    }

    public func daySnapshot(for day: Date, from records: [StatsSessionRecord]) -> StatsDaySnapshot {
        daySnapshot(for: day, from: records, events: [])
    }

    public func daySnapshot(for day: Date, from records: [StatsSessionRecord], events: [StatsEventRecord]) -> StatsDaySnapshot {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return emptyDay(date: dayStart)
        }

        var quality = StatsQualitySummary()
        var workSessions = 0
        var breakOpportunities = 0
        var completedBreaks = 0
        var postponedSessions = 0
        var totalPostpones = 0
        var postponesByMinutes: [Int: Int] = [:]
        var totalWorkSeconds = 0
        var longestWorkSeconds = 0

        let dayRecords = records.filter { record in
            record.startTime >= dayStart && record.startTime < dayEnd
        }

        for record in deduplicatedRestoredWorkSessions(dayRecords) {
            collectQualitySignals(from: record, into: &quality)

            let duration = effectiveDuration(for: record)
            if shouldIgnoreShort(record: record, duration: duration) {
                quality.ignoredShortSessions += 1
                continue
            }

            if isStale(record: record, duration: duration) {
                quality.excludedStaleSessions += 1
                quality.excludedStaleSessionIDs.append(record.id)
                continue
            }

            guard duration >= minimumSessionDurationSeconds else {
                continue
            }

            workSessions += 1
            totalWorkSeconds += duration
            longestWorkSeconds = max(longestWorkSeconds, duration)

            let postponeActions = max(record.postpones.count, record.recordedPostponeCount ?? 0)
            if postponeActions > 0 || record.postponeTotalDurationSeconds > 0 {
                postponedSessions += 1
            }
            totalPostpones += postponeActions

            for postpone in record.postpones {
                let minutes = max(1, postpone.durationSeconds / 60)
                postponesByMinutes[minutes, default: 0] += 1
            }

            if isBreakOpportunity(record: record, duration: duration) {
                breakOpportunities += 1
            }

            if isCompletedBreak(record) {
                completedBreaks += 1
            }
        }

        let eventSummary = summarizeEvents(
            events,
            dayStart: dayStart,
            dayEnd: dayEnd,
            hasActiveProtectionDay: workSessions > 0 || breakOpportunities > 0
        )

        return StatsDaySnapshot(
            date: dayStart,
            workSessions: workSessions,
            breakOpportunities: breakOpportunities,
            completedBreaks: completedBreaks,
            postponedSessions: postponedSessions,
            totalPostpones: totalPostpones,
            postponesByMinutes: postponesByMinutes,
            totalWorkSeconds: totalWorkSeconds,
            longestWorkSeconds: longestWorkSeconds,
            appExitCount: eventSummary.appExitCount,
            appOffSeconds: eventSummary.appOffSeconds,
            temporaryDisableCount: eventSummary.temporaryDisableCount,
            temporaryDisableSeconds: eventSummary.temporaryDisableSeconds,
            nightOverrideCount: eventSummary.nightOverrideCount,
            nightOverrideSeconds: eventSummary.nightOverrideSeconds,
            quality: quality
        )
    }

    public func monthSnapshot(
        for monthContaining: Date,
        from records: [StatsSessionRecord],
        events: [StatsEventRecord] = []
    ) -> StatsMonthSnapshot {
        let components = calendar.dateComponents([.year, .month], from: monthContaining)
        let monthStart = calendar.date(from: components) ?? calendar.startOfDay(for: monthContaining)
        let previous = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let next = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let days = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }.map { day in
            daySnapshot(for: day, from: records, events: events)
        }

        return StatsMonthSnapshot(
            monthStart: monthStart,
            previousMonthStart: previous,
            nextMonthStart: next,
            days: days
        )
    }

    private func emptyDay(date: Date) -> StatsDaySnapshot {
        StatsDaySnapshot(
            date: date,
            workSessions: 0,
            breakOpportunities: 0,
            completedBreaks: 0,
            postponedSessions: 0,
            totalPostpones: 0,
            postponesByMinutes: [:],
            totalWorkSeconds: 0,
            longestWorkSeconds: 0,
            quality: StatsQualitySummary()
        )
    }

    private struct EventSummary {
        var appExitCount = 0
        var appOffSeconds = 0
        var temporaryDisableCount = 0
        var temporaryDisableSeconds = 0
        var nightOverrideCount = 0
        var nightOverrideSeconds = 0
    }

    private func deduplicatedRestoredWorkSessions(_ records: [StatsSessionRecord]) -> [StatsSessionRecord] {
        let duplicateStartTolerance: TimeInterval = 1.0
        let sorted = records.sorted {
            if abs($0.startTime.timeIntervalSince($1.startTime)) > duplicateStartTolerance {
                return $0.startTime < $1.startTime
            }
            return $0.id < $1.id
        }

        var result: [StatsSessionRecord] = []
        var group: [StatsSessionRecord] = []

        func appendBestFromGroup() {
            guard !group.isEmpty else { return }
            result.append(group.max(by: { duplicateRecoveryScore($0) < duplicateRecoveryScore($1) }) ?? group[0])
        }

        for record in sorted {
            guard let first = group.first else {
                group = [record]
                continue
            }

            if abs(record.startTime.timeIntervalSince(first.startTime)) <= duplicateStartTolerance {
                group.append(record)
            } else {
                appendBestFromGroup()
                group = [record]
            }
        }

        appendBestFromGroup()
        return result
    }

    private func duplicateRecoveryScore(_ record: StatsSessionRecord) -> Int {
        var score = 0
        if isCompletedBreak(record) { score += 1_000 }
        if record.breakRecord != nil { score += 500 }
        if !record.postpones.isEmpty ||
            (record.recordedPostponeCount ?? 0) > 0 ||
            record.postponeTotalDurationSeconds > 0 {
            score += 200
        }
        if record.status == .active { score += 50 }
        score += min(49, max(0, Int(record.id)))
        return score
    }

    private func summarizeEvents(
        _ events: [StatsEventRecord],
        dayStart: Date,
        dayEnd: Date,
        hasActiveProtectionDay: Bool
    ) -> EventSummary {
        var summary = EventSummary()
        let dayNightKey = formatNightKey(dayStart)

        if hasActiveProtectionDay {
            let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
            for (index, event) in sortedEvents.enumerated()
                where event.type == .appTerminated && event.timestamp >= dayStart && event.timestamp < dayEnd {
                summary.appExitCount += 1
                if let launch = sortedEvents[(index + 1)...].first(where: { $0.type == .appLaunched && $0.timestamp > event.timestamp }) {
                    summary.appOffSeconds += overlapSeconds(
                        start: event.timestamp,
                        end: launch.timestamp,
                        rangeStart: dayStart,
                        rangeEnd: dayEnd
                    )
                }
            }
        }

        for event in events where event.timestamp >= dayStart && event.timestamp < dayEnd {
            switch event.type {
            case .temporaryDisableStarted:
                summary.temporaryDisableCount += 1
                summary.temporaryDisableSeconds += durationSeconds(for: event)
            case .nightOverrideGranted where event.nightKey == nil:
                summary.nightOverrideCount += 1
                summary.nightOverrideSeconds += durationSeconds(for: event)
            case .appLaunched, .appTerminated, .temporaryDisableEnded, .temporaryDisableExpired,
                 .nightOverrideRequested, .nightOverrideGranted, .nightOverrideCancelled,
                 .nightOverrideExpired, .unknown:
                break
            }
        }

        for event in events where event.type == .nightOverrideGranted && event.nightKey == dayNightKey {
            summary.nightOverrideCount += 1
            summary.nightOverrideSeconds += durationSeconds(for: event)
        }

        return summary
    }

    private func durationSeconds(for event: StatsEventRecord) -> Int {
        if let seconds = event.durationSeconds, seconds > 0 {
            return seconds
        }
        if let endTime = event.endTime {
            return max(0, Int(endTime.timeIntervalSince(event.timestamp)))
        }
        return 0
    }

    private func overlapSeconds(start: Date, end: Date, rangeStart: Date, rangeEnd: Date) -> Int {
        let clippedStart = max(start, rangeStart)
        let clippedEnd = min(end, rangeEnd)
        return max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
    }

    private func formatNightKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func effectiveDuration(for record: StatsSessionRecord) -> Int {
        if let actual = record.actualWorkDurationSeconds, actual > 0 {
            return actual
        }
        if let endTime = record.endTime {
            return max(0, Int(endTime.timeIntervalSince(record.startTime)))
        }
        if record.status == .active {
            return max(0, Int(now.timeIntervalSince(record.startTime)))
        }
        return 0
    }

    private func shouldIgnoreShort(record: StatsSessionRecord, duration: Int) -> Bool {
        duration > 0 &&
            duration < minimumSessionDurationSeconds &&
            record.status != .active
    }

    private func isStale(record: StatsSessionRecord, duration: Int) -> Bool {
        let expectedCeiling = record.plannedDurationSeconds +
            record.postponeTotalDurationSeconds +
            staleSessionGraceSeconds
        let threshold = min(staleSessionDurationSeconds, expectedCeiling)
        return duration > threshold
    }

    private func isBreakOpportunity(record: StatsSessionRecord, duration: Int) -> Bool {
        duration >= record.plannedDurationSeconds ||
            record.breakRecord != nil ||
            !record.postpones.isEmpty ||
            (record.recordedPostponeCount ?? 0) > 0 ||
            record.postponeTotalDurationSeconds > 0
    }

    private func isCompletedBreak(_ record: StatsSessionRecord) -> Bool {
        guard record.breakCompleted else { return false }
        guard let breakRecord = record.breakRecord else { return true }
        return breakRecord.status == .completed
    }

    private func collectQualitySignals(from record: StatsSessionRecord, into quality: inout StatsQualitySummary) {
        if let breakRecord = record.breakRecord {
            switch breakRecord.status {
            case .active:
                quality.activeBreakRecords += 1
                quality.activeBreakSessionIDs.append(record.id)
            case .interrupted:
                quality.interruptedBreakRecords += 1
                quality.interruptedBreakSessionIDs.append(record.id)
            case .completed, .unknown:
                break
            }
        }

        let unclosedPostpones = record.postpones.filter { postpone in
            postpone.status == .active || postpone.endTime == nil
        }
        if !unclosedPostpones.isEmpty {
            quality.unclosedPostponeRecords += unclosedPostpones.count
            quality.unclosedPostponeSessionIDs.append(record.id)
        }
    }
}
