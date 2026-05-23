import Foundation

public struct TemporaryDisableState: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let until: Date

    public init(startedAt: Date, until: Date) {
        self.startedAt = startedAt
        self.until = until
    }
}

public struct TemporaryDisablePolicy: Sendable {
    public static let disableSeconds = 60 * 60

    public init() {}

    public func grant(now: Date) -> TemporaryDisableState {
        TemporaryDisableState(
            startedAt: now,
            until: now.addingTimeInterval(TimeInterval(Self.disableSeconds))
        )
    }

    public func isActive(_ state: TemporaryDisableState?, now: Date) -> Bool {
        guard let state else { return false }
        return now < state.until
    }

    public func remainingSeconds(_ state: TemporaryDisableState?, now: Date) -> Int {
        guard let state, isActive(state, now: now) else { return 0 }
        return max(0, Int(state.until.timeIntervalSince(now)))
    }

    public func canStart(in status: NightRestrictionStatus) -> Bool {
        !status.isLocked && !status.isOverrideActive
    }

    public func shouldInterruptActiveDisable(for status: NightRestrictionStatus) -> Bool {
        status.isLocked || status.isOverrideActive
    }
}
