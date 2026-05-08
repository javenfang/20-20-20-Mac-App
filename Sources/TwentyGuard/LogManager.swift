import Foundation
import TwentyGuardCore

// MARK: - Log Data Models

struct LogEvent: Codable {
    let timestamp: Date
    let eventType: EventType
    let duration: TimeInterval?
    let context: [String: String]?
    
    enum EventType: String, Codable, CaseIterable {
        // Work/Break cycle events
        case workStarted = "work_started"
        case workPaused = "work_paused"
        case workCompleted = "work_completed"
        case breakStarted = "break_started"
        case breakCompleted = "break_completed"
        case breakPostponed = "break_postponed"
        case breakSkipped = "break_skipped"
        
        // System events
        case systemSleep = "system_sleep"
        case systemWake = "system_wake"
        case screenLock = "screen_lock"
        case screenUnlock = "screen_unlock"
        case screensaverStart = "screensaver_start"
        case screensaverStop = "screensaver_stop"
        case displaySleep = "display_sleep"
        case displayWake = "display_wake"
        
        // App events
        case appLaunched = "app_launched"
        case appTerminated = "app_terminated"
        case settingsChanged = "settings_changed"
        case modeChanged = "mode_changed"
        case timerReset = "timer_reset"
        case stateSnapshot = "state_snapshot"
        case nightOverrideRequested = "night_override_requested"
        case nightOverrideGranted = "night_override_granted"
        case nightOverrideCancelled = "night_override_cancelled"
        case nightOverrideExpired = "night_override_expired"
    }
}

struct NightOverrideSummary: Equatable {
    let count: Int
    let totalMinutes: Int
}

struct SessionState: Codable {
    let workStartTime: Date?
    let breakStartTime: Date?
    let currentWorkDuration: Int
    let currentBreakDuration: Int
    let isCustomMode: Bool
    let lastSaved: Date
    let pausedBySystemEvent: Bool  // 新增：是否由于系统事件被暂停
    
    func isValid() -> Bool {
        // 会话有效期：30分钟内
        return Date().timeIntervalSince(lastSaved) < 30 * 60
    }
    
    func shouldRestoreAfterSystemEvent() -> Bool {
        // 如果是由于系统事件暂停的，并且时间不超过2小时，可以考虑恢复
        // 但屏保/睡眠本身相当于休息，所以通常应该开始新会话
        return !pausedBySystemEvent && Date().timeIntervalSince(lastSaved) < 10 * 60
    }
}

// MARK: - Log Manager

class LogManager {
    static let shared = LogManager()
    
    private let logQueue = DispatchQueue(label: "com.javengroup.twentyguard.logmanager", qos: .utility)
    private let fileManager = FileManager.default
    
    // 存储路径
    private let appSupportURL: URL
    private let logsDirectoryURL: URL
    private let sessionStateURL: URL
    
    
    private init() {
        let paths = AppDataPaths.live(fileManager: fileManager)
        self.appSupportURL = paths.appSupportURL
        self.logsDirectoryURL = paths.logsDirectoryURL
        self.sessionStateURL = paths.sessionStateURL
        
        // 创建目录
        createDirectoriesIfNeeded()
        
        // 启动时记录
        logEvent(.appLaunched)
    }
    
    // MARK: - Public Methods
    
    /// 记录事件
    func logEvent(_ eventType: LogEvent.EventType, duration: TimeInterval? = nil, context: [String: String]? = nil) {
        let event = LogEvent(
            timestamp: Date(),
            eventType: eventType,
            duration: duration,
            context: context
        )
        
        logQueue.async { [weak self] in
            self?.writeLogEvent(event)
        }
        
        // 控制台输出（调试用）
        let durationStr = duration != nil ? String(format: " (%.1fs)", duration!) : ""
        let contextStr = context?.isEmpty == false ? " \(context!)" : ""
        print("📊 \(eventType.rawValue)\(durationStr)\(contextStr)")
    }
    
