import Cocoa
import TwentyGuardCore

final class StatsDashboardWindow: NSWindow {
    private let statsDB = StatsDatabase.shared
    private let verdictEvaluator = StatsHealthVerdictEvaluator()
    private var localizer: ((String) -> String)?
    private var dashboardSnapshot: StatsDashboardSnapshot?
    private var monthSnapshot: StatsMonthSnapshot?
    private var selectedMonthDay: Date?
    private var activePage: StatsDashboardPage = .summary
    private let contentStack = NSStackView()
    private weak var monthContentStack: NSStackView?
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
        dashboardSnapshot = snapshot
        monthSnapshot = snapshot.month
        selectedMonthDay = defaultSelectedDay(in: snapshot.month)
        renderDashboard()
    }

    private func renderDashboard() {
        guard let snapshot = dashboardSnapshot, let monthSnapshot else { return }
        clearContent()

        let presentation = StatsDashboardPresentation(
            page: activePage,
            hasQualityIssues: snapshot.week.quality.hasIssues
        )

        for section in presentation.sections {
            switch section {
            case .header:
                addContentSection(makeHeader(snapshot))
            case .pageTabs:
                addContentSection(makePageTabs())
            case .verdict:
                addContentSection(makeVerdictPanel(snapshot.today))
            case .keyMetrics:
                addContentSection(makeKeyMetrics(snapshot.today))
            case .weekTable:
                addContentSection(makeWeekTableSection(snapshot.week))
            case .month:
                addContentSection(makeMonthContentContainer(monthSnapshot))
            case .quality:
                addContentSection(makeQualitySection(snapshot.week.quality))
            }
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
        monthContentStack = nil
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func addContentSection(_ view: NSView) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func replaceStackContents(in stack: NSStackView, with view: NSView) {
        for arrangedView in stack.arrangedSubviews {
            stack.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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

    private func makePageTabs() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let control = NSSegmentedControl(
            labels: [localized("statsSummaryTab"), localized("statsMonthTab")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeStatsPage(_:))
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.segmentStyle = .rounded
        control.selectedSegment = activePage.rawValue
        control.setContentHuggingPriority(.required, for: .horizontal)

        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

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
            title: localized("statsBreakDisciplineMetric"),
            value: formatPercent(today.breakCompletionRate),
            detail: localizedFormat(
                "statsBreakDisciplineDetailFormat",
                today.completedBreaks,
                today.breakOpportunities,
                formatDuration(today.longestWorkSeconds)
            ),
            accent: completionColor(today.breakCompletionRate)
        ))
        row.addArrangedSubview(makeMetricCard(
            title: localized("statsExceptionMetric"),
            value: localizedFormat("statsPostponeCountFormat", today.exceptionCount),
            detail: exceptionDetail(today),
            accent: today.exceptionCount > 0 ? .systemOrange : .systemGreen
        ))
        let isNightRestrictionEnabled = nightRestrictionEnabled()
        row.addArrangedSubview(makeMetricCard(
            title: localized("statsNightBoundaryMetric"),
            value: isNightRestrictionEnabled ? localized("statsEnabled") : localized("statsDisabled"),
            detail: nightBoundaryDetail(today, isEnabled: isNightRestrictionEnabled),
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
        dateLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true

        let workLabel = makeLabel(formatDuration(day.totalWorkSeconds), size: 12, color: .secondaryLabelColor)
        workLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        workLabel.widthAnchor.constraint(equalToConstant: 132).isActive = true

        let completionLabel = makeBadge(formatPercent(day.breakCompletionRate), color: completionColor(day.breakCompletionRate))
        completionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        completionLabel.alignment = .right
        completionLabel.widthAnchor.constraint(equalToConstant: 74).isActive = true

        let postponeLabel = makeLabel("\(day.totalPostpones)", size: 12, weight: .semibold, color: day.totalPostpones > 0 ? .systemOrange : .secondaryLabelColor)
        postponeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        postponeLabel.alignment = .right
        postponeLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true

        let exceptionLabel = makeLabel(exceptionMarker(day), size: 12, weight: .semibold, color: day.exceptionCount > 0 ? .systemOrange : .secondaryLabelColor)
        exceptionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        exceptionLabel.alignment = .right
        exceptionLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        row.addArrangedSubview(dateLabel)
        row.addArrangedSubview(workLabel)
        row.addArrangedSubview(completionLabel)
        row.addArrangedSubview(postponeLabel)
        row.addArrangedSubview(exceptionLabel)
        return row
    }

    private func makeWeekHeaderRow() -> NSView {
        let row = makeHorizontalStack(spacing: 14)
        row.alignment = .centerY

        let dateLabel = makeColumnHeader(localized("statsDateColumn"), width: 62, alignment: .left)
        let workLabel = makeColumnHeader(localized("statsWorkColumn"), width: 132, alignment: .left)
        let completionLabel = makeColumnHeader(localized("statsCompletionColumn"), width: 74, alignment: .right)
        let postponeLabel = makeColumnHeader(localized("statsPostponeColumn"), width: 50, alignment: .right)
        let exceptionLabel = makeColumnHeader(localized("statsExceptionColumn"), width: 56, alignment: .right)

        row.addArrangedSubview(dateLabel)
        row.addArrangedSubview(workLabel)
        row.addArrangedSubview(completionLabel)
        row.addArrangedSubview(postponeLabel)
        row.addArrangedSubview(exceptionLabel)
        return row
    }

    private func makeMonthSection(_ month: StatsMonthSnapshot) -> NSView {
        let panel = makePanel()
        let stack = makeVerticalStack(spacing: 14, inset: 16)
        panel.addSubview(stack)
        pin(stack, to: panel)

        let header = makeHorizontalStack(spacing: 10)
        header.alignment = .centerY

        let previous = NSButton(title: "<", target: self, action: #selector(showPreviousMonth))
        previous.translatesAutoresizingMaskIntoConstraints = false
        previous.bezelStyle = .rounded
        previous.widthAnchor.constraint(equalToConstant: 34).isActive = true

        let title = makeLabel(formatMonth(month.monthStart), size: 16, weight: .semibold)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let next = NSButton(title: ">", target: self, action: #selector(showNextMonth))
        next.translatesAutoresizingMaskIntoConstraints = false
        next.bezelStyle = .rounded
        next.isEnabled = month.monthStart < currentMonthStart()
        next.widthAnchor.constraint(equalToConstant: 34).isActive = true

        header.addArrangedSubview(previous)
        header.addArrangedSubview(title)
        header.addArrangedSubview(next)
        stack.addArrangedSubview(header)

        stack.addArrangedSubview(makeLabel(
            localizedFormat(
                "statsMonthSummaryFormat",
                month.activeDays,
                month.healthyDays,
                formatPercent(month.breakCompletionRate),
                month.exceptionDays
            ),
            size: 12,
            color: .secondaryLabelColor
        ))

        stack.addArrangedSubview(makeMonthCalendar(month))
        stack.addArrangedSubview(makeSelectedDayDetail(month))
        return panel
    }

    private func makeMonthContentContainer(_ month: StatsMonthSnapshot) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = makeVerticalStack(spacing: 0, inset: 0)
        monthContentStack = stack
        container.addSubview(stack)
        pin(stack, to: container)
        refreshMonthContent(with: month)

        return container
    }

    private func refreshMonthContent(with month: StatsMonthSnapshot? = nil) {
        guard let stack = monthContentStack, let month = month ?? monthSnapshot else { return }
        replaceStackContents(in: stack, with: makeMonthSection(month))
    }

    private func makeMonthCalendar(_ month: StatsMonthSnapshot) -> NSView {
        let stack = makeVerticalStack(spacing: 6, inset: 0)
        let weekdayRow = makeHorizontalStack(spacing: 6, distribution: .fillEqually)
        for symbol in shortWeekdaySymbols() {
            let label = makeLabel(symbol, size: 11, weight: .medium, color: .secondaryLabelColor)
            label.alignment = .center
            weekdayRow.addArrangedSubview(label)
        }
        stack.addArrangedSubview(weekdayRow)
        weekdayRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let calendar = Calendar.current
        let leadingBlanks = max(0, calendar.component(.weekday, from: month.monthStart) - calendar.firstWeekday)
        var cells: [StatsDaySnapshot?] = Array(repeating: nil, count: leadingBlanks)
        cells.append(contentsOf: month.days.map(Optional.some))
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        for rowStart in stride(from: 0, to: cells.count, by: 7) {
            let row = makeHorizontalStack(spacing: 6, distribution: .fillEqually)
            for index in rowStart..<(rowStart + 7) {
                row.addArrangedSubview(makeMonthCell(day: cells[index], index: index - leadingBlanks))
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return stack
    }

    private func makeMonthCell(day: StatsDaySnapshot?, index: Int) -> NSView {
        guard let day else {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.heightAnchor.constraint(equalToConstant: 42).isActive = true
            return spacer
        }

        let button = NSButton(title: monthCellTitle(day), target: self, action: #selector(selectMonthDay(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.tag = index
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = monthCellColor(day).cgColor
        button.contentTintColor = .labelColor
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return button
    }

    private func makeSelectedDayDetail(_ month: StatsMonthSnapshot) -> NSView {
        let day = selectedDay(in: month)
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        let stack = makeVerticalStack(spacing: 6, inset: 0)
        panel.addSubview(stack)
        pin(stack, to: panel)

        guard let day else {
            stack.addArrangedSubview(makeLabel(localized("statsMonthNoSelectedDay"), size: 12, color: .secondaryLabelColor))
            return panel
        }

        stack.addArrangedSubview(makeLabel(formatLongDate(day.date), size: 13, weight: .semibold))
        stack.addArrangedSubview(makeLabel(
            localizedFormat(
                "statsSelectedDayDetailFormat",
                formatDuration(day.totalWorkSeconds),
                formatPercent(day.breakCompletionRate),
                day.totalPostpones,
                day.exceptionCount
            ),
            size: 12,
            color: .secondaryLabelColor
        ))
        if day.exceptionCount > 0 {
            stack.addArrangedSubview(makeLabel(exceptionDetail(day), size: 12, color: .systemOrange))
        }
        return panel
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

    private func formatLongDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func shortWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let first = max(0, Calendar.current.firstWeekday - 1)
        return Array(symbols[first...] + symbols[..<first])
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

    private func exceptionMarker(_ day: StatsDaySnapshot) -> String {
        guard day.exceptionCount > 0 else { return localized("statsExceptionNone") }
        return localizedFormat("statsExceptionCountFormat", day.exceptionCount)
    }

    private func exceptionDetail(_ day: StatsDaySnapshot) -> String {
        localizedFormat(
            "statsExceptionDetailFormat",
            day.appExitCount,
            formatDuration(day.appOffSeconds),
            day.temporaryDisableCount,
            formatDuration(day.temporaryDisableSeconds),
            day.nightOverrideCount,
            formatDuration(day.nightOverrideSeconds)
        )
    }

    private func nightBoundaryDetail(_ today: StatsDaySnapshot, isEnabled: Bool) -> String {
        guard isEnabled else { return localized("statsNightDetail") }
        guard today.nightOverrideCount > 0 else { return localized("statsNightNoOverride") }
        return localizedFormat("statsNightOverrideFormat", today.nightOverrideCount, max(1, today.nightOverrideSeconds / 60))
    }

    private func monthCellTitle(_ day: StatsDaySnapshot) -> String {
        let dayNumber = Calendar.current.component(.day, from: day.date)
        if day.exceptionCount > 0 { return "\(dayNumber) !" }
        if day.isHealthyDay { return "\(dayNumber) ." }
        if day.workSessions > 0 || day.breakOpportunities > 0 { return "\(dayNumber)" }
        return "\(dayNumber)"
    }

    private func monthCellColor(_ day: StatsDaySnapshot) -> NSColor {
        if isSelected(day.date) {
            return NSColor.controlAccentColor.withAlphaComponent(0.38)
        }
        if day.exceptionCount > 0 {
            return NSColor.systemOrange.withAlphaComponent(0.22)
        }
        if day.isHealthyDay {
            return NSColor.systemGreen.withAlphaComponent(0.20)
        }
        if day.workSessions > 0 || day.breakOpportunities > 0 {
            return NSColor.systemYellow.withAlphaComponent(0.22)
        }
        return NSColor.separatorColor.withAlphaComponent(0.20)
    }

    private func defaultSelectedDay(in month: StatsMonthSnapshot) -> Date? {
        let calendar = Calendar.current
        if let today = month.days.first(where: { calendar.isDate($0.date, inSameDayAs: Date()) }) {
            return today.date
        }
        return month.days.last(where: { $0.workSessions > 0 || $0.exceptionCount > 0 })?.date ?? month.days.first?.date
    }

    private func selectedDay(in month: StatsMonthSnapshot) -> StatsDaySnapshot? {
        let calendar = Calendar.current
        guard let selectedMonthDay else { return nil }
        return month.days.first { calendar.isDate($0.date, inSameDayAs: selectedMonthDay) }
    }

    private func currentMonthStart() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? calendar.startOfDay(for: Date())
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedMonthDay else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selectedMonthDay)
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

    @objc private func changeStatsPage(_ sender: NSSegmentedControl) {
        guard let page = StatsDashboardPage(rawValue: sender.selectedSegment), page != activePage else {
            return
        }

        activePage = page
        renderDashboard()
    }

    @objc private func showPreviousMonth() {
        guard let monthSnapshot else { return }
        loadMonth(monthSnapshot.previousMonthStart)
    }

    @objc private func showNextMonth() {
        guard let monthSnapshot else { return }
        loadMonth(monthSnapshot.nextMonthStart)
    }

    @objc private func selectMonthDay(_ sender: NSButton) {
        guard let monthSnapshot, monthSnapshot.days.indices.contains(sender.tag) else { return }
        selectedMonthDay = monthSnapshot.days[sender.tag].date
        if StatsDashboardPresentation.renderScope(for: .monthDaySelected) == .monthContent {
            refreshMonthContent()
        } else {
            renderDashboard()
        }
    }

    private func loadMonth(_ date: Date) {
        statsDB.getMonthSnapshot(monthContaining: date) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let snapshot) = result {
                    self.monthSnapshot = snapshot
                    self.selectedMonthDay = self.defaultSelectedDay(in: snapshot)
                    if StatsDashboardPresentation.renderScope(for: .monthChanged) == .monthContent {
                        self.refreshMonthContent(with: snapshot)
                    } else {
                        self.renderDashboard()
                    }
                }
            }
        }
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
