import Foundation

public struct SessionState: Codable, Equatable, Sendable {
    public let workStartTime: Date?
    public let breakStartTime: Date?
    public let postponeStartTime: Date?
    public let postponeDuration: TimeInterval
    public let totalPostponedTime: TimeInterval
    public let currentWorkDuration: Int
    public let currentBreakDuration: Int
    public let isCustomMode: Bool
    public let lastSaved: Date
    public let pausedBySystemEvent: Bool

    public init(
        workStartTime: Date?,
        breakStartTime: Date?,
        postponeStartTime: Date? = nil,
        postponeDuration: TimeInterval = 0,
        totalPostponedTime: TimeInterval = 0,
        currentWorkDuration: Int,
        currentBreakDuration: Int,
        isCustomMode: Bool,
        lastSaved: Date,
        pausedBySystemEvent: Bool
    ) {
        self.workStartTime = workStartTime
        self.breakStartTime = breakStartTime
        self.postponeStartTime = postponeStartTime
        self.postponeDuration = max(0, postponeDuration)
        self.totalPostponedTime = max(0, totalPostponedTime)
        self.currentWorkDuration = currentWorkDuration
        self.currentBreakDuration = currentBreakDuration
        self.isCustomMode = isCustomMode
        self.lastSaved = lastSaved
        self.pausedBySystemEvent = pausedBySystemEvent
    }

    public func isValid(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSaved) < 30 * 60
    }

    public func shouldRestoreAfterSystemEvent(now: Date = Date()) -> Bool {
        !pausedBySystemEvent && now.timeIntervalSince(lastSaved) < 10 * 60
    }

    public func postponeRemaining(now: Date) -> TimeInterval {
        guard let postponeStartTime, postponeDuration > 0 else { return 0 }
        return max(0, postponeDuration - now.timeIntervalSince(postponeStartTime))
    }

    public func completedBreak(now: Date) -> SessionState {
        SessionState(
            workStartTime: now,
            breakStartTime: nil,
            postponeStartTime: nil,
            postponeDuration: 0,
            totalPostponedTime: 0,
            currentWorkDuration: currentWorkDuration,
            currentBreakDuration: currentBreakDuration,
            isCustomMode: isCustomMode,
            lastSaved: now,
            pausedBySystemEvent: false
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.workStartTime = try container.decodeIfPresent(Date.self, forKey: .workStartTime)
        self.breakStartTime = try container.decodeIfPresent(Date.self, forKey: .breakStartTime)
        self.postponeStartTime = try container.decodeIfPresent(Date.self, forKey: .postponeStartTime)
        self.postponeDuration = max(0, try container.decodeIfPresent(TimeInterval.self, forKey: .postponeDuration) ?? 0)
        self.totalPostponedTime = max(0, try container.decodeIfPresent(TimeInterval.self, forKey: .totalPostponedTime) ?? 0)
        self.currentWorkDuration = try container.decode(Int.self, forKey: .currentWorkDuration)
        self.currentBreakDuration = try container.decode(Int.self, forKey: .currentBreakDuration)
        self.isCustomMode = try container.decode(Bool.self, forKey: .isCustomMode)
        self.lastSaved = try container.decode(Date.self, forKey: .lastSaved)
        self.pausedBySystemEvent = try container.decodeIfPresent(Bool.self, forKey: .pausedBySystemEvent) ?? false
    }
}

public enum SessionRecoveryDecision: Equatable, Sendable {
    case noPostpone
    case continuePostpone(startTime: Date, duration: TimeInterval, totalPostponedTime: TimeInterval)
    case startBreakAfterExpiredPostpone(totalPostponedTime: TimeInterval)
}

public struct SessionRecoveryPolicy: Sendable {
    public init() {}

    public func decision(for state: SessionState, now: Date) -> SessionRecoveryDecision {
        guard let postponeStartTime = state.postponeStartTime, state.postponeDuration > 0 else {
            return .noPostpone
        }

        if state.postponeRemaining(now: now) > 0 {
            return .continuePostpone(
                startTime: postponeStartTime,
                duration: state.postponeDuration,
                totalPostponedTime: state.totalPostponedTime
            )
        }

        return .startBreakAfterExpiredPostpone(totalPostponedTime: state.totalPostponedTime)
    }
}