    /// 保存当前会话状态
    func saveSessionState(
        workStartTime: Date?,
        breakStartTime: Date?,
        currentWorkDuration: Int,
        currentBreakDuration: Int,
        isCustomMode: Bool,
        pausedBySystemEvent: Bool = false
    ) {
        let state = SessionState(
            workStartTime: workStartTime,
            breakStartTime: breakStartTime,
            currentWorkDuration: currentWorkDuration,
            currentBreakDuration: currentBreakDuration,
            isCustomMode: isCustomMode,
            lastSaved: Date(),
            pausedBySystemEvent: pausedBySystemEvent
        )
        
        logQueue.async { [weak self] in
            self?.writeSessionState(state)
        }
    }
    
    /// 恢复会话状态
    func restoreSessionState() -> SessionState? {
        guard let data = try? Data(contentsOf: sessionStateURL) else {
            logEvent(.appLaunched, context: ["restore_error": "file_not_exists", "path": sessionStateURL.path])
            return nil
        }
        
        let decoder = JSONDecoder()
        // Use same formatter as encoding to maintain consistency
        decoder.dateDecodingStrategy = .formatted(makeLogDateFormatter())
        
        do {
            let state = try decoder.decode(SessionState.self, from: data)
            logEvent(.appLaunched, context: ["restore_debug": "decode_success", "lastSaved": state.lastSaved.description])
            
            guard state.isValid() else {
                let timeSinceLastSave = Date().timeIntervalSince(state.lastSaved)
                logEvent(.appLaunched, context: ["restore_error": "session_expired", "seconds_since_save": String(Int(timeSinceLastSave))])
                return nil
            }
            
            logEvent(.appLaunched, context: ["restore_success": "true", "workStartTime": state.workStartTime?.description ?? "nil"])
            return state
            
        } catch {
            logEvent(.appLaunched, context: ["restore_error": "decode_failed", "error": error.localizedDescription])
            return nil
        }
    }
    
    /// 清理会话状态
    func clearSessionState() {
        try? fileManager.removeItem(at: sessionStateURL)
    }
    
    /// 获取今天的日志文件路径
    func getTodayLogFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayString = formatter.string(from: Date())
        return logsDirectoryURL.appendingPathComponent("\(todayString).jsonl")
    }
    
    /// 清理旧日志（保留指定天数）
    func cleanupOldLogs(keepDays: Int = 30) {
        logQueue.async { [weak self] in
            self?.performLogCleanup(keepDays: keepDays)
        }
    }
    
    /// 导出日志（调试用）
    func exportRecentLogs(days: Int = 7) -> [String] {
        var logs: [String] = []
        let calendar = Calendar.current
        
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                let dateString = formatter.string(from: date)
                let fileURL = logsDirectoryURL.appendingPathComponent("\(dateString).jsonl")
                
                if let content = try? String(contentsOf: fileURL) {
                    logs.append("=== \(dateString) ===")
                    logs.append(content)
                }
            }
        }
        
        return logs
    }

    func nightOverrideSummary(nightKey: String, days: Int = 7) -> NightOverrideSummary {
        var count = 0
        var totalMinutes = 0

        for event in loadRecentEvents(days: days) where event.eventType == .nightOverrideGranted {
            guard event.context?["night_key"] == nightKey else { continue }
            count += 1
            if let unlockMinutes = event.context?["unlock_minutes"].flatMap(Int.init) {
                totalMinutes += unlockMinutes
            } else if let duration = event.duration {
                totalMinutes += max(1, Int(duration / 60))
            }
        }

        return NightOverrideSummary(count: count, totalMinutes: totalMinutes)
    }
    
    // MARK: - Private Methods
    
    private func createDirectoriesIfNeeded() {
        do {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create directories: \(error)")
        }
    }
    
    private func writeLogEvent(_ event: LogEvent) {
        do {
            let encoder = JSONEncoder()
            // Use local timezone instead of UTC
            let formatter = makeLogDateFormatter()
            encoder.dateEncodingStrategy = .formatted(formatter)
            let data = try encoder.encode(event)
            
            if let jsonString = String(data: data, encoding: .utf8) {
                let logLine = jsonString + "\n"
                let fileURL = getLogFileURL(for: event.timestamp)
                
                if fileManager.fileExists(atPath: fileURL.path) {
                    // 追加到现有文件
                    let fileHandle = try FileHandle(forWritingTo: fileURL)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logLine.data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    // 创建新文件
                    try logLine.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("❌ Failed to write log event: \(error)")
        }
    }
    
    private func writeSessionState(_ state: SessionState) {
        do {
            let encoder = JSONEncoder()
            // Use local timezone instead of UTC
            let formatter = makeLogDateFormatter()
            encoder.dateEncodingStrategy = .formatted(formatter)
            let data = try encoder.encode(state)
            try data.write(to: sessionStateURL)
        } catch {
            print("❌ Failed to save session state: \(error)")
        }
    }
    
    private func getLogFileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: date)
        return logsDirectoryURL.appendingPathComponent("\(dateString).jsonl")
    }

    private func loadRecentEvents(days: Int) -> [LogEvent] {
        var events: [LogEvent] = []
        let calendar = Calendar.current
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(makeLogDateFormatter())

        for offset in 0..<max(1, days) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let fileURL = getLogFileURL(for: date)
            guard let content = try? String(contentsOf: fileURL) else { continue }

            for line in content.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let event = try? decoder.decode(LogEvent.self, from: data) else {
                    continue
                }
                events.append(event)
            }
        }

        return events
    }

    private func makeLogDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone.current
        return formatter
    }
    
    private func performLogCleanup(keepDays: Int) {
        do {
            let calendar = Calendar.current
            let cutoffDate = calendar.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
            let contents = try fileManager.contentsOfDirectory(at: logsDirectoryURL, includingPropertiesForKeys: [.creationDateKey])
            
            for fileURL in contents {
                if fileURL.pathExtension == "jsonl" {
                    let creationDate = try fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    if creationDate < cutoffDate {
                        try fileManager.removeItem(at: fileURL)
                        print("🗑️ Cleaned up old log: \(fileURL.lastPathComponent)")
                    }
                }
            }
        } catch {
            print("❌ Failed to cleanup old logs: \(error)")
        }
    }
}

