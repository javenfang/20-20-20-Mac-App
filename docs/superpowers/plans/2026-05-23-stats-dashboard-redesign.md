# Statistics Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a protection-focused statistics dashboard with app-exit, temporary-disable, night-boundary, seven-day, and month-switching visibility.

**Architecture:** Keep session metrics in the existing `sessions` table and add a long-lived event statistics layer in SQLite. `StatsEngine` accepts session records plus normalized event records and emits day, week, and month snapshots. The AppKit dashboard renders a verdict-first layout, a compact seven-day list, and a month calendar without becoming a full activity tracker.

**Tech Stack:** SwiftPM, Swift, AppKit, SQLite3, XCTest, existing localization resources.

---

### Task 1: Extend Core Stats Model

**Files:**
- Modify: `Sources/TwentyGuardCore/StatsEngine.swift`
- Modify: `Sources/TwentyGuardCore/StatsHealthVerdict.swift`
- Test: `Tests/TwentyGuardCoreTests/StatsEngineTests.swift`
- Test: `Tests/TwentyGuardCoreTests/StatsHealthVerdictTests.swift`

- [x] Add `StatsEventType` and `StatsEventRecord` for app lifecycle, temporary disable, and night override events.
- [x] Expand `StatsDaySnapshot` with app-exit, app-off, temporary-disable, and night-override counters.
- [x] Add `StatsMonthSnapshot` with month days, active days, healthy days, exception days, aggregate completion rate, and month navigation metadata.
- [x] Update health verdict priority so clear protection bypasses can surface before normal rhythm.
- [x] Add failing tests for app exit pairing, temporary disable duration, night override aggregation, month boundaries, and protection-bypass verdicts.
- [x] Implement the minimal model logic until tests pass.

### Task 2: Persist Long-Lived Stats Events

**Files:**
- Modify: `Sources/TwentyGuard/StatsDatabase.swift`
- Modify: `Sources/TwentyGuard/EventRecorder.swift`

- [x] Add `stats_events` table with `event_type`, `timestamp`, optional `duration_seconds`, optional `end_timestamp`, optional `night_key`, and JSON context.
- [x] Add indexes for timestamp, event type, and night key.
- [x] Add `recordStatsEvent(...)`, event query helpers, `getDashboardSnapshot(...)`, and `getMonthSnapshot(...)` paths that pass events into `StatsEngine`.
- [x] Update `EventRecorder` so app launch/termination, temporary disable, and night override events write both SQLite stats events and JSONL logs.
- [x] Update cleanup so long-lived stats events retain the same long horizon as session statistics.

### Task 3: Rework Dashboard UI

**Files:**
- Modify: `Sources/TwentyGuard/StatsDashboardWindow.swift`

- [x] Render today verdict plus three cards: break discipline, exception behavior, and night boundary.
- [x] Add seven-day rows with compact exception markers.
- [x] Add a month section with previous/next buttons, month summary, calendar grid, and selected-day detail.
- [x] Keep layout scrollable and fixed-width enough to avoid text overlap.
- [x] Avoid adding detailed app/category/activity tracking.

### Task 4: Localization and Documentation

**Files:**
- Modify: `Sources/TwentyGuardCore/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/ja.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/ko.lproj/Localizable.strings`
- Modify: `Sources/TwentyGuardCore/Resources/es.lproj/Localizable.strings`
- Modify: `Tests/TwentyGuardCoreTests/AppLocalizationTests.swift`
- Modify: `Info.plist`
- Modify: `Sources/TwentyGuard/Resources/version-history.json`
- Modify: `docs/REQUIREMENTS.md`
- Modify: `docs/architecture.md`
- Modify: `CLAUDE.md`

- [x] Add localization keys for the new dashboard labels and details in all supported languages.
- [x] Add localization completeness tests for the new statistics keys.
- [x] Bump app version because this is a user-visible behavior and UI change.
- [x] Update requirements, architecture, and release history to describe the new statistics model.

### Task 5: Verification

**Commands:**
- `swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --scratch-path .build`
- `make build-app`
- `make verify-app-bundle`
- `make install`
- `make launch`

- [x] Run the full Swift test suite.
- [x] Build and verify the app bundle.
- [x] Install and launch the local app.
- [x] Confirm the installed app reports the bumped version.
