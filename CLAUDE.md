# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 🤖 AI Coding Assistant Principles

1. **AI Coding First** - Leverage AI assistance throughout the development lifecycle
2. **CLAUDE.md Persists English Version** - Maintain documentation in English for broader accessibility
3. **Architecture Design Principle: KISS** - Keep It Simple, Stupid


---

## Project Overview

**TwentyGuard** - A native macOS menu bar application implementing strict 20-20-20 eye breaks, custom work rhythms, health statistics, postpone limits, and optional night screen lock.

**Implementation Status**: ✅ **COMPLETE** - Fully implemented and ready for production use.

**Key Features**: Work/break cycles, postpone limits, health statistics, night screen lock, multi-language support, smart system event response

📖 **Detailed Features**: See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)

## 🎯 jstudio Role Boundary

When working with this repository on **jstudio**, TwentyGuard should be treated as
a **marketing workspace**, not a code-writing workspace.

**Primary responsibilities on jstudio**:
- Product positioning and audience definition
- Launch planning and channel strategy
- Website, release, and announcement copy
- Screenshots, visuals, and marketing asset coordination
- User-facing messaging, FAQ, and distribution materials

**Do not assume engineering ownership on jstudio**:
- Do not take on Swift/AppKit implementation work by default
- Do not edit source code, change build/release logic, or run deployment-style workflows unless the user explicitly overrides this boundary
- Keep code-level inspection limited to context gathering when it directly supports marketing accuracy

## 🎯 Core Design Decisions

**These are key design principles that have been clearly established and should not be repeatedly questioned:**

### 1. Behavior After System Wake ⭐ (v1.1.0)
> **Regardless of previous state, always start a fresh work cycle after any system wake event**

**Rationale**:
- Screensaver/sleep/lid close already provides eye rest
- Users should start fresh to avoid "just opened, already need break" experience

**Trigger Events**: System sleep, screen lock, screensaver, display sleep, lid close

### 2. Postpone Mechanism ⭐ (v1.2.0)
> **Default mode limits cumulative postpones to 5 minutes; custom mode can choose 5 or 10 minutes**

**Rationale**: Prevent users from bypassing break reminders through repeated postpones

**Implementation**: Dynamic button disabling + real-time status display

### 3. Time Calculation
> **Use absolute time instead of relative counting**

**Rationale**: Avoid cumulative errors, support system sleep recovery

