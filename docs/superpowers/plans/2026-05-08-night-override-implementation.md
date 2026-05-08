# Night Override Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the Night Screen Lock testing escape with a formal 30-minute Night Override flow that has escalating friction, persistence, logging, localization, tests, and versioned documentation.

**Architecture:** Keep schedule decisions in `NightRestrictionPolicy` and add `NightOverridePolicy` in `TwentyGuardCore` for override cost, reason, night key, and active-state behavior. The App target owns overlay presentation, UserDefaults persistence, JSONL event logging, and the health-report summary.

**Tech Stack:** SwiftPM, Swift, AppKit, XCTest, JSONL logs, UserDefaults, existing Makefile build pipeline.

---

### Task 1: Core Policy

**Files:**
- Create: `Sources/TwentyGuardCore/NightOverridePolicy.swift`
- Create: `Tests/TwentyGuardCoreTests/NightOverridePolicyTests.swift`
- Modify: `Sources/TwentyGuardCore/NightRestrictionPolicy.swift`
- Modify: `Tests/TwentyGuardCoreTests/NightRestrictionPolicyTests.swift`

- [x] Write failing tests for override wait durations, unlock duration, confirmation sentences, active-state expiry, and after-midnight night key.
- [x] Run `swift test --filter NightOverridePolicyTests` and confirm failures because the type does not exist.
- [x] Add `NightOverrideReason`, `NightOverrideRequest`, `NightOverrideState`, and `NightOverridePolicy`.
- [x] Remove `testingExitEnabled` from `NightRestrictionSettings`.
- [x] Rename the existing `disabledUntil` parameter to `overrideUntil` while preserving behavior.
- [x] Update existing night restriction tests to use the formal override name.
- [x] Run `swift test --filter NightOverridePolicyTests` and `swift test --filter NightRestrictionPolicyTests`.

### Task 2: Overlay Flow

**Files:**
- Modify: `Sources/TwentyGuard/NightRestrictionOverlayWindow.swift`

- [x] Replace `didRequestNightTestingExit()` with formal override delegate callbacks for request, cancel, and grant.
- [x] Replace the single testing button with a locked state and an override request state.
- [x] Add reason buttons, countdown label, confirmation sentence label, text input, mismatch label, cancel button, and unlock button.
- [x] Disable paste and only enable unlock when reason is selected, countdown has ended, and input exactly matches the expected sentence.
- [x] Add configuration methods that accept localized labels and `NightOverrideRequest`.
- [x] Keep all layout inside the existing full-screen overlay.

### Task 3: App Wiring and Persistence

**Files:**
- Modify: `Sources/TwentyGuard/AppDelegate.swift`
- Modify: `Sources/TwentyGuard/LogManager.swift`
- Modify: `Sources/TwentyGuard/EventRecorder.swift`

- [x] Replace `nightLockOverrideUntil` and testing-exit settings with `nightOverrideState` and stored override keys.
- [x] Persist active override state in UserDefaults and clear it when expired.
- [x] Record `night_override_requested`, `night_override_granted`, `night_override_cancelled`, and `night_override_expired` JSONL events.
- [x] Use `NightOverridePolicy` to create override requests and grant 30-minute overrides.
- [x] Update the menu/status timer to show active override remaining time.
- [x] Remove testing-exit menu configuration and settings logging.

### Task 4: Health Report Summary

**Files:**
- Modify: `Sources/TwentyGuard/LogManager.swift`
- Modify: `Sources/TwentyGuard/StatsDashboardWindow.swift`

- [x] Add a small `NightOverrideSummary` model based on JSONL events.
- [x] Read last night's granted overrides from local logs.
- [x] Display `statsNightNoOverride` or `statsNightOverrideFormat` in the existing Night metric detail.
- [x] Keep the UI to a one-line summary and avoid adding trend charts.

### Task 5: Localization, Version, Docs

**Files:**
- Modify: `Sources/TwentyGuardCore/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/es.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/ja.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/ko.lproj/Localizable.strings`
- Modify: `Info.plist`
- Modify: `Sources/TwentyGuard/Resources/version-history.json`
- Modify: `docs/REQUIREMENTS.md`
- Modify: `docs/architecture.md`
- Modify: `CLAUDE.md`

- [x] Remove user-facing `nightTestingExit*` localization keys.
- [x] Add `nightOverride*` and `statsNightOverride*` keys in all five languages.
- [x] Bump app version from `1.5.3` to `1.5.4`.
- [x] Update version history and durable docs for the formal Night Override.

### Task 6: Verification and Local Install

**Files:**
- Verify only.

- [x] Run `swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --scratch-path .build`.
- [x] Run `make build-app`.
- [x] Run `make install`.
- [x] Run `make launch`.
- [x] Verify `/Applications/TwentyGuard.app` launches and reports version `1.5.4`.
- [x] Commit implementation changes.
