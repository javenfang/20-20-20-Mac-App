import Cocoa
import ServiceManagement
import TwentyGuardCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private enum AppIdentity {
        static let displayName = "TwentyGuard"
        static let bundleIdentifier = "com.javengroup.twentyguard"
    }

    private enum NightOverrideDefaults {
        static let grantedAt = "nightOverrideGrantedAt"
        static let until = "nightOverrideUntil"
        static let reason = "nightOverrideReason"
        static let nightKey = "nightOverrideNightKey"
        static let numberForNight = "nightOverrideNumberForNight"
        static let countNightKey = "nightOverrideCountNightKey"
        static let countForNight = "nightOverrideCountForNight"
        static let legacyOverrideUntil = "nightLockOverrideUntil"
        static let legacyTestingExit = "nightTestingExitEnabled"
    }

    private var statusBarItem: NSStatusItem!
    private var menu: NSMenu!
    private var workTimer: Timer?
    private var breakTimer: Timer?
    private var nightLockTimer: Timer?
    private var menuUpdateTimer: Timer?
    private var stateSnapshotTimer: Timer?
    
    // 绝对时间记录
    private var workSessionStartTime: Date?
    private var breakSessionStartTime: Date?
    
    // 推迟状态跟踪
    private var postponeStartTime: Date?
    private var postponeDuration: TimeInterval = 0
    private var totalPostponedTime: TimeInterval = 0  // 累计推迟时间（秒）
    private var maxTotalPostponeTime: TimeInterval = 5 * 60  // 默认最多推迟5分钟
    
    private var timerMenuItem: NSMenuItem!
    private var breakOverlays: [BreakOverlayWindow] = []
    private var nightLockOverlays: [NightRestrictionOverlayWindow] = []
    private var loginItemMenuItem: NSMenuItem!
    private var nightRestrictionMenuItem: NSMenuItem!
    private var healthStatsWindow: StatsDashboardWindow?
    
    // 事件记录器（新的统一系统）
    private let eventRecorder = EventRecorder.shared
    // 保留日志管理器用于会话恢复
    private let logManager = LogManager.shared
    
    // Mode settings
    private var currentWorkDuration: Int = 20 * 60 // Default 20 minutes
    private var currentBreakDuration: Int = 20 // Default 20 seconds
    private var isCustomMode: Bool = false
    private var customWorkDuration: Int = 30 * 60 // Default custom: 30 minutes
    private var customBreakDuration: Int = 30 // Default custom: 30 seconds
    private var customPostponeLimitMinutes: Int = 5 // Default custom postpone limit
    private var modeMenuItems: [NSMenuItem] = []
    private var workDurationMenuItems: [NSMenuItem] = []
    private var breakDurationMenuItems: [NSMenuItem] = []
    private var postponeLimitMenuItems: [NSMenuItem] = []
    private var showCountdownInStatusBar: Bool = false
    private var showCountdownMenuItem: NSMenuItem!

    // Night restriction settings
    private let nightPolicy = NightRestrictionPolicy()
    private let nightOverridePolicy = NightOverridePolicy()
    private var nightRestrictionSettings = NightRestrictionSettings()
    private var nightOverrideState: NightOverrideState?
    
    // Language settings
    private var currentLanguage: String = ""
    private var languageMenuItems: [NSMenuItem] = []
    
    // Protection flags
    private var isCompletingWorkSession = false
    private var isCompletingBreakSession = false
    
    // MARK: - Computed Properties for Time Calculation

    private var effectiveWorkDuration: Int {
        currentNightStatus().effectiveWorkDurationSeconds
    }
    
    private var workTimeRemaining: TimeInterval {
        guard let startTime = workSessionStartTime else {
            return TimeInterval(effectiveWorkDuration)
        }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, TimeInterval(effectiveWorkDuration) - elapsed)
    }
    
    private var breakTimeRemaining: TimeInterval {
        guard let startTime = breakSessionStartTime else {
            return TimeInterval(currentBreakDuration)
        }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, TimeInterval(currentBreakDuration) - elapsed)
    }
    
    private var isWorkSessionActive: Bool {
        return workSessionStartTime != nil && workTimeRemaining > 0
    }
    
    private var isBreakSessionActive: Bool {
        return breakSessionStartTime != nil && breakTimeRemaining > 0
    }
    
    private var postponeTimeRemaining: TimeInterval {
        guard let startTime = postponeStartTime else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, postponeDuration - elapsed)
    }
    
    private var isPostponeActive: Bool {
        return postponeStartTime != nil && postponeTimeRemaining > 0
    }
    
    // MARK: - Localization
    
    // Localization helper
    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, language: currentLanguage)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检查是否已有实例运行
        if !checkSingleInstance() {
            NSApp.terminate(nil)
            return
        }

        loadSettings()
        setupStatusBar()
        setupMenu()
        setupSystemNotifications()
        
        // 记录应用启动
        eventRecorder.recordAppLaunch()

        // 尝试恢复会话状态，如果无法恢复则启动新的工作会话
        print("🔥 准备恢复会话状态...")
        if !restoreSessionIfNeeded() {
            // 没有有效的会话状态，启动新的工作计时器
            print("🔥 恢复失败，启动新的工作计时器")
            startWorkTimer()
        } else {
            // 成功恢复会话状态，仅启动UI更新计时器
            print("🔥 恢复成功，启动UI更新计时器")
            startUIUpdateTimer()
        }
        
        // 启动状态快照计时器（每10秒记录一次状态）
        startStateSnapshotTimer()
        _ = applyNightRestrictionState(reason: "app_launch")
    }
    
    private func checkSingleInstance() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentExecutablePath = Bundle.main.executablePath
        let conflictingBundleIdentifiers = Set([Bundle.main.bundleIdentifier].compactMap { $0 })
        
        print("检查单实例：当前进程 \(currentPID)，可执行路径：\(currentExecutablePath ?? "unknown")")
        
        // 查找相同可执行路径的其他进程
        let sameApps = runningApps.filter { app in
            guard app.processIdentifier != currentPID else { return false }
            
            // 比较可执行路径
            if let executableURL = app.executableURL,
               let currentPath = currentExecutablePath {
                return executableURL.path == currentPath
            }
            
            // 备选方案：比较 bundle identifier (适用于发布版本)
            if let bundleID = app.bundleIdentifier {
                return conflictingBundleIdentifiers.contains(bundleID)
            }
            
            return false
        }
        
        print("找到相同进程：\(sameApps.count)个")
        
        if !sameApps.isEmpty {
            // 有其他实例运行，记录日志并直接退出（不显示弹窗以避免阻塞）
            print("发现已有实例运行，当前实例将退出")
            logManager.logEvent(.appTerminated, context: ["reason": "duplicate_instance"])
            
            // 激活现有实例
            if let existingApp = sameApps.first {
                existingApp.activate(options: [])
            }
            
            return false
        }
        
        return true
    }

    private func restoreSessionIfNeeded() -> Bool {
        logManager.logEvent(.appLaunched, context: ["debug": "restore_start"])

        if let savedState = eventRecorder.restoreSessionState() {
            logManager.logEvent(.appLaunched, context: ["debug": "decode_success", "workStartTime": savedState.workStartTime?.description ?? "nil"])
            
            // 重要：不恢复用户配置（isCustomMode, currentWorkDuration, currentBreakDuration）
            // 这些应该始终来自UserDefaults，通过loadSettings()获取
            // 只恢复时间相关的会话状态（开始时间等）
            
            let timeSinceLastSave = Date().timeIntervalSince(savedState.lastSaved)
            logManager.logEvent(.appLaunched, context: ["debug": "time_check", "seconds_since_save": "\(Int(timeSinceLastSave))", "paused_by_system": "\(savedState.pausedBySystemEvent)"])
            
            // 使用新的恢复逻辑
            if !savedState.shouldRestoreAfterSystemEvent() {
                let reason = savedState.pausedBySystemEvent ? "paused_by_system_event" : "session_too_old"
                logManager.logEvent(.appLaunched, context: ["debug": "session_rejected", "reason": reason])
                logManager.logTimerReset(reason: reason)
                return false
            } else {
                logManager.logEvent(.appLaunched, context: ["debug": "session_valid"])
            }
            
            // 恢复工作会话
            if let workStart = savedState.workStartTime {
                let workElapsed = Date().timeIntervalSince(workStart)
                let plannedWorkDuration = effectiveWorkDuration
                let maxWorkTime = TimeInterval(plannedWorkDuration) + 2 * 60 // 允许2分钟缓冲
                
                if workElapsed < maxWorkTime {
                    // 继续工作会话
                    workSessionStartTime = workStart
                    // 在数据库中记录恢复的会话，使用原始开始时间
                    eventRecorder.startWorkSession(duration: plannedWorkDuration, startTime: workStart)
                    print("🔄 恢复工作会话，已用时 \(Int(workElapsed))秒，剩余 \(Int(workTimeRemaining))秒")
                    
                    if workElapsed >= TimeInterval(plannedWorkDuration) {
                        // 工作时间已到，立即进入休息
                        logManager.logWorkCompleted(duration: workElapsed)
                        showBreakOverlay()
                    }
                    return true
                } else {
                    // 工作时间过长，重置
                    logManager.logWorkPaused(duration: workElapsed, reason: "session_overtime")
                    logManager.logTimerReset(reason: "work_session_overtime")
                    return false
                }
            }
            
            // 恢复休息会话
            if let breakStart = savedState.breakStartTime {
                let breakElapsed = Date().timeIntervalSince(breakStart)
                let maxBreakTime = TimeInterval(currentBreakDuration) + 1 * 60 // 允许1分钟缓冲
                
                if breakElapsed < maxBreakTime {
                    // 继续休息会话
                    breakSessionStartTime = breakStart
                    print("🔄 恢复休息会话，已用时 \(Int(breakElapsed))秒，剩余 \(Int(breakTimeRemaining))秒")
                    showBreakOverlay()
                    return true
                } else {
                    // 休息时间过长，自动完成休息
                    logManager.logBreakCompleted(actualDuration: breakElapsed, expectedDuration: currentBreakDuration)
                    eventRecorder.endBreakSession()
                    logManager.logTimerReset(reason: "break_session_overtime")
                    return false
                }
            }
        }
        
        // 没有有效的保存状态，需要开始新会话
        logManager.logEvent(.appLaunched, context: ["debug": "restore_failed", "reason": "no_session_state"])
        return false
    }
    
    private func startUIUpdateTimer() {
        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateWorkTimer()
        }
        updateStatusBarTitle()
        updateMenuTimer()
    }
    
    private func loadSettings() {
        showCountdownInStatusBar = UserDefaults.standard.bool(forKey: "showCountdownInStatusBar")
        isCustomMode = UserDefaults.standard.bool(forKey: "isCustomMode")
        
        // Load language setting
        if let savedLanguage = UserDefaults.standard.string(forKey: "currentLanguage"),
           AppLocalization.supportedLanguageCodes.contains(savedLanguage) {
            currentLanguage = savedLanguage
        } else {
            // Auto-detect system language
            currentLanguage = AppLocalization.languageCode(for: Locale.preferredLanguages)
        }
        
        let savedCustomWorkDuration = UserDefaults.standard.integer(forKey: "customWorkDuration")
        if savedCustomWorkDuration > 0 {
            customWorkDuration = savedCustomWorkDuration
        }
        
        let savedCustomBreakDuration = UserDefaults.standard.integer(forKey: "customBreakDuration")
        if savedCustomBreakDuration > 0 {
            customBreakDuration = savedCustomBreakDuration
        }

        // Load custom-mode postpone limit setting. Default mode is always fixed at 5 minutes.
        let savedPostponeLimit = UserDefaults.standard.integer(forKey: "maxPostponeMinutes")
        customPostponeLimitMinutes = [5, 10].contains(savedPostponeLimit) ? savedPostponeLimit : 5

        nightRestrictionSettings = NightRestrictionSettings(
            isEnabled: UserDefaults.standard.bool(forKey: "nightRestrictionEnabled"),
            windDownStart: loadClockTime(forKey: "nightWindDownStartMinutes", defaultValue: ClockTime(hour: 20, minute: 0)),
            lockStart: loadClockTime(forKey: "nightLockStartMinutes", defaultValue: ClockTime(hour: 21, minute: 0)),
            unlockTime: loadClockTime(forKey: "nightUnlockMinutes", defaultValue: ClockTime(hour: 7, minute: 0))
        )
        cleanupLegacyNightOverrideDefaults()
        nightOverrideState = loadNightOverrideState()
        clearExpiredNightOverride()

        // Apply the loaded settings
        if isCustomMode {
            currentWorkDuration = customWorkDuration
            currentBreakDuration = customBreakDuration
            maxTotalPostponeTime = TimeInterval(customPostponeLimitMinutes * 60)
        } else {
            currentWorkDuration = 20 * 60
            currentBreakDuration = 20
            maxTotalPostponeTime = 5 * 60
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(showCountdownInStatusBar, forKey: "showCountdownInStatusBar")
        UserDefaults.standard.set(isCustomMode, forKey: "isCustomMode")
        UserDefaults.standard.set(customWorkDuration, forKey: "customWorkDuration")
        UserDefaults.standard.set(customBreakDuration, forKey: "customBreakDuration")
        UserDefaults.standard.set(currentLanguage, forKey: "currentLanguage")
        UserDefaults.standard.set(customPostponeLimitMinutes, forKey: "maxPostponeMinutes")
        UserDefaults.standard.set(nightRestrictionSettings.isEnabled, forKey: "nightRestrictionEnabled")
        UserDefaults.standard.set(nightRestrictionSettings.windDownStart.minutesAfterMidnight, forKey: "nightWindDownStartMinutes")
        UserDefaults.standard.set(nightRestrictionSettings.lockStart.minutesAfterMidnight, forKey: "nightLockStartMinutes")
        UserDefaults.standard.set(nightRestrictionSettings.unlockTime.minutesAfterMidnight, forKey: "nightUnlockMinutes")

        // 记录设置变更
        let changes: [String: String] = [
            "show_countdown": "\(showCountdownInStatusBar)",
            "custom_mode": "\(isCustomMode)",
            "custom_work_duration": "\(customWorkDuration)",
            "custom_break_duration": "\(customBreakDuration)",
            "language": currentLanguage,
            "custom_postpone_limit_minutes": "\(customPostponeLimitMinutes)",
            "effective_postpone_limit_minutes": "\(Int(maxTotalPostponeTime / 60))",
            "night_restriction_enabled": "\(nightRestrictionSettings.isEnabled)",
            "night_wind_down_start": nightRestrictionSettings.windDownStart.displayString,
            "night_lock_start": nightRestrictionSettings.lockStart.displayString,
            "night_unlock_time": nightRestrictionSettings.unlockTime.displayString
        ]
        eventRecorder.recordSettingsChange(changes: changes)
    }
    
    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        
        updateStatusBarTitle()
    }
    
    private func setupMenu() {
        menu = NSMenu()
        menu.delegate = self
        
        timerMenuItem = NSMenuItem(title: formatWorkTime(workTimeRemaining), action: nil, keyEquivalent: "")
        timerMenuItem.isEnabled = false
        menu.addItem(timerMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let testBreakItem = NSMenuItem(title: localized("testBreak"), action: #selector(triggerTestBreak), keyEquivalent: "t")
        testBreakItem.target = self
        testBreakItem.keyEquivalentModifierMask = .command
        menu.addItem(testBreakItem)
        
        let healthStatsItem = NSMenuItem(title: localized("eyeHealthStats"), action: #selector(showHealthStats), keyEquivalent: "s")
        healthStatsItem.target = self
        healthStatsItem.keyEquivalentModifierMask = .command
        menu.addItem(healthStatsItem)

        menu.addItem(NSMenuItem.separator())
        
        setupModeMenu()
        setupNightRestrictionMenu()
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsLabel = NSMenuItem(title: localized("settings"), action: nil, keyEquivalent: "")
        settingsLabel.isEnabled = false
        menu.addItem(settingsLabel)
        
        // Language selection menu
        let languageItem = NSMenuItem(title: localized("language"), action: nil, keyEquivalent: "")
        let languageSubmenu = NSMenu()
        
        for (langCode, langName) in AppLocalization.languageDisplayNames {
            let item = NSMenuItem(title: langName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = langCode
            item.state = (currentLanguage == langCode) ? .on : .off
            languageSubmenu.addItem(item)
            languageMenuItems.append(item)
        }
        
        languageItem.submenu = languageSubmenu
        menu.addItem(languageItem)
        
        loginItemMenuItem = NSMenuItem(title: localized("loginAtStartup"), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItemMenuItem.target = self
        updateLoginItemState()
        menu.addItem(loginItemMenuItem)
        
        showCountdownMenuItem = NSMenuItem(title: localized("showCountdown"), action: #selector(toggleShowCountdown), keyEquivalent: "")
        showCountdownMenuItem.target = self
        updateShowCountdownState()
        menu.addItem(showCountdownMenuItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: localized("about"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: localized("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        statusBarItem.menu = menu
    }
    
    private func setupSystemNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        // Listen for system sleep/wake notifications
        notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Listen for screen sleep/wake notifications
        notificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // Listen for screen lock/unlock notifications (closer to screensaver functionality)
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        
        // Listen for screensaver notifications
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(screensaverDidStart),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil
        )
        
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(screensaverDidStop),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil
        )
    }
    
    private func setupModeMenu() {
        let modeLabel = NSMenuItem(title: localized("mode"), action: nil, keyEquivalent: "")
        modeLabel.isEnabled = false
        menu.addItem(modeLabel)
        
        // Default 20-20-20 Mode
        let defaultModeItem = NSMenuItem(title: localized("defaultMode"), action: #selector(selectDefaultMode), keyEquivalent: "")
        defaultModeItem.target = self
        defaultModeItem.state = !isCustomMode ? .on : .off
        defaultModeItem.representedObject = "defaultMode" // Add identifier
        menu.addItem(defaultModeItem)
        modeMenuItems.append(defaultModeItem)
        
        // Custom Mode
        let customModeItem = NSMenuItem(title: localized("customMode"), action: #selector(selectCustomMode), keyEquivalent: "")
        customModeItem.target = self
        customModeItem.state = isCustomMode ? .on : .off
        customModeItem.representedObject = "customMode" // Add identifier
        menu.addItem(customModeItem)
        modeMenuItems.append(customModeItem)
        
        // Add dynamic sub-items if custom mode is selected
        if isCustomMode {
            addCustomModeSubItems()
        }
    }
    
    private func addCustomModeSubItems() {
        // Find the index of custom mode item
        guard let customModeIndex = menu.items.firstIndex(where: { $0.title == localized("customMode") }) else { return }
        
        // Work Duration Item with current value display
        let currentWorkMinutes = currentWorkDuration / 60
        let workDurationItem = NSMenuItem(title: "    \(localized("screenUsage")): \(currentWorkMinutes) \(localized("minutes"))", action: nil, keyEquivalent: "")
        let workDurationSubmenu = NSMenu()
        
        let workDurations = [10, 15, 20, 25, 30, 35, 40, 45, 50, 60] // minutes
        for duration in workDurations {
            let item = NSMenuItem(title: "\(duration) \(localized("minutes"))", action: #selector(selectWorkDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = duration
            item.state = (currentWorkDuration == duration * 60) ? .on : .off
            workDurationSubmenu.addItem(item)
            workDurationMenuItems.append(item)
        }
        
        workDurationItem.submenu = workDurationSubmenu
        menu.insertItem(workDurationItem, at: customModeIndex + 1)
        
        // Break Duration Item with current value display
        let breakDisplayText: String
        if currentBreakDuration >= 60 {
            let minutes = currentBreakDuration / 60
            breakDisplayText = "\(minutes) \(localized("minutes"))"
        } else {
            breakDisplayText = "\(currentBreakDuration) \(localized("seconds"))"
        }
        let breakDurationItem = NSMenuItem(title: "    \(localized("screenBreak")): \(breakDisplayText)", action: nil, keyEquivalent: "")
        let breakDurationSubmenu = NSMenu()
        
        let breakDurations = [10, 20, 30, 60, 120, 180, 300, 600] // seconds: 10s, 20s, 30s, 1min, 2min, 3min, 5min, 10min
        for duration in breakDurations {
            let displayText: String
            if duration >= 60 {
                let minutes = duration / 60
                displayText = "\(minutes) \(localized("minutes"))"
            } else {
                displayText = "\(duration) \(localized("seconds"))"
            }
            let item = NSMenuItem(title: displayText, action: #selector(selectBreakDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = duration
            item.state = (currentBreakDuration == duration) ? .on : .off
            breakDurationSubmenu.addItem(item)
            breakDurationMenuItems.append(item)
        }
        
        breakDurationItem.submenu = breakDurationSubmenu
        menu.insertItem(breakDurationItem, at: customModeIndex + 2)

        // Postpone Limit Item
        let currentPostponeMinutes = customPostponeLimitMinutes
        let postponeLimitItem = NSMenuItem(title: "    \(localized("postponeLimit")): \(currentPostponeMinutes) \(localized("minutes"))", action: nil, keyEquivalent: "")
        let postponeLimitSubmenu = NSMenu()

        let postponeLimits = [5, 10] // minutes
        for limit in postponeLimits {
            let item = NSMenuItem(title: "\(limit) \(localized("minutes"))", action: #selector(selectPostponeLimit(_:)), keyEquivalent: "")
            item.target = self
            item.tag = limit
            item.state = (currentPostponeMinutes == limit) ? .on : .off
            postponeLimitSubmenu.addItem(item)
            postponeLimitMenuItems.append(item)
        }

        postponeLimitItem.submenu = postponeLimitSubmenu
        menu.insertItem(postponeLimitItem, at: customModeIndex + 3)
    }

    private func removeCustomModeSubItems() {
        // Clear sub-menu items arrays
        workDurationMenuItems.removeAll()
        breakDurationMenuItems.removeAll()
        postponeLimitMenuItems.removeAll()

        // Remove the main duration items from menu
        let itemsToRemove = menu.items.filter {
            $0.title.hasPrefix("    \(localized("screenUsage"))") ||
            $0.title.hasPrefix("    \(localized("screenBreak"))") ||
            $0.title.hasPrefix("    \(localized("postponeLimit"))")
        }
        for item in itemsToRemove {
            menu.removeItem(item)
        }
    }
    
    private func updateCustomModeSubItems() {
        if isCustomMode {
            removeCustomModeSubItems()
            addCustomModeSubItems()
        }
    }

    private func loadClockTime(forKey key: String, defaultValue: ClockTime) -> ClockTime {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        let minutes = min(23 * 60 + 59, max(0, UserDefaults.standard.integer(forKey: key)))
        return ClockTime(minutesAfterMidnight: minutes)
    }

    private func cleanupLegacyNightOverrideDefaults() {
        UserDefaults.standard.removeObject(forKey: NightOverrideDefaults.legacyOverrideUntil)
        UserDefaults.standard.removeObject(forKey: NightOverrideDefaults.legacyTestingExit)
    }

    private func loadNightOverrideState() -> NightOverrideState? {
        guard let grantedAt = UserDefaults.standard.object(forKey: NightOverrideDefaults.grantedAt) as? Date,
              let until = UserDefaults.standard.object(forKey: NightOverrideDefaults.until) as? Date,
              let reasonRawValue = UserDefaults.standard.string(forKey: NightOverrideDefaults.reason),
              let reason = NightOverrideReason(rawValue: reasonRawValue),
              let nightKey = UserDefaults.standard.string(forKey: NightOverrideDefaults.nightKey) else {
            clearNightOverrideState()
            return nil
        }

        return NightOverrideState(
            grantedAt: grantedAt,
            until: until,
            reason: reason,
            nightKey: nightKey,
            overrideNumberForNight: max(1, UserDefaults.standard.integer(forKey: NightOverrideDefaults.numberForNight))
        )
    }

    private func saveNightOverrideState() {
        guard let state = nightOverrideState else {
            clearNightOverrideState()
            return
        }

        UserDefaults.standard.set(state.grantedAt, forKey: NightOverrideDefaults.grantedAt)
        UserDefaults.standard.set(state.until, forKey: NightOverrideDefaults.until)
        UserDefaults.standard.set(state.reason.rawValue, forKey: NightOverrideDefaults.reason)
        UserDefaults.standard.set(state.nightKey, forKey: NightOverrideDefaults.nightKey)
        UserDefaults.standard.set(state.overrideNumberForNight, forKey: NightOverrideDefaults.numberForNight)
    }

    private func clearNightOverrideState() {
        UserDefaults.standard.removeObject(forKey: NightOverrideDefaults.grantedAt)
        UserDefaults.standard.removeObject(forKey: NightOverrideDefaults.until)
        UserDefaults.standard.removeObject(forKey: NightOverrideDefaults.reason)
        UserDefaults.standard.removeObject(forKey: NightOverrideDefaults.nightKey)
        UserDefaults.standard.removeObject(forKey: NightOverrideDefaults.numberForNight)
    }

    private func nightOverrideCount(for nightKey: String) -> Int {
        guard UserDefaults.standard.string(forKey: NightOverrideDefaults.countNightKey) == nightKey else {
            return 0
        }
        return max(0, UserDefaults.standard.integer(forKey: NightOverrideDefaults.countForNight))
    }

    private func saveNightOverrideCount(_ count: Int, nightKey: String) {
        UserDefaults.standard.set(nightKey, forKey: NightOverrideDefaults.countNightKey)
        UserDefaults.standard.set(max(0, count), forKey: NightOverrideDefaults.countForNight)
    }

    private func setupNightRestrictionMenu() {
        nightRestrictionMenuItem = NSMenuItem(title: localized("nightRestriction"), action: nil, keyEquivalent: "")
        nightRestrictionMenuItem.submenu = buildNightRestrictionSubmenu()
        menu.addItem(nightRestrictionMenuItem)
    }

    private func rebuildNightRestrictionMenu() {
        guard nightRestrictionMenuItem != nil else { return }
        nightRestrictionMenuItem.title = localized("nightRestriction")
        nightRestrictionMenuItem.submenu = buildNightRestrictionSubmenu()
    }

    private func buildNightRestrictionSubmenu() -> NSMenu {
        enforceNightScheduleOrder()

        let submenu = NSMenu()

        let enabledItem = NSMenuItem(title: localized("nightRestrictionEnabled"), action: #selector(toggleNightRestriction), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = nightRestrictionSettings.isEnabled ? .on : .off
        submenu.addItem(enabledItem)

        submenu.addItem(NSMenuItem.separator())

        let windDownItem = NSMenuItem(
            title: "\(localized("nightWindDownStart")): \(nightRestrictionSettings.windDownStart.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        windDownItem.submenu = buildTimeSelectionMenu(
            options: timeOptions(from: 18 * 60, through: 23 * 60),
            selected: nightRestrictionSettings.windDownStart,
            action: #selector(selectNightWindDownStart(_:))
        )
        submenu.addItem(windDownItem)

        var lockOptions = timeOptions(from: 18 * 60 + 30, through: 23 * 60 + 30)
            .filter { $0 > nightRestrictionSettings.windDownStart }
        if !lockOptions.contains(nightRestrictionSettings.lockStart),
           nightRestrictionSettings.lockStart > nightRestrictionSettings.windDownStart {
            lockOptions.append(nightRestrictionSettings.lockStart)
            lockOptions.sort()
        }
        let lockItem = NSMenuItem(
            title: "\(localized("nightLockStart")): \(nightRestrictionSettings.lockStart.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        lockItem.submenu = buildTimeSelectionMenu(
            options: lockOptions,
            selected: nightRestrictionSettings.lockStart,
            action: #selector(selectNightLockStart(_:))
        )
        submenu.addItem(lockItem)

        let unlockItem = NSMenuItem(
            title: "\(localized("nightUnlockTime")): \(nightRestrictionSettings.unlockTime.displayString)",
            action: nil,
            keyEquivalent: ""
        )
        unlockItem.submenu = buildTimeSelectionMenu(
            options: timeOptions(from: 5 * 60, through: 10 * 60),
            selected: nightRestrictionSettings.unlockTime,
            action: #selector(selectNightUnlockTime(_:))
        )
        submenu.addItem(unlockItem)

        submenu.addItem(NSMenuItem.separator())

        let rhythmItem = NSMenuItem(title: nightRhythmSummaryTitle(), action: nil, keyEquivalent: "")
        rhythmItem.submenu = buildNightRhythmSubmenu()
        submenu.addItem(rhythmItem)

        return submenu
    }

    private func buildTimeSelectionMenu(options: [ClockTime], selected: ClockTime, action: Selector) -> NSMenu {
        let submenu = NSMenu()
        for time in options {
            let item = NSMenuItem(title: time.displayString, action: action, keyEquivalent: "")
            item.target = self
            item.tag = time.minutesAfterMidnight
            item.state = (time == selected) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func timeOptions(from startMinute: Int, through endMinute: Int, step: Int = 30) -> [ClockTime] {
        guard startMinute <= endMinute else { return [] }
        return stride(from: startMinute, through: endMinute, by: step).map {
            ClockTime(minutesAfterMidnight: $0)
        }
    }

    private func enforceNightScheduleOrder() {
        if nightRestrictionSettings.lockStart <= nightRestrictionSettings.windDownStart {
            let adjustedLockMinute = min(23 * 60 + 30, nightRestrictionSettings.windDownStart.minutesAfterMidnight + 60)
            nightRestrictionSettings.lockStart = ClockTime(minutesAfterMidnight: adjustedLockMinute)
        }
    }

    private func nightRhythmSummaryTitle() -> String {
        let base = formatDurationForMenu(currentWorkDuration)
        return "\(localized("nightRhythmToday")): \(base) -> \(localized("nightDisabled"))"
    }

    private func buildNightRhythmSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let base = formatDurationForMenu(currentWorkDuration)
        let stages = NightRestrictionPolicy.windDownLimits(baseWorkDurationSeconds: currentWorkDuration)
            .map(formatDurationForMenu)

        submenu.addItem(disabledMenuItem("\(localized("nightRhythmCurrent")): \(base)"))
        submenu.addItem(NSMenuItem.separator())

        for (index, stage) in stages.enumerated() {
            submenu.addItem(disabledMenuItem("\(localized("nightRhythmStage")) \(index + 1): \(stage)"))
        }

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(disabledMenuItem("\(localized("nightRhythmLockedAfter")): \(localized("nightDisabled"))"))
        return submenu
    }

    private func disabledMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formatDurationForMenu(_ seconds: Int) -> String {
        "\(max(1, seconds / 60)) \(localized("minutes"))"
    }

    @objc private func toggleNightRestriction() {
        nightRestrictionSettings.isEnabled.toggle()
        saveSettings()
        rebuildNightRestrictionMenu()
        _ = applyNightRestrictionState(reason: "night_setting_toggle")
        updateMenuTimer()
        updateStatusBarTitle()
    }

    @objc private func selectNightWindDownStart(_ sender: NSMenuItem) {
        nightRestrictionSettings.windDownStart = ClockTime(minutesAfterMidnight: sender.tag)
        enforceNightScheduleOrder()
        saveSettings()
        rebuildNightRestrictionMenu()
        _ = applyNightRestrictionState(reason: "night_wind_down_changed")
        updateMenuTimer()
        updateStatusBarTitle()
    }

    @objc private func selectNightLockStart(_ sender: NSMenuItem) {
        let selected = ClockTime(minutesAfterMidnight: sender.tag)
        guard selected > nightRestrictionSettings.windDownStart else { return }

        nightRestrictionSettings.lockStart = selected
        saveSettings()
        rebuildNightRestrictionMenu()
        _ = applyNightRestrictionState(reason: "night_lock_start_changed")
        updateMenuTimer()
        updateStatusBarTitle()
    }

    @objc private func selectNightUnlockTime(_ sender: NSMenuItem) {
        nightRestrictionSettings.unlockTime = ClockTime(minutesAfterMidnight: sender.tag)
        saveSettings()
        rebuildNightRestrictionMenu()
        _ = applyNightRestrictionState(reason: "night_unlock_changed")
        updateMenuTimer()
        updateStatusBarTitle()
    }

    @objc private func statusBarButtonClicked() {
        statusBarItem.menu = menu
        statusBarItem.button?.performClick(nil)
    }
    
    @objc private func triggerTestBreak() {
        // 记录当前工作会话（如果有）
        if let startTime = workSessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            logManager.logWorkPaused(duration: elapsed, reason: "manual_test_break")
        }

        // 使用新的事件记录器
        eventRecorder.endWorkSession()

        workTimer?.invalidate()
        showBreakOverlay()
    }
    
    @objc private func showHealthStats() {
        // 如果窗口已经存在，就激活它而不是创建新的
        if let existingWindow = healthStatsWindow {
            if existingWindow.isVisible {
                existingWindow.reloadData()
                existingWindow.makeKeyAndOrderFront(nil)
                return
            } else {
                // 窗口存在但不可见，清理引用
                healthStatsWindow = nil
            }
        }
        
        // 创建新的统计窗口
        let statsWindow = StatsDashboardWindow()
        statsWindow.setLocalizer(localized)
        healthStatsWindow = statsWindow
        
        // 设置窗口代理以在关闭时清理引用
        statsWindow.delegate = self
        
        // 显示窗口
        statsWindow.makeKeyAndOrderFront(nil)

        // 确保窗口获得焦点
        NSApp.activate(ignoringOtherApps: true)
        
        print("📊 统计窗口已创建并显示")
    }

    @objc private func showAbout() {
        print("📖 showAbout 被调用")

        // 读取版本历史 JSON 文件
        guard let versionData = loadVersionHistory() else {
            print("❌ 无法加载版本历史")
            // 使用默认信息显示
            showAboutPanelWithDefaults()
            return
        }

        print("✅ 成功加载版本历史数据")

        // 构建显示内容
        let appName = versionData["app_name"] as? String ?? AppIdentity.displayName
        let version = versionData["current_version"] as? String ?? "1.5.0"

        var creditsText = ""

        // 添加当前版本信息
        if let versions = versionData["versions"] as? [[String: Any]],
           let currentVersionInfo = versions.first,
           let versionNumber = currentVersionInfo["version"] as? String,
           let date = currentVersionInfo["date"] as? String,
           let changes = currentVersionInfo["changes"] as? [String] {

            creditsText += "Version \(versionNumber) - \(date)\n\n"
            creditsText += "What's New:\n"
            for change in changes {
                creditsText += "• \(change)\n"
            }
            creditsText += "\n"
        }

        // 添加作者信息
        if let author = versionData["author"] as? [String: String],
           let name = author["name"],
           let email = author["email"],
           let github = author["github"] {
            creditsText += "Author: \(name)\n"
            creditsText += "Email: \(email)\n"
            creditsText += "GitHub: \(github)\n"
        }

        print("📝 Credits 内容:\n\(creditsText)")

        // 创建 attributed string
        let credits = NSAttributedString(string: creditsText, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ])

        // 显示标准 About Panel
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: appName,
            .applicationVersion: version,
            .version: version,
            .credits: credits
        ]

        // 激活应用确保窗口显示
        NSApp.activate(ignoringOtherApps: true)

        print("🪟 准备显示 About Panel")
        NSApp.orderFrontStandardAboutPanel(options: options)
        print("✅ About Panel 已调用显示")
    }

    private func loadVersionHistory() -> [String: Any]? {
        // 方法 1: 尝试从资源包加载
        if let bundle = Bundle(for: type(of: self)).url(forResource: "TwentyGuard_TwentyGuard", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundle),
           let jsonPath = resourceBundle.path(forResource: "version-history", ofType: "json", inDirectory: "Resources") {

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    print("✅ 成功从资源包加载版本历史: \(jsonPath)")
                    return dict
                }
            } catch {
                print("⚠️ 解析版本历史失败 (\(jsonPath)): \(error)")
            }
        }

        // 方法 2: 尝试从主 bundle 的 Resources 目录加载
        if let jsonPath = Bundle.main.path(forResource: "version-history", ofType: "json", inDirectory: "Resources") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    print("✅ 成功从主 bundle 加载版本历史: \(jsonPath)")
                    return dict
                }
            } catch {
                print("⚠️ 解析版本历史失败 (\(jsonPath)): \(error)")
            }
        }

        // 方法 3: 尝试从主 bundle 根目录加载
        if let jsonPath = Bundle.main.path(forResource: "version-history", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    print("✅ 成功从主 bundle 根目录加载版本历史: \(jsonPath)")
                    return dict
                }
            } catch {
                print("⚠️ 解析版本历史失败 (\(jsonPath)): \(error)")
            }
        }

        print("⚠️ 未找到版本历史文件")
        return nil
    }

    private func showAboutPanelWithDefaults() {
        print("⚠️ 使用默认信息显示 About Panel")

        // 使用默认信息显示
        let defaultCredits = NSAttributedString(
            string: "TwentyGuard\n\nAuthor: Javen Fang\nEmail: javen.out@gmail.com\nGitHub: JavenGroup/TwentyGuard",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: AppIdentity.displayName,
            .applicationVersion: "1.5.0",
            .version: "1.5.0",
            .credits: defaultCredits
        ]

        // 激活应用确保窗口显示
        NSApp.activate(ignoringOtherApps: true)

        NSApp.orderFrontStandardAboutPanel(options: options)
        print("✅ About Panel（默认）已调用显示")
    }

    @objc private func toggleLoginItem() {
        let currentState = UserDefaults.standard.bool(forKey: "loginItemEnabled")
        let newState = !currentState
        UserDefaults.standard.set(newState, forKey: "loginItemEnabled")
        updateLoginItemState()
        
        if newState {
            addToLoginItems()
        } else {
            removeFromLoginItems()
        }
    }
    
    private func isLoginItemEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "loginItemEnabled")
    }
    
    private func updateLoginItemState() {
        let isEnabled = isLoginItemEnabled()
        loginItemMenuItem.state = isEnabled ? .on : .off
    }
    
    @objc private func toggleShowCountdown() {
        showCountdownInStatusBar.toggle()
        updateShowCountdownState()
        updateStatusBarTitle()
        saveSettings()
    }
    
    private func updateShowCountdownState() {
        showCountdownMenuItem.state = showCountdownInStatusBar ? .on : .off
    }
    
    private func addToLoginItems() {
        let appPath = Bundle.main.bundlePath
        guard !appPath.isEmpty else { return }
        
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        } else {
            let script = """
            tell application "System Events"
                make login item at end with properties {path:"\(appPath)", hidden:false}
            end tell
            """
            
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        }
    }
    
    private func removeFromLoginItems() {
        let appPath = Bundle.main.bundlePath
        guard !appPath.isEmpty else { return }
        
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        } else {
            let script = """
            tell application "System Events"
                delete login item "\(URL(fileURLWithPath: appPath).lastPathComponent)"
            end tell
            """
            
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        }
    }
    
    @objc private func quitApp() {
        // 记录当前会话状态
        if let startTime = workSessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            logManager.logWorkPaused(duration: elapsed, reason: "app_terminated")
        }

        if let startTime = breakSessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            logManager.logBreakCompleted(actualDuration: elapsed, expectedDuration: currentBreakDuration)
            eventRecorder.endBreakSession()
        }

        // 使用新的事件记录器
        eventRecorder.recordAppTermination()
        
        workTimer?.invalidate()
        breakTimer?.invalidate()
        nightLockTimer?.invalidate()
        menuUpdateTimer?.invalidate()
        stateSnapshotTimer?.invalidate()
        for overlay in nightLockOverlays {
            overlay.hideOverlay()
        }
        nightLockOverlays.removeAll()
        
        // Clean up notification observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func selectDefaultMode() {
        if isCustomMode {
            removeCustomModeSubItems()
        }
        isCustomMode = false
        currentWorkDuration = 20 * 60
        currentBreakDuration = 20
        maxTotalPostponeTime = 5 * 60  // Default mode: 5 minutes postpone limit

        eventRecorder.recordModeChange(mode: "default", workDuration: currentWorkDuration, breakDuration: currentBreakDuration)

        saveSettings()
        updateModeMenuStates()
        rebuildNightRestrictionMenu()
        restartWorkTimer()
    }
    
    @objc private func selectCustomMode() {
        if !isCustomMode {
            isCustomMode = true
            currentWorkDuration = customWorkDuration
            currentBreakDuration = customBreakDuration
            maxTotalPostponeTime = TimeInterval(customPostponeLimitMinutes * 60)
            
            eventRecorder.recordModeChange(mode: "custom", workDuration: currentWorkDuration, breakDuration: currentBreakDuration)
            
            addCustomModeSubItems()
            saveSettings()
            updateModeMenuStates()
            rebuildNightRestrictionMenu()
            restartWorkTimer()
        }
    }
    
    @objc private func selectWorkDuration(_ sender: NSMenuItem) {
        currentWorkDuration = sender.tag * 60
        customWorkDuration = currentWorkDuration
        updateCustomModeSubItems()
        updateModeMenuStates()
        saveSettings()
        rebuildNightRestrictionMenu()
        restartWorkTimer()
    }
    
    @objc private func selectBreakDuration(_ sender: NSMenuItem) {
        currentBreakDuration = sender.tag
        customBreakDuration = currentBreakDuration
        updateCustomModeSubItems()
        updateModeMenuStates()
        saveSettings()
    }

    @objc private func selectPostponeLimit(_ sender: NSMenuItem) {
        customPostponeLimitMinutes = sender.tag
        maxTotalPostponeTime = TimeInterval(customPostponeLimitMinutes * 60)
        updateCustomModeSubItems()
        saveSettings()
    }

    private func updateModeMenuStates() {
        // Update mode states based on representedObject instead of array index
        for item in modeMenuItems {
            if let identifier = item.representedObject as? String {
                switch identifier {
                case "defaultMode":
                    item.state = !isCustomMode ? .on : .off
                case "customMode":
                    item.state = isCustomMode ? .on : .off
                default:
                    break
                }
            }
        }
        
        // Update work duration states (only when custom mode is active)
        for item in workDurationMenuItems {
            item.state = (currentWorkDuration == item.tag * 60) ? .on : .off
        }
        
        // Update break duration states (only when custom mode is active)
        for item in breakDurationMenuItems {
            item.state = (currentBreakDuration == item.tag) ? .on : .off
        }
    }
    
    private func restartWorkTimer() {
        if applyNightRestrictionState(reason: "restart_work_timer") {
            return
        }

        // 停止当前工作会话（如果有）
        if let startTime = workSessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            logManager.logWorkPaused(duration: elapsed, reason: "manual_restart")
        }
        
        // 开始新的工作会话
        workSessionStartTime = Date()
        breakSessionStartTime = nil
        postponeStartTime = nil
        postponeDuration = 0
        totalPostponedTime = 0  // 重置累计推迟时间

        updateStatusBarTitle()
        updateMenuTimer()
        saveCurrentSessionState()

        // 使用新的事件记录器
        eventRecorder.startWorkSession(duration: effectiveWorkDuration)
        
        // 启动UI更新计时器
        workTimer?.invalidate()
        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateWorkTimer()
        }
    }
    
    private func startWorkTimer() {
        if applyNightRestrictionState(reason: "start_work_timer") {
            return
        }

        // 如果在推迟期间，不要重置工作会话
        if !isPostponeActive {
            // 如果还没有开始工作会话，则开始一个新的
            if workSessionStartTime == nil {
                workSessionStartTime = Date()
                eventRecorder.recordTimerReset(reason: "fresh_start")
                eventRecorder.startWorkSession(duration: effectiveWorkDuration)
            }
        }
        
        breakSessionStartTime = nil
        updateStatusBarTitle()
        updateMenuTimer()
        saveCurrentSessionState()
        
        // 启动UI更新计时器
        workTimer?.invalidate()
        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateWorkTimer()
        }
    }
    
    private func updateWorkTimer() {
        if applyNightRestrictionState(reason: "work_timer_tick") {
            return
        }

        updateMenuTimer()
        updateStatusBarTitle()

        // 检查推迟时间是否结束
        if isPostponeActive && postponeTimeRemaining <= 0 {
            // 推迟时间结束，清除推迟状态，开始正常休息
            print("⏰ Postpone time finished, showing break overlay")
            workTimer?.invalidate()
            workTimer = nil
            postponeStartTime = nil
            postponeDuration = 0
            showBreakOverlay()
        }
        // 检查工作时间是否已完成（添加重入保护）
        else if workTimeRemaining <= 0 && !isCompletingWorkSession {
            print("⏰ Work time finished (remaining: \(workTimeRemaining)), completing work session")
            completeWorkSession()
        }
    }
    
    private func completeWorkSession() {
        // 设置标志防止重入
        isCompletingWorkSession = true
        
        // 首先停止定时器，无论后续操作是否成功
        workTimer?.invalidate()
        workTimer = nil

        if applyNightRestrictionState(reason: "complete_work_session") {
            isCompletingWorkSession = false
            return
        }
        
        if let startTime = workSessionStartTime {
            let actualDuration = Date().timeIntervalSince(startTime)
            logManager.logWorkCompleted(duration: actualDuration)
        }
        
        // 尝试显示休息窗口
        showBreakOverlay()
        
        // 清除标志
        isCompletingWorkSession = false
    }
    
    private func updateStatusBarTitle() {
        if let button = statusBarItem.button {
            // Try to load custom status bar icon from SPM bundle resources
            if let statusIcon = loadStatusBarIcon() {
                statusIcon.isTemplate = true // This makes it adapt to dark/light mode
                button.image = statusIcon
            } else {
                // Fallback to system symbol if custom icon not found
                button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "TwentyGuard")
            }
            
            let nightStatus = currentNightStatus()

            if nightStatus.isOverrideActive, let state = nightOverrideState {
                button.title = " " + localized("nightOverrideActiveStatus") + " " + formatStatusBarTime(Int(max(0, state.until.timeIntervalSince(Date()))))
            } else if nightStatus.isLocked {
                button.title = " " + localized("nightLockedStatus")
            } else if showCountdownInStatusBar {
                // 如果处于推迟状态，显示推迟倒计时
                if isPostponeActive {
                    button.title = " " + formatStatusBarTime(Int(postponeTimeRemaining))
                } else {
                    button.title = " " + formatStatusBarTime(Int(workTimeRemaining))
                }
            } else {
                button.title = ""
            }
        }
    }
    
    private func loadStatusBarIcon() -> NSImage? {
        // Try different ways to load the custom icon for SPM
        
        // Method 1: Try to load from module bundle with high-res support
        if let bundle = Bundle(for: type(of: self)).url(forResource: "TwentyGuard_TwentyGuard", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundle) {
            
            // Create an NSImage and add both 1x and 2x representations
            let statusIcon = NSImage(size: NSSize(width: 16, height: 16))
            
            // Load 1x image
            if let path1x = resourceBundle.path(forResource: "statusbar_icon", ofType: "png", inDirectory: "Resources"),
               let image1x = NSImage(contentsOfFile: path1x) {
                let rep1x = image1x.representations.first
                rep1x?.size = NSSize(width: 16, height: 16)
                if let rep1x = rep1x {
                    statusIcon.addRepresentation(rep1x)
                }
            }
            
            // Load 2x image
            if let path2x = resourceBundle.path(forResource: "statusbar_icon@2x", ofType: "png", inDirectory: "Resources"),
               let image2x = NSImage(contentsOfFile: path2x) {
                let rep2x = image2x.representations.first
                rep2x?.size = NSSize(width: 16, height: 16) // Logical size stays 16x16
                if let rep2x = rep2x {
                    statusIcon.addRepresentation(rep2x)
                }
            }
            
            return statusIcon.representations.count > 0 ? statusIcon : nil
        }
        
        // Method 2: Try main bundle Resources directory
        if let resourcePath = Bundle.main.path(forResource: "statusbar_icon", ofType: "png", inDirectory: "Resources"),
           let statusIcon = NSImage(contentsOfFile: resourcePath) {
            statusIcon.size = NSSize(width: 16, height: 16)
            return statusIcon
        }
        
        // Method 3: Try main bundle root
        if let resourcePath = Bundle.main.path(forResource: "statusbar_icon", ofType: "png"),
           let statusIcon = NSImage(contentsOfFile: resourcePath) {
            statusIcon.size = NSSize(width: 16, height: 16)
            return statusIcon
        }
        
        return nil
    }
    
    
    private func formatStatusBarTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    private func formatWorkTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%@: %02d:%02d", localized("screenUsage"), minutes, secs)
    }

    private func currentNightStatus(now: Date = Date()) -> NightRestrictionStatus {
        clearExpiredNightOverride(now: now)
        return nightPolicy.status(
            now: now,
            baseWorkDurationSeconds: currentWorkDuration,
            settings: nightRestrictionSettings,
            overrideUntil: nightOverrideState?.until
        )
    }

    private func clearExpiredNightOverride(now: Date = Date()) {
        guard let state = nightOverrideState, !nightOverridePolicy.isActive(state, now: now) else { return }
        eventRecorder.recordNightOverrideExpired(state: state)
        nightOverrideState = nil
        saveNightOverrideState()
    }

    @discardableResult
    private func applyNightRestrictionState(reason: String) -> Bool {
        let status = currentNightStatus()

        switch status.phase {
        case .locked(let unlockTime):
            enterNightLock(unlockTime: unlockTime, schedule: status.schedule, reason: reason)
            return true

        case .windDown(let limitSeconds, _, _, _, _):
            if !nightLockOverlays.isEmpty {
                leaveNightLock(startFreshWorkSession: true)
                return true
            }

            if let workSessionStartTime,
               !isPostponeActive,
               !isCompletingWorkSession,
               Date().timeIntervalSince(workSessionStartTime) >= TimeInterval(limitSeconds) {
                print("🌙 夜间收紧阶段达到当前上限，进入休息")
                completeWorkSession()
                return true
            }

            return false

        case .normal:
            if !nightLockOverlays.isEmpty {
                leaveNightLock(startFreshWorkSession: true)
                return true
            }
            return false
        }
    }

    private func enterNightLock(unlockTime: Date, schedule: NightRestrictionSchedule, reason: String) {
        if !nightLockOverlays.isEmpty {
            refreshNightLockOverlays()
            startNightLockTimer()
            updateMenuTimer()
            updateStatusBarTitle()
            return
        }

        print("🌙 进入夜间禁用：\(reason)")
        closeHealthStatsWindowIfNeeded()
        cleanupBreakOverlays()

        workTimer?.invalidate()
        workTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil

        if let startTime = workSessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            logManager.logWorkPaused(duration: elapsed, reason: "night_lock_\(reason)")
            eventRecorder.endWorkSession()
        }

        if let startTime = breakSessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            logManager.logBreakCompleted(actualDuration: elapsed, expectedDuration: currentBreakDuration)
            eventRecorder.endBreakSession()
        }

        workSessionStartTime = nil
        breakSessionStartTime = nil
        postponeStartTime = nil
        postponeDuration = 0
        totalPostponedTime = 0
        saveCurrentSessionState()

        for screen in NSScreen.screens {
            let overlay = NightRestrictionOverlayWindow(screen: screen)
            overlay.nightDelegate = self
            overlay.configureLocked(
                title: AppIdentity.displayName,
                subtitle: localized("nightLockedStatus"),
                unlockTime: unlockTime,
                recoveryFormat: localized("nightOverrideRecoveryFormat"),
                scheduleText: nightScheduleText(schedule),
                overrideButtonTitle: localized("nightOverride")
            )
            overlay.showOverlay()
            nightLockOverlays.append(overlay)
        }

        startNightLockTimer()
        updateMenuTimer()
        updateStatusBarTitle()
    }

    private func startNightLockTimer() {
        nightLockTimer?.invalidate()
        nightLockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNightLockTimer()
        }
    }

    private func updateNightLockTimer() {
        let status = currentNightStatus()

        if case .locked(let unlockTime) = status.phase {
            for overlay in nightLockOverlays {
                overlay.update(unlockTime: unlockTime, now: Date(), recoveryFormat: localized("nightOverrideRecoveryFormat"))
            }
        } else {
            leaveNightLock(startFreshWorkSession: true)
        }
    }

    private func leaveNightLock(startFreshWorkSession: Bool) {
        nightLockTimer?.invalidate()
        nightLockTimer = nil

        for overlay in nightLockOverlays {
            overlay.hideOverlay()
        }
        nightLockOverlays.removeAll()

        updateMenuTimer()
        updateStatusBarTitle()

        if startFreshWorkSession, workSessionStartTime == nil, breakSessionStartTime == nil {
            startWorkTimer()
        }
    }

    private func refreshNightLockOverlays() {
        let status = currentNightStatus()
        guard case .locked(let unlockTime) = status.phase else { return }

        let scheduleText = nightScheduleText(status.schedule)
        for overlay in nightLockOverlays {
            overlay.configureLocked(
                title: AppIdentity.displayName,
                subtitle: localized("nightLockedStatus"),
                unlockTime: unlockTime,
                recoveryFormat: localized("nightOverrideRecoveryFormat"),
                scheduleText: scheduleText,
                overrideButtonTitle: localized("nightOverride")
            )
        }
    }

    private func nightScheduleText(_ schedule: NightRestrictionSchedule) -> String {
        "\(schedule.windDownStartTime.displayString) \(localized("nightWindDownStart")) - \(schedule.lockStartTime.displayString) \(localized("nightDisabled"))"
    }

    private func nightWindDownHint(for status: NightRestrictionStatus) -> String? {
        guard case .windDown(let limitSeconds, _, _, let lockStart, _) = status.phase else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let limitText = formatDurationForMenu(limitSeconds)
        return String(format: localized("nightWindDownBreakHint"), limitText, formatter.string(from: lockStart))
    }

    private func nightOverrideOverlayText(for request: NightOverrideRequest) -> NightOverrideOverlayText {
        NightOverrideOverlayText(
            requestTitle: localized("nightOverrideRequestTitle"),
            reasonTitle: localized("nightOverrideReasonTitle"),
            reasonTitles: [
                (.urgentWork, localized("nightOverrideReasonUrgentWork")),
                (.lifeTask, localized("nightOverrideReasonLifeTask")),
                (.family, localized("nightOverrideReasonFamily")),
                (.other, localized("nightOverrideReasonOther"))
            ],
            waitFormat: localized("nightOverrideWaiting"),
            waitExplanation: localized("nightOverrideWaitExplanation"),
            confirmPrompt: localized("nightOverrideConfirmPrompt"),
            confirmationText: localized(request.confirmationLocalizationKey),
            inputPlaceholder: localized("nightOverrideInputPlaceholder"),
            cancelTitle: localized("nightOverrideCancel"),
            unlockTitle: localized("nightOverrideUnlock"),
            mismatchText: localized("nightOverrideMismatch")
        )
    }
    
    // MARK: - Helper Methods
    
    private func updateMenuTimer() {
        let nightStatus = currentNightStatus()

        if nightStatus.isOverrideActive, let state = nightOverrideState {
            timerMenuItem.title = "\(localized("nightOverrideActiveStatus")) · \(formatStatusBarTime(Int(max(0, state.until.timeIntervalSince(Date())))))"
        } else if nightStatus.isLocked {
            timerMenuItem.title = "\(localized("nightLockedStatus")) · \(localized("nightUnlockTime")) \(nightStatus.schedule.unlockClockTime.displayString)"
        } else if isPostponeActive {
            // 推迟期间显示推迟倒计时
            let totalSeconds = Int(postponeTimeRemaining)
            let minutes = totalSeconds / 60
            let secs = totalSeconds % 60
            timerMenuItem.title = String(format: "%@: %02d:%02d (%@)", localized("screenUsage"), minutes, secs, localized("postponed"))
        } else if case .windDown(_, _, _, let lockStart, _) = nightStatus.phase {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            timerMenuItem.title = "\(localized("nightWindDownStatus")): \(formatStatusBarTime(Int(workTimeRemaining))) · \(formatter.string(from: lockStart)) \(localized("nightLockStart"))"
        } else {
            timerMenuItem.title = formatWorkTime(workTimeRemaining)
        }
    }
    
    private func saveCurrentSessionState() {
        logManager.saveSessionState(
            workStartTime: workSessionStartTime,
            breakStartTime: breakSessionStartTime,
            currentWorkDuration: currentWorkDuration,
            currentBreakDuration: currentBreakDuration,
            isCustomMode: isCustomMode
        )
    }
    
    private func startStateSnapshotTimer() {
        stateSnapshotTimer?.invalidate()
        stateSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.recordStateSnapshot()
        }
    }
    
    private func stopStateSnapshotTimer() {
        stateSnapshotTimer?.invalidate()
        stateSnapshotTimer = nil
    }
    
    private func recordStateSnapshot() {
        let currentMode = isCustomMode ? "custom" : "default"
        
        logManager.logStateSnapshot(
            workStartTime: workSessionStartTime,
            breakStartTime: breakSessionStartTime,
            workRemaining: workTimeRemaining,
            breakRemaining: breakTimeRemaining,
            currentMode: currentMode
        )
        
        // 同时保存会话状态
        saveCurrentSessionState()
    }
    
    private func showBreakOverlay() {
        print("🎭 showBreakOverlay 被调用")

        if applyNightRestrictionState(reason: "before_break_overlay") {
            return
        }

        closeHealthStatsWindowIfNeeded()

        // 防止重复创建窗口 - 如果已有窗口，先清理
        if !breakOverlays.isEmpty {
            print("⚠️ 检测到已存在 \(breakOverlays.count) 个休息窗口，先清理")
            cleanupBreakOverlays()
        }

        // 检查屏幕是否可用
        guard !NSScreen.screens.isEmpty else {
            print("❌ 没有可用屏幕")
            logManager.logEvent(.breakSkipped, context: ["reason": "no_screens_available"])
            // 屏幕不可用，延迟1秒后重新开始工作会话
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startWorkTimer()
            }
            return
        }

        print("📺 检测到 \(NSScreen.screens.count) 个屏幕")

        // 结束工作会话，开始休息会话
        workSessionStartTime = nil
        breakSessionStartTime = Date()
        saveCurrentSessionState()

        // 使用新的事件记录器
        eventRecorder.startBreakSession(duration: currentBreakDuration)

        // 为每个屏幕创建一个覆盖窗口
        print("🔄 清空旧的 breakOverlays（当前有 \(breakOverlays.count) 个）")
        breakOverlays.removeAll()
        
        for (index, screen) in NSScreen.screens.enumerated() {
            let screenInfo = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown"
            print("  📺 为屏幕 \(index + 1)/\(NSScreen.screens.count) 创建窗口 - 屏幕ID: \(screenInfo)")
            
            let overlay = BreakOverlayWindow(screen: screen)
            overlay.breakDelegate = self
            overlay.setLocalizer(localized)
            overlay.updateCountdown(Int(breakTimeRemaining))

            // 更新推迟状态显示
            let usedMinutes = Int(totalPostponedTime / 60)
            let remainingMinutes = Int((maxTotalPostponeTime - totalPostponedTime) / 60)
            overlay.updatePostponeStatus(used: usedMinutes, remaining: remainingMinutes)
            overlay.setNightWindDownHint(nightWindDownHint(for: currentNightStatus()))

            overlay.showOverlay()
            breakOverlays.append(overlay)
            
            print("     - 窗口创建成功: \(overlay)")
        }
        
        print("✅ 创建了 \(breakOverlays.count) 个休息窗口")
        
        // 如果没有成功创建任何覆盖窗口，回退到工作状态
        if breakOverlays.isEmpty {
            print("❌ 没有成功创建任何窗口")
            logManager.logEvent(.breakSkipped, context: ["reason": "overlay_creation_failed"])
            startWorkTimer()
            return
        }
        
        startBreakTimer()
    }
    
    private func startBreakTimer() {
        breakTimer?.invalidate()
        breakTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateBreakTimer()
        }
    }
    
    private func updateBreakTimer() {
        if applyNightRestrictionState(reason: "break_timer_tick") {
            return
        }

        let remaining = Int(breakTimeRemaining)

        // 检测异常情况：如果休息时间已经超过预期很多，可能是系统睡眠导致的
        if let breakStart = breakSessionStartTime {
            let elapsed = Date().timeIntervalSince(breakStart)
            if elapsed > TimeInterval(currentBreakDuration + 60) { // 超过预期时间1分钟以上
                print("⚠️ 检测到异常的休息时长: \(elapsed)秒, 预期: \(currentBreakDuration)秒")
                print("   可能是系统睡眠导致的，立即完成休息会话")
                completeBreakSession()
                return
            }
        }

        // 更新所有窗口的倒计时
        for overlay in breakOverlays {
            overlay.updateCountdown(max(0, remaining)) // 确保不显示负数
        }

        // 正常完成休息
        if breakTimeRemaining <= 0 && !isCompletingBreakSession {
            completeBreakSession()
        }
    }
    
    private func completeBreakSession() {
        // 设置标志防止重入
        isCompletingBreakSession = true
        
        // 首先停止定时器，无论后续操作是否成功
        breakTimer?.invalidate()
        breakTimer = nil
        
        cleanupBreakOverlays()
        
        if let startTime = breakSessionStartTime {
            let actualDuration = Date().timeIntervalSince(startTime)
            logManager.logBreakCompleted(actualDuration: actualDuration, expectedDuration: currentBreakDuration)
        }

        // 记录休息完成到数据库
        eventRecorder.endBreakSession()

        breakSessionStartTime = nil
        totalPostponedTime = 0  // 完成休息后重置累计推迟时间
        startWorkTimer()
        
        // 清除标志
        isCompletingBreakSession = false
    }
    
    private func cleanupBreakOverlays() {
        // 彻底清理所有休息窗口
        print("🧹 开始清理休息窗口 - 共 \(breakOverlays.count) 个")
        
        for (index, overlay) in breakOverlays.enumerated() {
            let screenInfo = overlay.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown"
            print("  📺 清理窗口 \(index + 1)/\(breakOverlays.count) - 屏幕: \(screenInfo)")
            print("     - 窗口状态: isVisible=\(overlay.isVisible), level=\(overlay.level.rawValue)")
            print("     - 窗口对象: \(overlay)")
            
            overlay.hideOverlay()
            
            print("     - 清理后: isVisible=\(overlay.isVisible)")
        }
        
        let countBefore = breakOverlays.count
        breakOverlays.removeAll()
        print("✅ 窗口清理完成 - 清理前: \(countBefore) 个, 清理后: \(breakOverlays.count) 个")
    }

    private func closeHealthStatsWindowIfNeeded() {
        guard let window = healthStatsWindow else { return }

        window.close()
        healthStatsWindow = nil
        print("📊 进入休息时关闭统计窗口，避免休息结束后自动露出")
    }
    
    private func postponeBreak(minutes: Int) {
        print("🚀 postponeBreak 被调用 - 推迟 \(minutes) 分钟")
        print("  - 当前 breakOverlays 数量: \(breakOverlays.count)")
        print("  - 当前屏幕数量: \(NSScreen.screens.count)")

        let postponeSeconds = TimeInterval(minutes * 60)

        // 检查是否超过累计上限（10分钟）
        if totalPostponedTime + postponeSeconds > maxTotalPostponeTime {
            print("⚠️ 已达推迟上限，累计推迟: \(Int(totalPostponedTime / 60)) 分钟，无法继续推迟 \(minutes) 分钟")
            return
        }

        // 累加推迟时间
        totalPostponedTime += postponeSeconds
        print("📊 累计推迟: \(Int(totalPostponedTime / 60)) 分钟，剩余可推迟: \(Int((maxTotalPostponeTime - totalPostponedTime) / 60)) 分钟")
        
        // 记录推迟的休息
        // 使用新的事件记录器
        eventRecorder.recordPostpone(minutes: minutes)
        
        print("⏸️ 停止休息计时器")
        breakTimer?.invalidate()
        
        print("🧹 调用 cleanupBreakOverlays")
        cleanupBreakOverlays()

        breakSessionStartTime = nil

        // 更新所有休息窗口的推迟状态显示（如果有的话）
        updateBreakOverlaysPostponeStatus()
        
        // 开始推迟计时器 - 不修改原始工作时长设置
        postponeStartTime = Date()
        postponeDuration = TimeInterval(minutes * 60)
        
        // 保持原始工作时长不变，不保存临时状态到会话文件
        logManager.logWorkStarted(mode: "postponed_\(minutes)min")
        
        // 先清理现有的计时器，避免冲突
        workTimer?.invalidate()
        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 更新UI显示推迟倒计时
            self.updateStatusBarTitle()
            self.updateMenuTimer()
            
            // 检查推迟时间是否结束
            if self.postponeTimeRemaining <= 0 {
                // 推迟时间结束，清除推迟状态，开始正常休息
                self.workTimer?.invalidate()
                self.postponeStartTime = nil
                self.postponeDuration = 0
                self.showBreakOverlay()
            }
        }
    }
    
    // MARK: - System Event Handlers
    
    @objc private func systemWillSleep() {
        print("🛌 System will sleep - pausing session")
        pauseCurrentSession(reason: "system_sleep")
        logManager.logEvent(.systemSleep)
    }
    
    @objc private func systemDidWake() {
        print("🌅 System did wake - evaluating session")
        logManager.logEvent(.systemWake)
        evaluateAndResumeSession(reason: "system_wake")
    }
    
    @objc private func screenDidLock() {
        print("🔒 Screen did lock - pausing session")
        pauseCurrentSession(reason: "screen_lock")
        logManager.logEvent(.screenLock)
    }
    
    @objc private func screenDidUnlock() {
        print("🔓 Screen did unlock - evaluating session")
        logManager.logEvent(.screenUnlock)
        evaluateAndResumeSession(reason: "screen_unlock")
    }
    
    @objc private func screensDidSleep() {
        print("📺 Screens did sleep - pausing session")
        pauseCurrentSession(reason: "display_sleep")
        logManager.logEvent(.displaySleep)
    }
    
    @objc private func screensDidWake() {
        print("📺 Screens did wake - evaluating session")
        logManager.logEvent(.displayWake)
        evaluateAndResumeSession(reason: "display_wake")
    }
    
    @objc private func screensaverDidStart() {
        print("🖥️ Screensaver did start - pausing session")
        pauseCurrentSession(reason: "screensaver_start")
        logManager.logEvent(.screensaverStart)
    }
    
    @objc private func screensaverDidStop() {
        print("🖥️ Screensaver did stop - evaluating session")
        logManager.logEvent(.screensaverStop)
        evaluateAndResumeSession(reason: "screensaver_stop")
    }
    
    private func pauseCurrentSession(reason: String) {
        workTimer?.invalidate()
        breakTimer?.invalidate()
        
        // 保存当前状态，标记为被系统事件暂停
        logManager.saveSessionState(
            workStartTime: workSessionStartTime,
            breakStartTime: breakSessionStartTime,
            currentWorkDuration: currentWorkDuration,
            currentBreakDuration: currentBreakDuration,
            isCustomMode: isCustomMode,
            pausedBySystemEvent: true  // 标记为系统事件暂停
        )
    }
    
    private func evaluateAndResumeSession(reason: String) {
        // 首先检查并清理任何残留的休息窗口
        if !breakOverlays.isEmpty {
            print("⚠️ 检测到系统唤醒后有 \(breakOverlays.count) 个残留休息窗口，先清理")
            cleanupBreakOverlays()
        }

        // 用户需求：无论之前什么状态，打开电脑后应该直接进入「工作状态」
        // 方案：任何系统唤醒事件都重置为新的工作会话
        print("🔄 系统唤醒 (\(reason)) - 重置为新的工作会话")

        // 记录之前的会话状态
        if let workStart = workSessionStartTime {
            let elapsed = Date().timeIntervalSince(workStart)
            logManager.logWorkPaused(duration: elapsed, reason: "system_wake_reset_\(reason)")
        } else if let breakStart = breakSessionStartTime {
            let elapsed = Date().timeIntervalSince(breakStart)
            logManager.logBreakCompleted(actualDuration: elapsed, expectedDuration: currentBreakDuration)
            // 记录休息完成到数据库
            eventRecorder.endBreakSession()
        }

        // 清理定时器
        breakTimer?.invalidate()
        breakTimer = nil

        // 重置为新的工作会话
        workSessionStartTime = nil
        breakSessionStartTime = nil
        restartWorkTimer()
    }
}