📖 **Complete Design Decisions**: See [docs/architecture.md](docs/architecture.md#9-key-technical-decisions)

## Architecture

**Native macOS Application** built with Swift and AppKit:
- Menu Bar Application with comprehensive menu system
- Full-Screen Break Overlay (multi-monitor support)
- SQLite + JSON dual-layer data persistence
- 5 languages support with runtime switching
- Smart session recovery after sleep/screensaver

📖 **Detailed Technical Architecture**: See [docs/architecture.md](docs/architecture.md)
- Component relationship diagrams, data flow, timing mechanism details
- Event handling system, persistence solutions
- Complete maintenance guide and troubleshooting

## 🏗️ Project Structure

**Single Project Architecture** (Swift Package Manager):
- Location: `/Users/javenfang/Projects/TwentyGuard/`
- Historical local symlink may exist: `/Users/javenfang/Projects/20-20-20 -> TwentyGuard`
- No Xcode project files needed, everything managed via Makefile
- Core Files: AppDelegate.swift, BreakOverlayWindow.swift, EventRecorder.swift, StatsDatabase.swift

📖 **Complete File Documentation**: See [docs/architecture.md](docs/architecture.md#13-project-structure)

---

## 📚 Documentation Navigation

**This Document**: Quick development guide with **build process and critical development notes**.

**Current Implementation Docs**:
- **[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)** - Functional requirements: complete feature list and user scenarios
- **[docs/architecture.md](docs/architecture.md)** - Technical architecture: in-depth implementation details and maintenance guide

Historical PRDs, implementation plans, and old bug-fix records have been removed. Keep durable product and architecture decisions in the two current docs above.

## 🚀 Standardized Build Process

### ⚠️ Important Notice
**This project has ONE standard build process managed via Makefile. Do not use other build methods to avoid version confusion.**

### Standard Build Commands

#### 1. Development & Debugging
```bash
cd /Users/javenfang/Projects/TwentyGuard/
make run        # Run development version directly (swift run)
```

#### 2. Build App Bundle
```bash
make build-app  # Build .app bundle to build/TwentyGuard.app
                # This is the ONLY standard build output location
```

#### 3. Install to Applications
```bash
make install    # Auto-execute: Build → Kill old process → Install to /Applications/
make launch     # Launch version in /Applications/
```

### 🚫 Forbidden Operations
- **DO NOT** create .app files in project root directory
- **DO NOT** build directly with Xcode (project has no .xcodeproj file)
- **DO NOT** manually copy .app to other locations
- **DO NOT** run multiple versions of the app simultaneously

### 📁 Standard Directory Structure
```
TwentyGuard/
├── build/              # ONLY build output directory
│   └── TwentyGuard.app # make build-app output
├── .build/            # Swift build intermediate files (auto-generated)
└── Sources/           # Source code
```

### 🔄 Complete Workflow
```bash
# Standard process after code modification
make build-app  # Step 1: Build new version
make install    # Step 2: Install to Applications
make launch     # Step 3: Launch new version
```

**⚠️ Important Notes:**
- **build/ directory** is the ONLY build output location
- **All builds MUST go through Makefile** to ensure consistency
- **Avoid version confusion**: Always use `make install` to update Applications version

## 🔧 Maintenance Notes

### Development Workflow
- **Source of Truth**: Swift Package Manager project (`/Users/javenfang/Projects/TwentyGuard/`)
- **Build Management**: All builds unified through Makefile
- **Asset Management**: Resource files centrally managed in Sources/ directory
- **Completion Default**: After finishing a requested code/app change, verifying it, and updating the local install when relevant, commit and push automatically unless the user explicitly says not to.

### Version Discipline
- **Every user-visible app adjustment MUST bump the app version in the same change set.**
- Treat feature work, in-app UI copy changes, localization changes, icon/resource changes, behavior changes, packaging changes, and release artifact changes as versioned changes.
- Pure README / marketing copy cleanup does not require a new app version if it does not change app behavior, bundled resources, release artifacts, or recorded release facts.
- For each versioned change, update all version sources together:
  - `Info.plist`: `CFBundleShortVersionString` and `CFBundleVersion`
  - `Sources/TwentyGuard/Resources/version-history.json`: `current_version` and newest history entry
  - `docs/REQUIREMENTS.md` and `docs/architecture.md`: document version and version history
  - `CLAUDE.md`: distribution readiness version when the app version changes
- Do not leave code/resource/doc changes at the previous app version. If the change is worth building, installing, packaging, or releasing, it needs a new patch/minor version.

### 📦 Release Checklist

**⚠️ MUST check before every new release:**

1. **Update Version History File**: [Sources/TwentyGuard/Resources/version-history.json](Sources/TwentyGuard/Resources/version-history.json)
   - Update `current_version` field (e.g., "1.2.0")
   - Add new version record at **beginning** of `versions` array
   - Include: version number, date (YYYY-MM-DD), major changes list
   - Keep versions in reverse chronological order (newest first)

2. **Verify About Page**:
   ```bash
   make install && make launch
   # Click menu bar → About → Confirm version info is correct
   ```

3. **Verify App Bundle Structure**:
   ```bash
   make build-app
   make verify-app-bundle
   ```
   This must confirm the standard `Contents/Info.plist`, `Contents/PkgInfo`,
   `Contents/MacOS/TwentyGuard`, runtime resources, SwiftPM resource bundles,
   localization files, and code signature layout. Do not ship an app bundle that
   contains `.DS_Store`, source `.xcassets` directories, or SwiftPM resource
   bundles at the `.app` root.

4. **Example Version Record**:
   ```json
   {
     "version": "1.2.0",
     "date": "2025-01-20",
     "changes": [
       "Added new feature X",
       "Fixed bug Y",
       "Improved performance Z"
     ]
   }
   ```

**Why Important**: version-history.json is the ONLY data source for the About page. Forgetting to update will show outdated version info to users.

### 🚨 Critical Update Process
**Required steps after every code modification:**

1. **Development & Testing**:
   ```bash
   make build && make run  # Test development version
   ```

2. **Update Applications Version** (REQUIRED):
   ```bash
   make install  # One-command replace Applications version
   make launch   # Launch new version
   ```

### 📊 Statistics Debugging Checklist

**⚠️ Important: When debugging statistics issues, ALWAYS check JSONL log files first!**

JSONL is the source of truth for event records; database is the query optimization layer. Any statistics issues should start investigation from JSONL.

**Data reset note**: TwentyGuard intentionally does **not** migrate old `20-20-20` local data. Statistics, JSONL logs, and session recovery now start fresh under `~/Library/Application Support/com.javengroup.twentyguard/`.

**When statistics window shows no data, check in this order:**

1. **First Check JSONL Files** (are events recorded):
   ```bash
   cat ~/Library/Application\ Support/com.javengroup.twentyguard/logs/$(date +%Y-%m-%d).jsonl | jq -r '.eventType' | sort | uniq -c
   ```
   Should see: `work_started`, `break_started`, `work_completed`, `break_completed` events

   For session lifecycle bugs, inspect `session_debug` actions as well:
   ```bash
   cat ~/Library/Application\ Support/com.javengroup.twentyguard/logs/$(date +%Y-%m-%d).jsonl \
     | jq 'select(.eventType == "session_debug")'
   ```

2. **Check sessions Table** (is data written to database):
   ```bash
   sqlite3 ~/Library/Application\ Support/com.javengroup.twentyguard/twentyguard_stats.db \
     "SELECT COUNT(*) FROM sessions WHERE date(start_time, 'unixepoch') = date('now');"
   ```
   Should return today's session count (> 0)

3. **Check Table Schema** (confirm field names are correct):
   ```bash
   sqlite3 ~/Library/Application\ Support/com.javengroup.twentyguard/twentyguard_stats.db \
     "PRAGMA table_info(sessions);"
   ```
   Confirm existence of fields: `postpones` (JSON), `break_info` (JSON), `actual_work_duration`

**Key Points**:
- New version uses JSON fields (`postpones`, `break_info`), not separate `postpone_1min` columns
- StatsDatabase query methods MUST parse JSON instead of direct column queries
- `type` field only has value `'work'`, break info is in JSON

### 🐛 Quick Troubleshooting

**Symptom: Countdown inaccurate or version confusion**
- **Solution**: `make install` to reinstall latest version

**Symptom: Postpone functionality abnormal**
- **Check**: Postpone logic should NOT modify `currentWorkDuration`

📖 **Complete Troubleshooting**: See [docs/architecture.md](docs/architecture.md#101-common-issues)
- Detailed symptom analysis and solutions
- Log viewing methods and database check commands
- Performance monitoring metrics

## 📱 Distribution Readiness

- ✅ **Bundle ID**: `com.javengroup.twentyguard`
- ✅ **App Name**: "TwentyGuard"
- ✅ **Version**: 1.7.6
- ✅ **Minimum macOS**: 12.0
- ⚠️ **Development Signing**: `make build-app` uses ad-hoc signing for local install/test only
- ⚠️ **Public Direct Download**: latest verified public DMG is v1.5.3; v1.7.6 must run `make release` before upload
- ✅ **Size**: ~1.3MB (extremely lightweight)

For direct distribution outside the Mac App Store, Apple requires the app to be
signed with a Developer ID certificate and submitted for notarization. The
release path is configured for the Shenzhen Lifangjuzhen team:

```bash
# One-time setup after installing the Developer ID Application certificate.
make notary-store-credentials APPLE_ID=<apple-id-email> TEAM_ID=MDQ5F44RU5

# Per release.
make release \
  TEAM_ID=MDQ5F44RU5 \
  DEVELOPER_ID_APPLICATION="Developer ID Application: Shenzhen Lifangjuzhen Technology Co., Ltd. (MDQ5F44RU5)"
```

`make release` builds the versioned `dist/TwentyGuard-v<version>.dmg`, signs the app and DMG,
submits the DMG for notarization, staples the ticket, and verifies Gatekeeper.
Do not upload a `make dmg` output as the public release artifact unless it has
also gone through the Developer ID notarization path.

Latest verified public release artifact:
- **Path**: `dist/TwentyGuard-v1.5.3.dmg`
- **Notary submission**: `691c1c24-24ca-45ba-a7da-efe7a36e13fe`
- **Gatekeeper**: accepted, source `Notarized Developer ID`
- **SHA-256**: `322364e11c50a8ac7bccf71cceeeb136ff0bca338fb077b3664e53511be355cc`
