import Foundation
import TwentyGuardCore

// MARK: - EventRecorder

/// Simplified event recording system that writes to both SQLite and optional JSON logs
class EventRecorder {
    static let shared = EventRecorder()

    private let statsDB = StatsDatabase.shared
    private let logManager = LogManager.shared  // Keep existing JSON logger for debugging

    // Current session tracking
    private var currentWorkSessionId: Int64?
    private var currentBreakSessionId: Int64?
    private var currentWorkDuration: Int = 20 * 60  // Default 20 minutes
    private var currentBreakDuration: Int = 20  // Default 20 seconds

    private init() {}

    // MARK: - Work Session Management

    func startWorkSession(duration: Int, startTime: Date? = nil) {
        currentWorkDuration = duration

        // Record in database with optional start time (for session restoration)
        currentWorkSessionId = statsDB.startWorkSession(plannedDuration: duration, startTime: startTime)
        currentBreakSessionId = nil

        // Optional: Keep JSON log for debugging
        logManager.logWorkStarted(mode: duration == 20 * 60 ? "default" : "custom")

        if let startTime = startTime {
            print("📊 EventRecorder: Resumed work session with duration \(duration)s, started at \(startTime)")
        } else {
            print("📊 EventRecorder: Started work session with duration \(duration)s")
        }
    }

    func endWorkSession() {
        if currentWorkSessionId != nil {
            statsDB.endActiveSession()

            // Log work completion
            logManager.logWorkCompleted(duration: TimeInterval(currentWorkDuration))

            currentWorkSessionId = nil
            print("📊 EventRecorder: Ended work session")
        }
    }

    // MARK: - Break Session Management

    func startBreakSession(duration: Int) {
        currentBreakDuration = duration

        // Start break in database (v1.2.0 - updates work session's break_info)
        statsDB.startBreak(plannedDuration: duration)

        // Optional: Keep JSON log
        logManager.logBreakStarted(expectedDuration: duration)

        print("📊 EventRecorder: Started break with duration \(duration)s")
    }

    func endBreakSession() {
        // Complete break in database (v1.2.0 - updates work session)
        statsDB.completeBreak()

        // Log break completion
        logManager.logBreakCompleted(actualDuration: TimeInterval(currentBreakDuration), expectedDuration: currentBreakDuration)

        currentBreakSessionId = nil
        print("📊 EventRecorder: Completed break")
    }

    // MARK: - Postpone Management

    func recordPostpone(minutes: Int) {
        // Record in database
        statsDB.recordPostpone(minutes: minutes)

        // Optional: Keep JSON log (pass 0 for partial duration since we track in DB now)
        logManager.logBreakPostponed(partialDuration: 0, postponeMinutes: minutes)

        print("📊 EventRecorder: Recorded \(minutes) minute postpone")
    }

    // MARK: - System Events

    func recordSystemSleep() {
        // End any active sessions
        statsDB.endActiveSession()

        // Log system event
        logManager.logEvent(.systemSleep)

        print("📊 EventRecorder: System sleep detected")
    }

    func recordSystemWake() {
        // Log system event
        logManager.logEvent(.systemWake)

        print("📊 EventRecorder: System wake detected")
    }

    func recordScreensaverStart() {
        // End any active sessions (screensaver counts as break)
        statsDB.endActiveSession()

        // Log event
        logManager.logEvent(.screensaverStart)

        print("📊 EventRecorder: Screensaver started")
    }

    func recordScreensaverStop() {
        // Log event
        logManager.logEvent(.screensaverStop)

        print("📊 EventRecorder: Screensaver stopped")
    }

    // MARK: - App Lifecycle

    func recordAppLaunch() {
        // Log app launch
        logManager.logEvent(.appLaunched)

        // Clean old data periodically (keep 90 days)
        statsDB.cleanOldData(keepDays: 90)

        print("📊 EventRecorder: App launched")
    }

    func recordAppTermination() {
        // End any active sessions
        statsDB.endActiveSession()

        // Log termination
        logManager.logEvent(.appTerminated)

        print("📊 EventRecorder: App terminated")
    }

    // MARK: - Settings Changes