extension AppDelegate: BreakOverlayDelegate {
    func didRequestPostpone(minutes: Int) {
        postponeBreak(minutes: minutes)
    }
}

extension AppDelegate: NightRestrictionOverlayDelegate {
    func didRequestNightOverride() {
        let status = currentNightStatus()
        guard case .locked = status.phase else {
            leaveNightLock(startFreshWorkSession: true)
            return
        }

        let nightKey = nightOverridePolicy.nightKey(for: status.schedule)
        let request = nightOverridePolicy.request(overrideNumberForNight: nightOverrideCount(for: nightKey) + 1)
        eventRecorder.recordNightOverrideRequested(nightKey: nightKey, request: request)

        let text = nightOverrideOverlayText(for: request)
        for overlay in nightLockOverlays {
            overlay.configureOverrideRequest(request, text: text)
        }
    }

    func didCancelNightOverride(request: NightOverrideRequest) {
        let status = currentNightStatus()
        let nightKey = nightOverridePolicy.nightKey(for: status.schedule)
        eventRecorder.recordNightOverrideCancelled(nightKey: nightKey, request: request)
        refreshNightLockOverlays()
    }

    func didGrantNightOverride(reason: NightOverrideReason, request: NightOverrideRequest) {
        let status = currentNightStatus()
        guard case .locked = status.phase else {
            leaveNightLock(startFreshWorkSession: true)
            return
        }

        let nightKey = nightOverridePolicy.nightKey(for: status.schedule)
        let state = nightOverridePolicy.grant(
            now: Date(),
            reason: reason,
            nightKey: nightKey,
            overrideNumberForNight: request.overrideNumberForNight
        )
        nightOverrideState = state
        saveNightOverrideState()
        saveNightOverrideCount(request.overrideNumberForNight, nightKey: nightKey)
        eventRecorder.recordNightOverrideGranted(state: state, request: request)
        leaveNightLock(startFreshWorkSession: true)
        rebuildNightRestrictionMenu()
        updateMenuTimer()
        updateStatusBarTitle()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 如果关闭的是统计窗口，清理引用
        if let window = notification.object as? StatsDashboardWindow, window == healthStatsWindow {
            healthStatsWindow = nil
            print("📊 统计窗口引用已清理")
        }
    }
}

