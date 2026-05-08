import Foundation

public enum NightOverrideReason: String, Codable, CaseIterable, Equatable, Sendable {
    case urgentWork = "urgent_work"
    case lifeTask = "life_task"
    case family = "family"
    case other = "other"
}

public struct NightOverrideRequest: Equatable, Sendable {
    public let overrideNumberForNight: Int
    public let waitSeconds: Int
    public let unlockSeconds: Int
    public let confirmationLocalizationKey: String

    public init(
        overrideNumberForNight: Int,
        waitSeconds: Int,
        unlockSeconds: Int,
        confirmationLocalizationKey: String
    ) {
        self.overrideNumberForNight = overrideNumberForNight
        self.waitSeconds = waitSeconds
        self.unlockSeconds = unlockSeconds
        self.confirmationLocalizationKey = confirmationLocalizationKey
    }
}

public struct NightOverrideState: Codable, Equatable, Sendable {
    public let grantedAt: Date
    public let until: Date
    public let reason: NightOverrideReason
    public let nightKey: String
    public let overrideNumberForNight: Int

    public init(
        grantedAt: Date,
        until: Date,
        reason: NightOverrideReason,
        nightKey: String,
        overrideNumberForNight: Int
    ) {
        self.grantedAt = grantedAt
        self.until = until
        self.reason = reason
        self.nightKey = nightKey
        self.overrideNumberForNight = overrideNumberForNight
    }
}

public struct NightOverridePolicy: Sendable {
    public static let unlockSeconds = 30 * 60

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func request(overrideNumberForNight: Int) -> NightOverrideRequest {
        let normalizedCount = max(1, overrideNumberForNight)

        switch normalizedCount {
        case 1:
            return NightOverrideRequest(
                overrideNumberForNight: normalizedCount,
                waitSeconds: 60,
                unlockSeconds: Self.unlockSeconds,
                confirmationLocalizationKey: "nightOverrideConfirmationFirst"
            )
        case 2:
            return NightOverrideRequest(
                overrideNumberForNight: normalizedCount,
                waitSeconds: 90,
                unlockSeconds: Self.unlockSeconds,
                confirmationLocalizationKey: "nightOverrideConfirmationSecond"
            )
        default:
            return NightOverrideRequest(
                overrideNumberForNight: normalizedCount,
                waitSeconds: 120,
                unlockSeconds: Self.unlockSeconds,
                confirmationLocalizationKey: "nightOverrideConfirmationRepeated"
            )
        }
    }

    public func grant(
        now: Date,
        reason: NightOverrideReason,
        nightKey: String,
        overrideNumberForNight: Int
    ) -> NightOverrideState {
        NightOverrideState(
            grantedAt: now,
            until: now.addingTimeInterval(TimeInterval(Self.unlockSeconds)),
            reason: reason,
            nightKey: nightKey,
            overrideNumberForNight: max(1, overrideNumberForNight)
        )
    }

    public func isActive(_ state: NightOverrideState?, now: Date) -> Bool {
        guard let state else { return false }
        return now < state.until
    }

    public func nightKey(for schedule: NightRestrictionSchedule) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: schedule.windDownStart)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
