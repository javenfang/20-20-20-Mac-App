import Cocoa
import TwentyGuardCore

protocol NightRestrictionOverlayDelegate: AnyObject {
    func didRequestNightOverride()
    func didCancelNightOverride(request: NightOverrideRequest)
    func didGrantNightOverride(reason: NightOverrideReason, request: NightOverrideRequest)
}

struct NightOverrideOverlayText {
    let requestTitle: String
    let reasonTitle: String
    let reasonTitles: [(reason: NightOverrideReason, title: String)]
    let waitFormat: String
    let waitExplanation: String
    let confirmPrompt: String
    let confirmationText: String
    let inputPlaceholder: String
    let cancelTitle: String
    let unlockTitle: String
    let mismatchText: String
}

final class NightRestrictionOverlayWindow: NSWindow {
    weak var nightDelegate: NightRestrictionOverlayDelegate?

    private var lockedStack: NSStackView!
    private var requestStack: NSStackView!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var countdownLabel: NSTextField!
    private var recoveryLabel: NSTextField!
    private var scheduleLabel: NSTextField!
    private var overrideButton: NSButton!

    private var requestTitleLabel: NSTextField!
    private var reasonTitleLabel: NSTextField!
    private var reasonStack: NSStackView!
    private var waitLabel: NSTextField!
    private var waitExplanationLabel: NSTextField!
    private var confirmPromptLabel: NSTextField!
    private var confirmationLabel: NSTextField!
    private var confirmationField: NoPasteTextField!
    private var mismatchLabel: NSTextField!
    private var cancelButton: NSButton!
    private var unlockButton: NSButton!