// MARK: - Helper Methods

extension AppDelegate {
    /// 更新所有休息窗口的推迟状态显示
    private func updateBreakOverlaysPostponeStatus() {
        let usedMinutes = Int(totalPostponedTime / 60)
        let remainingMinutes = Int((maxTotalPostponeTime - totalPostponedTime) / 60)

        for overlay in breakOverlays {
            overlay.updatePostponeStatus(used: usedMinutes, remaining: remainingMinutes)
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateMenuTimer()
        updateLoginItemState()
        updateShowCountdownState()
        updateModeMenuStates()
        rebuildNightRestrictionMenu()
        startMenuUpdateTimer()
    }
    
    func menuDidClose(_ menu: NSMenu) {
        stopMenuUpdateTimer()
    }
    
    private func startMenuUpdateTimer() {
        stopMenuUpdateTimer()
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuTimer()
        }
    }
    
    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
    }
    
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let langCode = sender.representedObject as? String else { return }
        
        currentLanguage = langCode
        saveSettings()
        
        // Update language menu items
        for item in languageMenuItems {
            item.state = (item.representedObject as? String == currentLanguage) ? .on : .off
        }
        
        // Refresh the entire menu with new language
        menu.removeAllItems()
        setupMenu()
        
        // Update break overlays if they exist
        for overlay in breakOverlays {
            overlay.setLocalizer(localized)
        }
        refreshNightLockOverlays()
    }
}
