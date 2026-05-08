import Cocoa
import TwentyGuardCore

final class StatsDashboardWindow: NSWindow {
    private let statsDB = StatsDatabase.shared
    private let logManager = LogManager.shared
    private let verdictEvaluator = StatsHealthVerdictEvaluator()
    private var localizer: ((String) -> String)?
    private let contentStack = NSStackView()
    private let scrollView = NSScrollView()
    private let documentView = FlippedDocumentView()
    private let footerView = NSView()
    private let closeButton = NSButton()

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupLayout()
        centerOnMainScreen()
        loadSnapshot()
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    }

    func setLocalizer(_ localizer: @escaping (String) -> String) {
        self.localizer = localizer
        title = localizer("eye_health_report")
        closeButton.title = localizer("close")
    }

    func reloadData() {
        loadSnapshot()
    }

    private func setupWindow() {
        title = localized("eye_health_report")
        minSize = NSSize(width: 560, height: 560)
        isReleasedWhenClosed = false
        backgroundColor = .controlBackgroundColor
    }

    private func setupLayout() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        contentView = rootView

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        documentView.addSubview(contentStack)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.wantsLayer = true
        footerView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.title = localized("close")
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        rootView.addSubview(scrollView)
        rootView.addSubview(footerView)
        footerView.addSubview(separator)
        footerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 58),

            separator.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: footerView.topAnchor),

            closeButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -22),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24)
        ])
    }

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else {
            center()
            return
        }

        let screenFrame = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.midY - frame.height / 2
        ))
    }

    private func loadSnapshot() {
        showLoading()

        statsDB.getDashboardSnapshot { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let snapshot):
                    self.render(snapshot)
                case .failure:
                    self.renderError()
                }
            }
        }
    }

    private func showLoading() {
        clearContent()
        let label = makeLabel(localized("statsLoading"), size: 14, color: .secondaryLabelColor)
        label.alignment = .center
        addContentSection(label)
    }

    private func render(_ snapshot: StatsDashboardSnapshot) {
        clearContent()
        addContentSection(makeHeader(snapshot))
        addContentSection(makeVerdictPanel(snapshot.today))
        addContentSection(makeKeyMetrics(snapshot.today))
        addContentSection(makeWeekTableSection(snapshot.week))
        if snapshot.week.quality.hasIssues {
            addContentSection(makeQualitySection(snapshot.week.quality))
        }
        scrollToTop()
    }

    private func renderError() {
        clearContent()
        addContentSection(makeHeader(nil))
        let panel = makePanel()
        let stack = makeVerticalStack(spacing: 8, inset: 16)
        panel.addSubview(stack)
        pin(stack, to: panel)
        stack.addArrangedSubview(makeLabel(localized("statsUnavailableTitle"), size: 15, weight: .semibold))
        stack.addArrangedSubview(makeLabel(localized("statsUnavailableMessage"), size: 13, color: .secondaryLabelColor))
        addContentSection(panel)
        scrollToTop()
    }

    private func clearContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func addContentSection(_ view: NSView) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makeHeader(_ snapshot: StatsDashboardSnapshot?) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = makeVerticalStack(spacing: 6, inset: 0)
        container.addSubview(stack)
        pin(stack, to: container)

        stack.addArrangedSubview(makeLabel(localized("eye_health_report"), size: 24, weight: .bold))

        let subtitle: String
        if let snapshot {
            subtitle = localizedFormat("statsUpdatedAtFormat", formatDateTime(snapshot.generatedAt))
        } else {
            subtitle = localized("statsLoadingSubtitle")
        }
        stack.addArrangedSubview(makeLabel(subtitle, size: 12, color: .secondaryLabelColor))

        return container
    }

    private func makeVerdictPanel(_ today: StatsDaySnapshot) -> NSView {
        let panel = makePanel()
        panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 142).isActive = true

        let stack = makeVerticalStack(spacing: 10, inset: 18)
        panel.addSubview(stack)
        pin(stack, to: panel)

        let verdict = verdictEvaluator.verdict(for: today, localize: localized)
        stack.addArrangedSubview(makeLabel(localized("statsTodayVerdict"), size: 13, weight: .medium, color: .secondaryLabelColor))

        let titleLabel = makeLabel(verdict.title, size: 32, weight: .bold, color: verdictColor(verdict.severity))
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(titleLabel)

        let reasonLabel = makeLabel(verdict.reason, size: 14, weight: .medium, color: .secondaryLabelColor)
        stack.addArrangedSubview(reasonLabel)

        if today.totalWorkSeconds > 0 {
            stack.addArrangedSubview(makeLabel(
                localizedFormat(
                    "statsTotalAndLongestFormat",
                    formatDuration(today.totalWorkSeconds),
                    formatDuration(today.longestWorkSeconds)
                ),
                size: 12,
                color: .tertiaryLabelColor
            ))
        }

        return panel
    }

    private func makeKeyMetrics(_ today: StatsDaySnapshot) -> NSView {
        let container = makeVerticalStack(spacing: 12, inset: 0)

        container.addArrangedSubview(makeSectionTitle(localized("statsKeyMetrics")))

        let row = makeHorizontalStack(distribution: .fillEqually)
        row.addArrangedSubview(makeMetricCard(
            title: localized("statsCompletionRate"),
            value: formatPercent(today.breakCompletionRate),
            detail: localizedFormat("statsCompletionDetailFormat", today.completedBreaks, today.breakOpportunities),
            accent: completionColor(today.breakCompletionRate)
        ))
        row.addArrangedSubview(makeMetricCard(
            title: localized("statsPostponeMetric"),
            value: localizedFormat("statsPostponeCountFormat", today.totalPostpones),
            detail: localizedFormat("statsPostponedSessionsFormat", today.postponedSessions),
            accent: today.postponeSessionRate > 0.3 ? .systemOrange : .systemGreen
        ))
        let isNightRestrictionEnabled = nightRestrictionEnabled()
        row.addArrangedSubview(makeMetricCard(
            title: localized("statsNightMetric"),
            value: isNightRestrictionEnabled ? localized("statsEnabled") : localized("statsDisabled"),
            detail: nightOverrideDetail(isEnabled: isNightRestrictionEnabled),
            accent: isNightRestrictionEnabled ? .systemGreen : .secondaryLabelColor,
            monospacedValue: false
        ))

        container.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        return container
    }

    private func makeTodayDetails(_ today: StatsDaySnapshot) -> NSView {
        let panel = makePanel()
        let stack = makeVerticalStack(spacing: 12, inset: 16)
        panel.addSubview(stack)
        pin(stack, to: panel)

        stack.addArrangedSubview(makeSectionTitle(localized("statsTodayDetails")))
        stack.addArrangedSubview(makeInfoRow(title: localized("statsTotalWorkDuration"), value: formatDuration(today.totalWorkSeconds)))
        stack.addArrangedSubview(makeInfoRow(title: localized("statsBreakOpportunities"), value: localizedFormat("statsPostponeCountFormat", today.breakOpportunities)))
        stack.addArrangedSubview(makeInfoRow(title: localized("statsCompletedBreaks"), value: localizedFormat("statsPostponeCountFormat", today.completedBreaks)))
        stack.addArrangedSubview(makeInfoRow(title: localized("statsPostponeBreakdown"), value: postponeBreakdown(today.postponesByMinutes)))

        return panel
    }

    private func makeWeekTableSection(_ week: StatsWeekSnapshot) -> NSView {
        let panel = makePanel()
        let stack = makeVerticalStack(spacing: 14, inset: 16)
        panel.addSubview(stack)
        pin(stack, to: panel)

        stack.addArrangedSubview(makeSectionTitle(localized("statsLast7Days")))
        stack.addArrangedSubview(makeLabel(
            localizedFormat(
                "statsWeekSummaryFormat",
                formatDuration(week.totalWorkSeconds),
                week.healthyDays,
                formatPercent(week.breakCompletionRate)
            ),
            size: 12,
            color: .secondaryLabelColor
        ))

        let dayList = makeVerticalStack(spacing: 8, inset: 0)
        dayList.addArrangedSubview(makeWeekHeaderRow())
        for day in week.days.reversed() {
            dayList.addArrangedSubview(makeDayRow(day))
        }
        stack.addArrangedSubview(dayList)

        return panel
    }

    private func makeQualitySection(_ quality: StatsQualitySummary) -> NSView {
        let panel = makePanel()
        let stack = makeVerticalStack(spacing: 10, inset: 16)
        panel.addSubview(stack)
        pin(stack, to: panel)

        stack.addArrangedSubview(makeSectionTitle(localized("statsDataQuality")))

        let messages = qualityMessages(quality)
        if messages.isEmpty {
            stack.addArrangedSubview(makeLabel(localized("statsNoQualityIssues"), size: 13, color: .secondaryLabelColor))
        } else {
            for message in messages {
                stack.addArrangedSubview(makeLabel(message, size: 13, color: .secondaryLabelColor))
            }
        }

        return panel
    }

    private func makeDayRow(_ day: StatsDaySnapshot) -> NSView {
        let row = makeHorizontalStack(spacing: 14)
        row.alignment = .centerY

        let dateLabel = makeLabel(formatShortDate(day.date), size: 12, weight: .medium)
        dateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        dateLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let workLabel = makeLabel(formatDuration(day.totalWorkSeconds), size: 12, color: .secondaryLabelColor)
        workLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        workLabel.widthAnchor.constraint(equalToConstant: 178).isActive = true

        let completionLabel = makeBadge(formatPercent(day.breakCompletionRate), color: completionColor(day.breakCompletionRate))
        completionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        completionLabel.alignment = .right
        completionLabel.widthAnchor.constraint(equalToConstant: 74).isActive = true

        let postponeLabel = makeLabel("\(day.totalPostpones)", size: 12, weight: .semibold, color: day.totalPostpones > 0 ? .systemOrange : .secondaryLabelColor)
        postponeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        postponeLabel.alignment = .right
        postponeLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        row.addArrangedSubview(dateLabel)
        row.addArrangedSubview(workLabel)
        row.addArrangedSubview(completionLabel)
        row.addArrangedSubview(postponeLabel)
        return row
    }

    private func makeWeekHeaderRow() -> NSView {
        let row = makeHorizontalStack(spacing: 14)
        row.alignment = .centerY

        let dateLabel = makeColumnHeader(localized("statsDateColumn"), width: 68, alignment: .left)
        let workLabel = makeColumnHeader(localized("statsWorkColumn"), width: 178, alignment: .left)
        let completionLabel = makeColumnHeader(localized("statsCompletionColumn"), width: 74, alignment: .right)
        let postponeLabel = makeColumnHeader(localized("statsPostponeColumn"), width: 56, alignment: .right)

        row.addArrangedSubview(dateLabel)
        row.addArrangedSubview(workLabel)
        row.addArrangedSubview(completionLabel)
        row.addArrangedSubview(postponeLabel)
        return row
    }

    private func makeColumnHeader(_ text: String, width: CGFloat, alignment: NSTextAlignment) -> NSTextField {
        let label = makeLabel(text, size: 11, weight: .medium, color: .secondaryLabelColor)
        label.alignment = alignment
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func makeMetricCard(title: String, value: String, detail: String, accent: NSColor, monospacedValue: Bool = true) -> NSView {
        let card = makePanel()
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true

        let stack = makeVerticalStack(spacing: 6, inset: 14)
        card.addSubview(stack)
        pin(stack, to: card)

        let titleLabel = makeLabel(title, size: 12, color: .secondaryLabelColor)
        let valueLabel = makeLabel(value, size: 22, weight: .bold)
        valueLabel.font = monospacedValue ? .monospacedDigitSystemFont(ofSize: 22, weight: .bold) : .systemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = accent
        let detailLabel = makeLabel(detail, size: 11, color: .secondaryLabelColor)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(detailLabel)

        return card
    }

    private func makeInfoRow(title: String, value: String) -> NSView {
        let row = makeHorizontalStack(spacing: 12)
        row.alignment = .firstBaseline

        let titleLabel = makeLabel(title, size: 13, color: .secondaryLabelColor)
        titleLabel.widthAnchor.constraint(equalToConstant: 112).isActive = true

        let valueLabel = makeLabel(value, size: 13, weight: .medium)
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        makeLabel(text, size: 16, weight: .semibold)
    }

    private func makePanel() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        view.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.64).cgColor
        return view
    }

    private func makeVerticalStack(spacing: CGFloat, inset: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        return stack
    }

    private func makeHorizontalStack(spacing: CGFloat = 12, distribution: NSStackView.Distribution = .fill) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = distribution
        stack.spacing = spacing
        return stack
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeBadge(_ text: String, color: NSColor) -> NSTextField {
        let label = makeLabel(text, size: 12, weight: .semibold, color: color)
        label.alignment = .right
        return label
    }

    private func pin(_ child: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    private func scrollToTop() {
        documentView.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return localized("statsZeroMinutes") }
        let minutes = max(1, seconds / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 && remainingMinutes > 0 {
            return localizedFormat("statsHoursMinutesFormat", hours, remainingMinutes)
        }
        if hours > 0 {
            return localizedFormat("statsHoursFormat", hours)
        }
        return localizedFormat("statsMinutesFormat", minutes)
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private func postponeBreakdown(_ values: [Int: Int]) -> String {
        let one = values[1] ?? 0
        let two = values[2] ?? 0
        let five = values[5] ?? 0
        let other = values.filter { ![1, 2, 5].contains($0.key) }.reduce(0) { $0 + $1.value }
        if other > 0 {
            return localizedFormat("statsPostponeBreakdownWithOtherFormat", one, two, five, other)
        }
        return localizedFormat("statsPostponeBreakdownFormat", one, two, five)
    }

    private func longestWorkDetail(_ seconds: Int) -> String {
        if seconds == 0 { return localized("statsNoValidSessionsToday") }
        if seconds > 90 * 60 { return localized("statsObviouslyLong") }
        if seconds > 60 * 60 { return localized("statsNeedsAttention") }
        return localized("statsNormalRhythm")
    }

    private func verdictColor(_ severity: StatsHealthVerdictSeverity) -> NSColor {
        switch severity {
        case .good:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .neutral:
            return .labelColor
        }
    }

    private func nightRestrictionEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "nightRestrictionEnabled")
    }

    private func nightOverrideDetail(isEnabled: Bool) -> String {
        guard isEnabled else { return localized("statsNightDetail") }

        let summary = logManager.nightOverrideSummary(nightKey: currentStatsNightKey())
        if summary.count == 0 {
            return localized("statsNightNoOverride")
        }
        return localizedFormat("statsNightOverrideFormat", summary.count, summary.totalMinutes)
    }

    private func currentStatsNightKey(now: Date = Date()) -> String {
        let calendar = Calendar.current
        let settings = NightRestrictionSettings(
            isEnabled: true,
            windDownStart: loadClockTime(forKey: "nightWindDownStartMinutes", defaultValue: ClockTime(hour: 20, minute: 0)),
            lockStart: loadClockTime(forKey: "nightLockStartMinutes", defaultValue: ClockTime(hour: 21, minute: 0)),
            unlockTime: loadClockTime(forKey: "nightUnlockMinutes", defaultValue: ClockTime(hour: 7, minute: 0))
        )
        let today = calendar.startOfDay(for: now)
        let windDownToday = date(on: today, at: settings.windDownStart, calendar: calendar)
        let anchorDay: Date
        if now >= windDownToday {
            anchorDay = today
        } else {
            anchorDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }

        let schedule = nightSchedule(anchorDay: anchorDay, settings: settings, calendar: calendar)
        return NightOverridePolicy(calendar: calendar).nightKey(for: schedule)
    }

    private func loadClockTime(forKey key: String, defaultValue: ClockTime) -> ClockTime {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        let minutes = min(23 * 60 + 59, max(0, UserDefaults.standard.integer(forKey: key)))
        return ClockTime(minutesAfterMidnight: minutes)
    }

    private func nightSchedule(anchorDay: Date, settings: NightRestrictionSettings, calendar: Calendar) -> NightRestrictionSchedule {
        let windDownStart = date(on: anchorDay, at: settings.windDownStart, calendar: calendar)
        var lockStart = date(on: anchorDay, at: settings.lockStart, calendar: calendar)
        var unlockTime = date(on: anchorDay, at: settings.unlockTime, calendar: calendar)

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

    private func date(on day: Date, at time: ClockTime, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }

    private func completionColor(_ rate: Double) -> NSColor {
        if rate >= 0.8 { return .systemGreen }
        if rate >= 0.5 { return .systemOrange }
        return .systemRed
    }

    private func qualityMessages(_ quality: StatsQualitySummary) -> [String] {
        var messages: [String] = []

        if quality.excludedStaleSessions > 0 {
            messages.append(localizedFormat("statsExcludedStaleSessionsFormat", quality.excludedStaleSessions))
        }
        if quality.ignoredShortSessions > 0 {
            messages.append(localizedFormat("statsIgnoredShortSessionsFormat", quality.ignoredShortSessions))
        }
        if quality.activeBreakRecords > 0 {
            messages.append(localizedFormat("statsActiveBreakRecordsFormat", quality.activeBreakRecords))
        }
        if quality.interruptedBreakRecords > 0 {
            messages.append(localizedFormat("statsInterruptedBreakRecordsFormat", quality.interruptedBreakRecords))
        }
        if quality.unclosedPostponeRecords > 0 {
            messages.append(localizedFormat("statsUnclosedPostponeRecordsFormat", quality.unclosedPostponeRecords))
        }

        return messages
    }

    private func localized(_ key: String) -> String {
        localizer?(key) ?? AppLocalization.localized(key, language: AppLocalization.fallbackLanguageCode)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), arguments: arguments)
    }

    @objc private func closeWindow() {
        close()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}