// MARK: - Convenience Logging Methods

extension LogManager {
    func logWorkStarted(mode: String) {
        logEvent(.workStarted, context: ["mode": mode])
    }
    
    func logWorkPaused(duration: TimeInterval, reason: String) {
        logEvent(.workPaused, duration: duration, context: ["reason": reason])
    }
    
    func logWorkCompleted(duration: TimeInterval) {
        logEvent(.workCompleted, duration: duration)
    }
    
    func logBreakStarted(expectedDuration: Int) {
        logEvent(.breakStarted, context: ["expected_duration": "\(expectedDuration)"])
    }
    
    func logBreakCompleted(actualDuration: TimeInterval, expectedDuration: Int) {
        let context: [String: String] = [
            "expected_duration": "\(expectedDuration)",
            "actual_duration": String(format: "%.1f", actualDuration)
        ]
        logEvent(.breakCompleted, duration: actualDuration, context: context)
    }
    
    func logBreakPostponed(partialDuration: TimeInterval, postponeMinutes: Int) {
        let context: [String: String] = [
            "postpone_minutes": "\(postponeMinutes)",
            "partial_duration": String(format: "%.1f", partialDuration)
        ]
        logEvent(.breakPostponed, duration: partialDuration, context: context)
    }
    
    func logSettingsChanged(changes: [String: String]) {
        logEvent(.settingsChanged, context: changes)
    }
    
    func logTimerReset(reason: String) {
        logEvent(.timerReset, context: ["reason": reason])
    }
    
    func logStateSnapshot(
        workStartTime: Date?,
        breakStartTime: Date?,
        workRemaining: TimeInterval,
        breakRemaining: TimeInterval,
        currentMode: String
    ) {
        var context: [String: String] = [
            "mode": currentMode,
            "work_remaining": String(format: "%.1f", workRemaining),
            "break_remaining": String(format: "%.1f", breakRemaining)
        ]
        
        if let workStart = workStartTime {
            let workElapsed = Date().timeIntervalSince(workStart)
            context["work_elapsed"] = String(format: "%.1f", workElapsed)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            formatter.timeZone = TimeZone.current
            context["work_started_at"] = formatter.string(from: workStart)
        }
        
        if let breakStart = breakStartTime {
            let breakElapsed = Date().timeIntervalSince(breakStart)
            context["break_elapsed"] = String(format: "%.1f", breakElapsed)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            formatter.timeZone = TimeZone.current
            context["break_started_at"] = formatter.string(from: breakStart)
        }
        
        logEvent(.stateSnapshot, context: context)
    }
}
