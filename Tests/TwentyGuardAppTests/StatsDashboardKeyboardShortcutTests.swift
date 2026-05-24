import AppKit
import XCTest
@testable import TwentyGuard

final class StatsDashboardKeyboardShortcutTests: XCTestCase {
    func testCommandWClosesStatsDashboardWindow() {
        let event = keyEvent(character: "w", keyCode: 13)

        XCTAssertTrue(StatsDashboardKeyboardShortcut.isCloseWindowEvent(event))
    }

    func testCommandCActivatesCloseButtonShortcut() {
        let event = keyEvent(character: "c", keyCode: 8)

        XCTAssertEqual(StatsDashboardKeyboardShortcut.closeButtonKeyEquivalent, "c")
        XCTAssertEqual(StatsDashboardKeyboardShortcut.closeButtonModifierMask, .command)
        XCTAssertTrue(StatsDashboardKeyboardShortcut.isCloseWindowEvent(event))
    }

    func testCloseButtonReceivesCommandCKeyEquivalent() {
        let button = NSButton()

        StatsDashboardKeyboardShortcut.configureCloseButton(button)

        XCTAssertEqual(button.keyEquivalent, "c")
        XCTAssertEqual(button.keyEquivalentModifierMask, .command)
    }

    func testPlainCDoesNotCloseStatsDashboardWindow() {
        let event = keyEvent(character: "c", keyCode: 8, modifierFlags: [])

        XCTAssertFalse(StatsDashboardKeyboardShortcut.isCloseWindowEvent(event))
    }

    private func keyEvent(
        character: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = .command
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
