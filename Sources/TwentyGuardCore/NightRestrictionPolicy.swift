import Foundation

public struct ClockTime: Codable, Equatable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        precondition((0..<24).contains(hour), "hour must be in 0..<24")
        precondition((0..<60).contains(minute), "minute must be in 0..<60")
        self.hour = hour
        self.minute = minute
    }

    public init(minutesAfterMidnight: Int) {
        let normalized = ((minutesAfterMidnight % 1440) + 1440) % 1440
        self.hour = normalized / 60
        self.minute = normalized % 60
    }

    public var minutesAfterMidnight: Int {
        hour * 60 + minute
    }

    public var displayString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesAfterMidnight < rhs.minutesAfterMidnight
    }
}

public struct NightRestrictionSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var windDownStart: ClockTime
    public var lockStart: ClockTime
    public var unlockTime: ClockTime

    public init(
        isEnabled: Bool = false,
        windDownStart: ClockTime = ClockTime(hour: 20, minute: 0),
        lockStart: ClockTime = ClockTime(hour: 21, minute: 0),
        unlockTime: ClockTime = ClockTime(hour: 7, minute: 0)
    ) {
        self.isEnabled = isEnabled
        self.windDownStart = windDownStart
        self.lockStart = lockStart
        self.unlockTime = unlockTime
    }
}

public struct NightRestrictionSchedule: Equatable, Sendable {
    public let windDownStart: Date
    public let lockStart: Date
    public let unlockTime: Date
    public let windDownStartTime: ClockTime
    public let lockStartTime: ClockTime
    public let unlockClockTime: ClockTime

    public init(
        windDownStart: Date,
        lockStart: Date,
        unlockTime: Date,
        windDownStartTime: ClockTime,
        lockStartTime: ClockTime,
        unlockClockTime: ClockTime
    ) {
        self.windDownStart = windDownStart
        self.lockStart = lockStart
        self.unlockTime = unlockTime
        self.windDownStartTime = windDownStartTime
        self.lockStartTime = lockStartTime
        self.unlockClockTime = unlockClockTime
    }
}

public enum NightRestrictionPhase: Equatable, Sendable {
    case normal
    case windDown(limitSeconds: Int, stageIndex: Int, stageCount: Int, lockStart: Date, unlockTime: Date)
    case locked(unlockTime: Date)
}

public struct NightRestrictionStatus: Equatable, Sendable {
    public let phase: NightRestrictionPhase
    public let effectiveWorkDurationSeconds: Int
    public let schedule: NightRestrictionSchedule
    public let isOverrideActive: Bool

    public init(
        phase: NightRestrictionPhase,
        effectiveWorkDurationSeconds: Int,
        schedule: NightRestrictionSchedule,
        isOverrideActive: Bool
    ) {
        self.phase = phase
        self.effectiveWorkDurationSeconds = effectiveWorkDurationSeconds
        self.schedule = schedule
        self.isOverrideActive = isOverrideActive
    }

    public var isLocked: Bool {
        if case .locked = phase { return true }
        return false
    }

    public var isWindDown: Bool {
        if case .windDown = phase { return true }
        return false
    }
}

public struct NightRestrictionPolicy: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func status(
        now: Date,
        baseWorkDurationSeconds: Int,
        settings: NightRestrictionSettings,
        overrideUntil: Date? = nil
    ) -> NightRestrictionStatus {
        let baseDuration = max(60, baseWorkDurationSeconds)
        let schedule = relevantSchedule(now: now, settings: settings)
        let isOverrideActive = overrideUntil.map { now < $0 } ?? false

        guard settings.isEnabled, !isOverrideActive else {
            return NightRestrictionStatus(
                phase: .normal,
                effectiveWorkDurationSeconds: baseDuration,
                schedule: schedule,
                isOverrideActive: isOverrideActive
            )
        }

        if now >= schedule.lockStart && now < schedule.unlockTime {
            return NightRestrictionStatus(
                phase: .locked(unlockTime: schedule.unlockTime),
                effectiveWorkDurationSeconds: 0,
                schedule: schedule,
                isOverrideActive: false
            )
        }

        if now >= schedule.windDownStart && now < schedule.lockStart {
            let limits = Self.windDownLimits(baseWorkDurationSeconds: baseDuration)
            let duration = max(1, schedule.lockStart.timeIntervalSince(schedule.windDownStart))
            let stageDuration = duration / Double(limits.count)
            let elapsed = max(0, now.timeIntervalSince(schedule.windDownStart))
            let stageIndex = min(limits.count - 1, max(0, Int(elapsed / stageDuration)))
            let limit = limits[stageIndex]

            return NightRestrictionStatus(
                phase: .windDown(
                    limitSeconds: limit,
                    stageIndex: stageIndex,
                    stageCount: limits.count,
                    lockStart: schedule.lockStart,
                    unlockTime: schedule.unlockTime
                ),
                effectiveWorkDurationSeconds: limit,
                schedule: schedule,
                isOverrideActive: false
            )
        }

        return NightRestrictionStatus(
            phase: .normal,
            effectiveWorkDurationSeconds: baseDuration,
            schedule: schedule,
            isOverrideActive: false
        )
    }

    public static func windDownLimits(baseWorkDurationSeconds: Int) -> [Int] {
        [0.75, 0.50, 0.25].map { ratio in
            let scaled = Int(Double(baseWorkDurationSeconds) * ratio)
            return max(5 * 60, (scaled / (5 * 60)) * (5 * 60))
        }
    }

    private func relevantSchedule(now: Date, settings: NightRestrictionSettings) -> NightRestrictionSchedule {
        let today = calendar.startOfDay(for: now)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let previousSchedule = schedule(anchorDay: previousDay, settings: settings)

        if now >= previousSchedule.windDownStart && now < previousSchedule.unlockTime {
            return previousSchedule
        }

        return schedule(anchorDay: today, settings: settings)
    }

    private func schedule(anchorDay: Date, settings: NightRestrictionSettings) -> NightRestrictionSchedule {
        let windDownStart = date(on: anchorDay, at: settings.windDownStart)
        var lockStart = date(on: anchorDay, at: settings.lockStart)
        var unlockTime = date(on: anchorDay, at: settings.unlockTime)

        while lockStart <= windDownStart {
            lockStart = calendar.date(byAdding: .day, value: 1, to: lockStart) ?? lockStart.addingTimeInterval(24 * 60 * 60)
        }

        while unlockTime <= lockStart {
            unlockTime = calendar.date(byAdding: .day, value: 1, to: unlockTime) ?? unlockTime.addingTimeInterval(24 * 60 * 60)
        }

        return NightRestrictionSchedule(
            windDownStart: windDownStart,
            lockStart: lockStart,
            unlockTime: unlockTime,
            windDownStartTime: settings.windDownStart,
            lockStartTime: settings.lockStart,
            unlockClockTime: settings.unlockTime
        )
    }

    private func date(on anchorDay: Date, at time: ClockTime) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: anchorDay)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? anchorDay
    }
}