    private var request: NightOverrideRequest?
    private var selectedReason: NightOverrideReason?
    private var expectedConfirmation = ""
    private var waitRemaining = 0
    private var waitFormat = ""
    private var unlockTitle = ""
    private var mismatchText = ""
    private var requestTimer: Timer?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        setupWindow()
        setupUI()
    }

    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrameOrigin(screen.frame.origin)
    }

    private func setupWindow() {
        level = .screenSaver
        backgroundColor = NSColor.black.withAlphaComponent(0.92)
        isOpaque = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
    }

    private func setupUI() {
        guard let contentView else { return }

        titleLabel = makeLabel("", size: 18, weight: .medium, color: .secondaryLabelColor)
        subtitleLabel = makeLabel("", size: 44, weight: .semibold, color: .labelColor)
        countdownLabel = makeLabel("00:00:00", size: 86, weight: .bold, color: .labelColor, monospaced: true)
        recoveryLabel = makeLabel("", size: 22, weight: .semibold, color: .labelColor)
        scheduleLabel = makeLabel("", size: 15, weight: .regular, color: .secondaryLabelColor)

        lockedStack = makeVerticalStack(spacing: 14)
        lockedStack.alignment = .centerX
        lockedStack.addArrangedSubview(titleLabel)
        lockedStack.addArrangedSubview(subtitleLabel)
        lockedStack.setCustomSpacing(34, after: subtitleLabel)
        lockedStack.addArrangedSubview(countdownLabel)
        lockedStack.setCustomSpacing(38, after: countdownLabel)
        lockedStack.addArrangedSubview(recoveryLabel)
        lockedStack.addArrangedSubview(scheduleLabel)

        requestTitleLabel = makeLabel("", size: 32, weight: .semibold, color: .labelColor)
        reasonTitleLabel = makeLabel("", size: 14, weight: .medium, color: .secondaryLabelColor)
        reasonStack = makeHorizontalStack(spacing: 10)
        waitLabel = makeLabel("", size: 24, weight: .semibold, color: .labelColor)
        waitExplanationLabel = makeLabel("", size: 13, weight: .regular, color: .secondaryLabelColor)
        confirmPromptLabel = makeLabel("", size: 14, weight: .medium, color: .secondaryLabelColor)
        confirmationLabel = makeLabel("", size: 16, weight: .semibold, color: .labelColor)
        confirmationField = NoPasteTextField()
        confirmationField.translatesAutoresizingMaskIntoConstraints = false
        confirmationField.font = .systemFont(ofSize: 16, weight: .medium)
        confirmationField.alignment = .center
        confirmationField.delegate = self
        confirmationField.menu = nil
        mismatchLabel = makeLabel("", size: 12, weight: .medium, color: .systemRed)
        mismatchLabel.isHidden = true

        let actionRow = makeHorizontalStack(spacing: 12)
        actionRow.alignment = .centerY
        cancelButton = NSButton(title: "", target: self, action: #selector(cancelOverrideClicked))
        cancelButton.bezelStyle = .rounded
        unlockButton = NSButton(title: "", target: self, action: #selector(unlockOverrideClicked))
        unlockButton.bezelStyle = .rounded
        actionRow.addArrangedSubview(cancelButton)
        actionRow.addArrangedSubview(unlockButton)

        requestStack = makeVerticalStack(spacing: 14)
        requestStack.alignment = .centerX
        requestStack.addArrangedSubview(requestTitleLabel)
        requestStack.setCustomSpacing(22, after: requestTitleLabel)
        requestStack.addArrangedSubview(reasonTitleLabel)
        requestStack.addArrangedSubview(reasonStack)
        requestStack.setCustomSpacing(20, after: reasonStack)
        requestStack.addArrangedSubview(waitLabel)
        requestStack.addArrangedSubview(waitExplanationLabel)
        requestStack.setCustomSpacing(20, after: waitExplanationLabel)
        requestStack.addArrangedSubview(confirmPromptLabel)
        requestStack.addArrangedSubview(confirmationLabel)
        requestStack.addArrangedSubview(confirmationField)
        requestStack.addArrangedSubview(mismatchLabel)
        requestStack.setCustomSpacing(18, after: mismatchLabel)
        requestStack.addArrangedSubview(actionRow)
        requestStack.isHidden = true

        overrideButton = NSButton(title: "", target: self, action: #selector(overrideClicked))
        overrideButton.font = .systemFont(ofSize: 12, weight: .regular)
        overrideButton.bezelStyle = .inline
        overrideButton.translatesAutoresizingMaskIntoConstraints = false
        overrideButton.contentTintColor = .secondaryLabelColor

        contentView.addSubview(lockedStack)
        contentView.addSubview(requestStack)
        contentView.addSubview(overrideButton)

        NSLayoutConstraint.activate([
            lockedStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            lockedStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -10),
            lockedStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 56),
            lockedStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -56),

            requestStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            requestStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            requestStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 56),
            requestStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -56),
            requestStack.widthAnchor.constraint(lessThanOrEqualToConstant: 680),

            confirmationField.widthAnchor.constraint(equalToConstant: 560),
            confirmationField.heightAnchor.constraint(equalToConstant: 34),

            overrideButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            overrideButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            overrideButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            overrideButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, monospaced: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = monospaced ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeVerticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = spacing
        return stack
    }

    private func makeHorizontalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = spacing
        return stack
    }

    func configureLocked(
        title: String,
        subtitle: String,
        unlockTime: Date,
        recoveryFormat: String,
        scheduleText: String,
        overrideButtonTitle: String
    ) {
        requestTimer?.invalidate()
        requestTimer = nil
        request = nil
        selectedReason = nil

        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        scheduleLabel.stringValue = scheduleText
        overrideButton.title = overrideButtonTitle
        lockedStack.isHidden = false
        requestStack.isHidden = true
        overrideButton.isHidden = false
        update(unlockTime: unlockTime, now: Date(), recoveryFormat: recoveryFormat)
    }

    func configureOverrideRequest(_ request: NightOverrideRequest, text: NightOverrideOverlayText) {
        self.request = request
        selectedReason = nil
        expectedConfirmation = text.confirmationText
        waitRemaining = request.waitSeconds
        waitFormat = text.waitFormat
        unlockTitle = text.unlockTitle
        mismatchText = text.mismatchText

        requestTitleLabel.stringValue = text.requestTitle
        reasonTitleLabel.stringValue = text.reasonTitle
        waitLabel.stringValue = String(format: text.waitFormat, waitRemaining)
        waitExplanationLabel.stringValue = text.waitExplanation
        confirmPromptLabel.stringValue = text.confirmPrompt
        confirmationLabel.stringValue = text.confirmationText
        confirmationField.placeholderString = text.inputPlaceholder
        confirmationField.stringValue = ""
        mismatchLabel.stringValue = text.mismatchText
        mismatchLabel.isHidden = true
        cancelButton.title = text.cancelTitle
        unlockButton.title = String(format: text.waitFormat, waitRemaining)

        rebuildReasonButtons(text.reasonTitles)
        lockedStack.isHidden = true
        requestStack.isHidden = false
        overrideButton.isHidden = true
        updateUnlockButton()
        startRequestTimer()
    }

    func update(unlockTime: Date, now: Date, recoveryFormat: String? = nil) {
        let remaining = max(0, Int(unlockTime.timeIntervalSince(now)))
        countdownLabel.stringValue = formatRemaining(remaining)
        if let recoveryFormat {
            recoveryLabel.stringValue = String(format: recoveryFormat, formatClock(unlockTime))
        }
    }

    func showOverlay() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
    }

    func hideOverlay() {
        requestTimer?.invalidate()
        requestTimer = nil
        orderOut(nil)
    }

    private func rebuildReasonButtons(_ reasons: [(reason: NightOverrideReason, title: String)]) {
        for view in reasonStack.arrangedSubviews {
            reasonStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for entry in reasons {
            let button = NSButton(title: entry.title, target: self, action: #selector(reasonClicked(_:)))
            button.bezelStyle = .rounded
            button.setButtonType(.toggle)
            button.tag = NightOverrideReason.allCases.firstIndex(of: entry.reason) ?? 0
            reasonStack.addArrangedSubview(button)
        }
    }

    private func startRequestTimer() {
        requestTimer?.invalidate()
        requestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.waitRemaining = max(0, self.waitRemaining - 1)
            self.updateUnlockButton()
            if self.waitRemaining == 0 {
                timer.invalidate()
                self.requestTimer = nil
            }
        }
    }

    private func updateUnlockButton() {
        if waitRemaining > 0 {
            waitLabel.stringValue = String(format: waitFormat, waitRemaining)
            unlockButton.title = String(format: waitFormat, waitRemaining)
            unlockButton.isEnabled = false
        } else {
            waitLabel.stringValue = unlockTitle
            unlockButton.title = unlockTitle
            unlockButton.isEnabled = selectedReason != nil && confirmationField.stringValue == expectedConfirmation
        }

        mismatchLabel.isHidden = confirmationField.stringValue.isEmpty || confirmationField.stringValue == expectedConfirmation
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private func formatClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    @objc private func overrideClicked() {
        nightDelegate?.didRequestNightOverride()
    }

    @objc private func reasonClicked(_ sender: NSButton) {
        guard NightOverrideReason.allCases.indices.contains(sender.tag) else { return }
        selectedReason = NightOverrideReason.allCases[sender.tag]

        for case let button as NSButton in reasonStack.arrangedSubviews {
            button.state = button == sender ? .on : .off
        }

        updateUnlockButton()
    }

    @objc private func cancelOverrideClicked() {
        guard let request else { return }
        nightDelegate?.didCancelNightOverride(request: request)
    }

    @objc private func unlockOverrideClicked() {
        guard let request, let selectedReason else { return }
        guard waitRemaining == 0, confirmationField.stringValue == expectedConfirmation else {
            updateUnlockButton()
            return
        }

        nightDelegate?.didGrantNightOverride(reason: selectedReason, request: request)
    }

    override var canBecomeKey: Bool {
        true
    }
}

extension NightRestrictionOverlayWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        updateUnlockButton()
    }
}

private final class NoPasteTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let characters = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command), characters == "v" {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