    func recordModeChange(mode: String, workDuration: Int, breakDuration: Int) {
        currentWorkDuration = workDuration
        currentBreakDuration = breakDuration

        // Log mode change
        logManager.logEvent(.modeChanged, context: [
            "new_mode": mode,
            "work_duration": "\(workDuration)",
            "break_duration": "\(breakDuration)"
        ])

        print("📊 EventRecorder: Mode changed to \(mode)")
    }

    func recordSettingsChange(changes: [String: String]) {
        // Log settings change
        logManager.logSettingsChanged(changes: changes)

        print("📊 EventRecorder: Settings changed")
    }

    // MARK: - Night Override

    func recordNightOverrideRequested(nightKey: String, request: NightOverrideRequest) {
        logManager.logEvent(.nightOverrideRequested, context: nightOverrideContext(
            nightKey: nightKey,
            request: request
        ))
    }

    func recordNightOverrideGranted(state: NightOverrideState, request: NightOverrideRequest) {
        var context = nightOverrideContext(nightKey: state.nightKey, request: request)
        context["reason"] = state.reason.rawValue
        context["granted_at"] = formattedLogDate(state.grantedAt)
        context["override_until"] = formattedLogDate(state.until)
        logManager.logEvent(
            .nightOverrideGranted,
            duration: TimeInterval(request.unlockSeconds),
            context: context
        )
    }

    func recordNightOverrideCancelled(nightKey: String, request: NightOverrideRequest) {
        logManager.logEvent(.nightOverrideCancelled, context: nightOverrideContext(
            nightKey: nightKey,
            request: request
        ))
    }

    func recordNightOverrideExpired(state: NightOverrideState) {
        let request = NightOverrideRequest(
            overrideNumberForNight: state.overrideNumberForNight,
            waitSeconds: 0,
            unlockSeconds: NightOverridePolicy.unlockSeconds,
            confirmationLocalizationKey: ""
        )
        var context = nightOverrideContext(nightKey: state.nightKey, request: request)
        context["reason"] = state.reason.rawValue
        context["granted_at"] = formattedLogDate(state.grantedAt)
        context["override_until"] = formattedLogDate(state.until)
        logManager.logEvent(.nightOverrideExpired, context: context)
    }

    private func nightOverrideContext(nightKey: String, request: NightOverrideRequest) -> [String: String] {
        [
            "night_key": nightKey,
            "override_number": "\(request.overrideNumberForNight)",
            "wait_seconds": "\(request.waitSeconds)",
            "unlock_minutes": "\(request.unlockSeconds / 60)"
        ]
    }

    private func formattedLogDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - Timer Reset

    func recordTimerReset(reason: String) {
        // End any active sessions
        statsDB.endActiveSession()

        // Log timer reset
        logManager.logTimerReset(reason: reason)

        print("📊 EventRecorder: Timer reset - \(reason)")
    }

    // MARK: - Session State

    func saveSessionState(workStartTime: Date?, breakStartTime: Date?, isCustomMode: Bool, pausedBySystemEvent: Bool = false) {
        // Save session state for recovery
        logManager.saveSessionState(
            workStartTime: workStartTime,
            breakStartTime: breakStartTime,
            currentWorkDuration: currentWorkDuration,
            currentBreakDuration: currentBreakDuration,
            isCustomMode: isCustomMode,
            pausedBySystemEvent: pausedBySystemEvent
        )
    }

    func restoreSessionState() -> SessionState? {
        return logManager.restoreSessionState()
    }

    func clearSessionState() {
        logManager.clearSessionState()
    }

    // MARK: - Statistics Access

    func getTodayStats() -> DailyStats? {
        let stats = statsDB.getTodayStats()
        if stats == nil {
            print("⚠️ EventRecorder: getTodayStats returned nil")
        } else {
            print("✅ EventRecorder: getTodayStats returned data")
        }
        return stats
    }

    func getWeeklyStats() -> [(Date, DailyStats)] {
        return statsDB.getWeeklyStats()
    }

    // MARK: - Maintenance

    func updateDailySummary() {
        statsDB.updateDailySummary()
        print("📊 EventRecorder: Updated daily summary")
    }

    func cleanupOldData() {
        statsDB.cleanOldData(keepDays: 90)
        logManager.cleanupOldLogs(keepDays: 30)
        print("📊 EventRecorder: Cleaned up old data")
    }
}
