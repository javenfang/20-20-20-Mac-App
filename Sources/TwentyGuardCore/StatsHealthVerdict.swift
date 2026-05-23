import Foundation

public enum StatsHealthVerdictSeverity: Equatable, Sendable {
    case good
    case warning
    case neutral
}

public struct StatsHealthVerdict: Equatable, Sendable {
    public let title: String
    public let reason: String
    public let severity: StatsHealthVerdictSeverity

    public init(title: String, reason: String, severity: StatsHealthVerdictSeverity) {
        self.title = title
        self.reason = reason
        self.severity = severity
    }
}

public struct StatsHealthVerdictEvaluator: Sendable {
    public init() {}

    public func verdict(
        for day: StatsDaySnapshot,
        localize: (String) -> String = { AppLocalization.localized($0, language: AppLocalization.defaultLanguageCode) }
    ) -> StatsHealthVerdict {
        if day.workSessions == 0 && day.totalWorkSeconds == 0 {
            return StatsHealthVerdict(
                title: localize("verdictNoDataTitle"),
                reason: localize("verdictNoDataReason"),
                severity: .neutral
            )
        }

        if day.longestWorkSeconds > 90 * 60 {
            return StatsHealthVerdict(
                title: localize("verdictLongWorkTitle"),
                reason: String(
                    format: localize("verdictLongWorkReasonFormat"),
                    formatDuration(day.longestWorkSeconds, localize: localize)
                ),
                severity: .warning
            )
        }

        if day.breakOpportunities > 0 && day.breakCompletionRate < 0.8 {
            return StatsHealthVerdict(
                title: localize("verdictLowBreakTitle"),
                reason: String(
                    format: localize("verdictLowBreakReasonFormat"),
                    formatPercent(day.breakCompletionRate)
                ),
                severity: .warning
            )
        }

        if day.breakOpportunities > 0 && day.postponeSessionRate > 0.3 {
            return StatsHealthVerdict(
                title: localize("verdictHighPostponeTitle"),
                reason: String(
                    format: localize("verdictHighPostponeReasonFormat"),
                    formatPercent(day.postponeSessionRate)
                ),
                severity: .warning
            )
        }

        if day.hasProtectionBypass {
            return StatsHealthVerdict(
                title: localize("verdictProtectionBypassedTitle"),
                reason: String(
                    format: localize("verdictProtectionBypassedReasonFormat"),
                    day.exceptionCount
                ),
                severity: .warning
            )
        }

        if day.isHealthyDay {
            return StatsHealthVerdict(
                title: localize("verdictHealthyTitle"),
                reason: localize("verdictHealthyReason"),
                severity: .good
            )
        }

        return StatsHealthVerdict(
            title: localize("verdictAttentionTitle"),
            reason: localize("verdictAttentionReason"),
            severity: .neutral
        )
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatDuration(_ seconds: Int, localize: (String) -> String) -> String {
        guard seconds > 0 else { return localize("statsZeroMinutes") }
        let minutes = max(1, seconds / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 && remainingMinutes > 0 {
            return String(format: localize("statsHoursMinutesFormat"), hours, remainingMinutes)
        }
        if hours > 0 {
            return String(format: localize("statsHoursFormat"), hours)
        }
        return String(format: localize("statsMinutesFormat"), minutes)
    }
}
