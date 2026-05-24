# TwentyGuard - 技术架构文档

> **文档版本**: v1.7.6
> **最后更新**: 2026-05-24
> **维护者**: Javen Fang (@javenfang)

---

## 📚 文档导航

**本文档**: 深入的技术架构和实现细节，适合**维护开发者和架构师**阅读。

**其他文档**:
- **[CLAUDE.md](../CLAUDE.md)** - 开发快速入口：构建流程、关键注意事项
- **[REQUIREMENTS.md](REQUIREMENTS.md)** - 功能需求文档：用户功能和使用场景

**何时阅读本文档**:
- ✅ 需要深入理解计时机制、状态管理、数据流
- ✅ 需要排查复杂问题（会话恢复、多屏幕管理等）
- ✅ 需要修改核心架构或添加新功能
- ✅ 需要优化性能或数据库设计

**快速查找**:
- 计时机制 → [第4章](#4-计时机制)
- 事件处理 → [第5章](#5-事件处理系统)
- 数据持久化 → [第6章](#6-持久化方案)
- 问题排查 → [10.1 常见问题排查](#101-常见问题排查)
- 数据库检查 → [10.3 数据库检查](#103-数据库检查)

---

## 📋 目录

- [1. 架构概览](#1-架构概览)
- [2. 核心组件](#2-核心组件)
- [3. 数据流与状态管理](#3-数据流与状态管理)
- [4. 计时机制](#4-计时机制)
- [5. 事件处理系统](#5-事件处理系统)
- [6. 持久化方案](#6-持久化方案)
- [7. 国际化系统](#7-国际化系统)
- [8. 构建与部署](#8-构建与部署)
- [9. 关键技术决策](#9-关键技术决策)
- [10. 维护指南](#10-维护指南)

---

## 1. 架构概览

### 1.1 整体架构

20-20-20 采用 **单一进程、事件驱动** 的原生 macOS 应用架构：

```mermaid
graph TB
    subgraph "应用层"
        A[AppDelegate<br/>核心控制器] --> B[BreakOverlayWindow<br/>休息提醒窗口]
        A --> C[StatsDashboardWindow<br/>统计窗口]
        A --> N[NightRestrictionOverlayWindow<br/>夜间锁定遮罩]
    end

    subgraph "数据层"
        D[EventRecorder<br/>事件记录器] --> E[StatsDatabase<br/>SQLite存储]
        D --> F[LogManager<br/>JSON日志]
    end

    subgraph "系统层"
        G[NSStatusBar<br/>菜单栏] --> A
        H[NSWorkspace<br/>系统通知] --> A
        I[UserDefaults<br/>用户设置] --> A
    end

    A --> D
    B -.委托.-> A
    C -.委托.-> A

    style A fill:#e1f5ff
    style D fill:#fff4e1
    style E fill:#e8f5e9
    style F fill:#e8f5e9
```

### 1.2 技术栈

- **语言**: Swift 5.9+
- **框架**: AppKit (原生 macOS UI)
- **构建系统**: Swift Package Manager
- **数据库**: SQLite3
- **最低系统**: macOS 12.0+

### 1.3 项目结构

```
Sources/TwentyGuard/
├── main.swift                    # 入口点
├── AppDelegate.swift             # 主控制器 (1573行)
├── BreakOverlayWindow.swift      # 全屏休息窗口 (477行)
├── EventRecorder.swift           # 事件记录器 (231行)
├── StatsDatabase.swift           # SQLite数据库 (716行)
├── LogManager.swift              # JSON日志 (373行)
├── StatsDashboardWindow.swift    # 当前健康统计窗口
├── HealthAnalyzer.swift          # 健康分析 (未使用)
└── Resources/                    # 资源文件
    ├── statusbar_icon.png        # 16x16 菜单栏图标
    └── statusbar_icon@2x.png     # 32x32 Retina图标
```

---

## 2. 核心组件

### 2.1 AppDelegate - 主控制器

**文件**: [`AppDelegate.swift`](../Sources/TwentyGuard/AppDelegate.swift)

**职责**:
- 应用生命周期管理
- 计时器调度 (工作/休息/推迟)
- 菜单栏UI管理
- 系统事件响应
- 会话状态管理
- 临时禁用 1 小时状态管理
- 夜间禁用和正式破例状态管理

**关键设计**:
- 使用三种 Timer：工作/休息/状态快照
- 使用绝对时间 `Date` 记录会话开始时间
- 通过计算属性实时计算剩余时间（避免累积误差）
- ⭐ v1.2.0 更新：默认模式推迟总计最多 5 分钟，自定义模式可选 5/10 分钟
- ⭐ v1.5.4 更新：夜间禁用移除测试出口，改为带等待、原因和确认句的正式破例流程
- ⭐ v1.5.5 修复：推迟休息状态持久化，应用重启后不再误开新工作周期
- ⭐ v1.6.0 新增：会议等特殊场合可临时禁用 1 小时，但夜间禁用和夜间破例优先
- ⭐ v1.7.0 新增：健康统计改为保护遵守视角，长期统计 App 退出、临时禁用和夜间破例，并提供月度切换视图
- ⭐ v1.7.1 调整：统计窗口顶部拆分「概览 / 月度」tab，月度切换只刷新月度页内容
- ⭐ v1.7.2 修复：推迟休息统计记录到当前未完成休息所属的 work session，而不是只查 active work session
- ⭐ v1.7.3 修复：推迟到期会关闭 active postpone，完成欠下休息会完成同一 break opportunity；新工作周期会中断未闭合 break/postpone，数据质量会显示异常 session ID
- ⭐ v1.7.4 调整：统计窗口直接处理 ⌘W 关闭，右下角 Close 按钮配置 ⌘C key equivalent
- ⭐ v1.7.5 修复：恢复同一 work session 时复用 active row，统计层忽略同开始时间恢复副本，避免不可能的超长工作污染完成率
- ⭐ v1.7.6 诊断增强：新增 `session_debug` JSONL 事件，串联 AppDelegate 会话恢复、系统事件和 StatsDatabase 会话闭合动作

📖 **详细实现**: [`AppDelegate.swift:54-86`](../Sources/TwentyGuard/AppDelegate.swift#L54-L86)

### 2.2 BreakOverlayWindow - 休息提醒窗口

**文件**: [`BreakOverlayWindow.swift`](../Sources/TwentyGuard/BreakOverlayWindow.swift)

**职责**:
- 全屏模态窗口显示
- 倒计时展示
- 推迟按钮处理
- 全局键盘监听 (⌘1/⌘2/⌘5)
- 多屏幕支持

**窗口层级**: `.screenSaver` (高于其他应用)

**关键特性**:
- 支持多显示器（每个屏幕一个窗口实例）
- ⭐ v1.1.0 更新：底部显示推迟状态（已推迟X分钟，剩余Y分钟）
- ⭐ v1.1.0 更新：根据剩余时间动态禁用推迟按钮
- 使用网格布局实现冒号对齐 ([`BreakOverlayWindow.swift:98-180`](../Sources/TwentyGuard/BreakOverlayWindow.swift#L98-L180))
- 全局键盘事件监听，无需窗口焦点 ([`BreakOverlayWindow.swift:310-332`](../Sources/TwentyGuard/BreakOverlayWindow.swift#L310-L332))
- 通过委托模式通知 AppDelegate 处理推迟请求

### 2.3 NightRestrictionPolicy / NightOverridePolicy - 夜间边界

**文件**:
- [`NightRestrictionPolicy.swift`](../Sources/TwentyGuardCore/NightRestrictionPolicy.swift)
- [`NightOverridePolicy.swift`](../Sources/TwentyGuardCore/NightOverridePolicy.swift)
- [`NightRestrictionOverlayWindow.swift`](../Sources/TwentyGuard/NightRestrictionOverlayWindow.swift)

**职责**:
- 计算夜间收紧、完全禁用和恢复可用的时间段
- 根据当前夜间阶段调整工作周期上限
- 在完全禁用阶段显示多屏全屏遮罩
- 管理正式破例：等待成本、原因、确认句、30 分钟解锁窗口

**正式破例规则**:
- 第 1 次破例等待 60 秒，第 2 次等待 90 秒，第 3 次及以后等待 120 秒
- 每次破例只解锁 30 分钟
- 破例必须选择原因，并逐字输入本地化确认句；确认输入禁止粘贴
- 活跃破例保存到 UserDefaults，重启后仍按剩余时间生效
- 破例请求、授权、取消、到期写入 JSONL 日志

### 2.4 EventRecorder - 事件记录器

**文件**: [`EventRecorder.swift`](../Sources/TwentyGuard/EventRecorder.swift)

**职责**:
- 统一事件记录入口
- 协调 SQLite 长期统计事件和 JSONL 调试日志
- 会话状态管理
- 数据清理调度

**双重记录系统**:
```mermaid
graph LR
    A[EventRecorder] --> B[StatsDatabase<br/>SQLite sessions + stats_events]
    A --> C[LogManager<br/>JSONL日志]

    B --> D[长期统计数据<br/>90天]
    C --> E[调试日志<br/>30天]

    style A fill:#fff4e1
    style B fill:#e8f5e9
    style C fill:#e8f5e9
```

**关键方法**:
- `startWorkSession(duration:)` - 开始工作会话
- `startBreakSession(duration:)` - 开始休息会话
- `recordPostpone(minutes:)` - 记录推迟事件
- 推迟到期重新进入休息时，会关闭 active postpone；完成休息时，会把同一 work session 的 `break_info` 标记为 completed
- 新 work session 开始前会中断遗留的 active break/postpone，避免历史 active 记录继续污染数据质量
- `recordNightOverrideRequested(...)` / `recordNightOverrideGranted(...)` - 记录夜间破例事件
- `getTodayStats()` - 获取今日统计

### 2.5 StatsDatabase - SQLite存储

**文件**: [`StatsDatabase.swift`](../Sources/TwentyGuard/StatsDatabase.swift)

**职责**:
- 会话数据持久化
- 长期统计事件持久化
- 今日、近 7 天、月度统计聚合
- 数据查询与清理

**数据库表结构**:

```sql
-- 会话记录表
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT CHECK(type IN ('work')) NOT NULL,
    start_time REAL NOT NULL,
    end_time REAL,
    status TEXT CHECK(status IN ('active', 'completed', 'interrupted')) DEFAULT 'active',
    planned_duration INTEGER DEFAULT 1800,
    actual_work_duration INTEGER,
    postpone_count INTEGER DEFAULT 0,
    postpone_total_duration INTEGER DEFAULT 0,
    postpones TEXT,
    break_info TEXT,
    break_completed INTEGER DEFAULT 0,
    created_at REAL DEFAULT (strftime('%s', 'now'))
);

-- 长期统计事件表
CREATE TABLE stats_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    timestamp REAL NOT NULL,
    duration_seconds INTEGER,
    end_timestamp REAL,
    night_key TEXT,
    context TEXT,
    created_at REAL DEFAULT (strftime('%s', 'now'))
);
```

**数据库文件位置**:
```
~/Library/Application Support/com.javengroup.twentyguard/twentyguard_stats.db
```

### 2.6 LogManager - JSON日志

**文件**: [`LogManager.swift`](../Sources/TwentyGuard/LogManager.swift)

**职责**:
- 结构化日志记录 (JSONL格式)
- 会话状态序列化
- 应用崩溃恢复

**日志文件位置**:
```
~/Library/Application Support/com.javengroup.twentyguard/logs/
├── 2025-10-31.jsonl       # 每日日志
├── 2025-10-30.jsonl
└── current_session.json   # 当前会话状态
```

**日志事件类型** ([`LogManager.swift:11-38`](../Sources/TwentyGuard/LogManager.swift#L11-L38)):
- 工作/休息周期: `work_started`, `work_completed`, `break_started`, etc.
- 系统事件: `system_sleep`, `screensaver_start`, etc.
- 应用事件: `app_launched`, `settings_changed`, etc.
- 夜间破例: `night_override_requested`, `night_override_granted`, `night_override_cancelled`, `night_override_expired`
- 临时禁用: `temporary_disable_started`, `temporary_disable_ended`, `temporary_disable_expired`

---

## 3. 数据流与状态管理

### 3.1 工作-休息周期

```mermaid
stateDiagram-v2
    [*] --> 工作中
    工作中 --> 休息中: 工作时间到
    工作中 --> 推迟中: 用户推迟
    推迟中 --> 休息中: 推迟时间到
    休息中 --> 工作中: 休息时间到
    休息中 --> 推迟中: 用户推迟

    工作中: workSessionStartTime ≠ nil
    休息中: breakSessionStartTime ≠ nil
    推迟中: postponeStartTime ≠ nil
```

**状态转换代码路径**:
1. **启动** → `applicationDidFinishLaunching` ([`AppDelegate.swift:233`](../Sources/TwentyGuard/AppDelegate.swift#L233))
   - 尝试恢复会话 (`restoreSessionIfNeeded`)
   - 失败则启动新工作会话 (`startWorkTimer`)

2. **工作完成** → `completeWorkSession` ([`AppDelegate.swift:1005`](../Sources/TwentyGuard/AppDelegate.swift#L1005))
   - 记录工作时长
   - 显示休息窗口 (`showBreakOverlay`)

3. **休息完成** → `completeBreakSession` ([`AppDelegate.swift:1258`](../Sources/TwentyGuard/AppDelegate.swift#L1258))
   - 清理休息窗口
   - 重置推迟次数
   - 启动新工作会话

4. **推迟请求** → `postponeBreak` ([`AppDelegate.swift:1301`](../Sources/TwentyGuard/AppDelegate.swift#L1301))
   - 清理休息窗口
   - 设置推迟计时器
   - 推迟时间到后重新显示休息窗口

### 3.2 重入保护机制

**问题**: 计时器可能在短时间内多次触发完成逻辑

**解决方案**: 使用布尔标志防止重入 ([`AppDelegate.swift:48-50`](../Sources/TwentyGuard/AppDelegate.swift#L48-L50))
- `isCompletingWorkSession` / `isCompletingBreakSession` 标志
- 进入完成逻辑前检查标志，执行中设置为 `true`，完成后重置为 `false`

### 3.3 多屏幕窗口管理

**问题**: 用户可能有多个显示器，需要在所有屏幕上显示休息窗口

**解决方案** ([`AppDelegate.swift:1164-1224`](../Sources/TwentyGuard/AppDelegate.swift#L1164-L1224)):
- 遍历 `NSScreen.screens`，为每个屏幕创建独立窗口实例
- 所有窗口共享同一个委托，任一窗口的推迟按钮被点击 → 清理所有窗口
- 使用 `cleanupBreakOverlays()` 统一清理，防止窗口残留

---

## 4. 计时机制

### 4.1 绝对时间 vs 相对时间

**采用方案**: 绝对时间记录 + 实时计算

**优势**:
- ✅ 避免累积误差（每秒重新计算，而非累加）
- ✅ 支持系统睡眠/唤醒（恢复后仍可根据开始时间计算）
- ✅ 便于会话恢复（只需保存 `Date` 对象）

**核心思想**: 记录 `workSessionStartTime: Date?`，通过 `Date().timeIntervalSince(startTime)` 计算已用时间，剩余时间 = 总时长 - 已用时间。

📖 **代码实现**: [`AppDelegate.swift:54-68`](../Sources/TwentyGuard/AppDelegate.swift#L54-L68)

### 4.2 计时器调度策略

**三种计时器**:
1. **workTimer**: 工作期间每秒触发，更新UI和检查完成条件
2. **breakTimer**: 休息期间每秒触发，更新倒计时
3. **stateSnapshotTimer**: 每10秒记录状态快照

**启动时机**:
- `workTimer`: `startWorkTimer()` / `restartWorkTimer()`
- `breakTimer`: `startBreakTimer()`
- `stateSnapshotTimer`: 应用启动时 ([`AppDelegate.swift:261`](../Sources/TwentyGuard/AppDelegate.swift#L261))

**停止时机**:
- 会话完成时立即停止对应计时器
- 应用退出时停止所有计时器 ([`AppDelegate.swift:850-853`](../Sources/TwentyGuard/AppDelegate.swift#L850-L853))

### 4.3 推迟逻辑 ⭐ v1.1.0 更新

**设计原则**: 推迟是临时状态，不修改原始工作时长设置

**实现要点**:
- 使用独立的 `postponeStartTime` 和 `postponeDuration` 追踪推迟状态
- `SessionState` 持久化推迟开始时间、推迟时长和累计推迟，避免应用重启后误开新工作周期
- `currentWorkDuration` 保持不变（避免影响持久化设置）
- 推迟计时器到期后，自动重新显示休息窗口

**推迟限制机制** (v1.2.0 更新):
- **累计时长限制**: 使用 `totalPostponedTime` 追踪所有推迟操作的累计时间
- **可配置上限**: `maxTotalPostponeTime` 变量控制推迟上限
  - 默认模式: 固定 5 分钟上限
  - 自定义模式: 可选 5 分钟或 10 分钟上限
- **动态按钮禁用**:
  - 剩余时间 < 5 分钟 → "推迟 5 分钟"按钮禁用
  - 剩余时间 < 2 分钟 → "推迟 2 分钟"按钮禁用
  - 剩余时间 < 1 分钟 → "推迟 1 分钟"按钮禁用
- **实时状态显示**: 窗口底部显示 "已推迟 X 分钟，剩余可推迟 Y 分钟"
- **自动重置**: 完成休息后 `totalPostponedTime` 重置为 0

**核心代码路径**:
- 推迟请求处理: [`AppDelegate.swift:1301-1356`](../Sources/TwentyGuard/AppDelegate.swift#L1301-L1356)
- UI状态更新: `updateBreakOverlaysPostponeStatus()`
- 窗口状态更新: [`BreakOverlayWindow.swift:updatePostponeStatus()`](../Sources/TwentyGuard/BreakOverlayWindow.swift)

### 4.4 临时禁用逻辑 ⭐ v1.6.0 新增

**设计原则**: 临时禁用是会议等特殊场合的短时暂停，不修改工作/休息设置，也不绕过夜间边界。

**实现要点**:
- 使用 `TemporaryDisableState` 记录 `startedAt` 和 `until`
- `TemporaryDisablePolicy.disableSeconds` 固定为 60 分钟
- 启动后停止工作、休息、推迟计时，清理休息遮罩，并结束当前统计会话
- 菜单栏和状态栏显示临时禁用倒计时
- 到期或手动结束后清理状态，并启动新的正常工作周期
- 状态保存到 UserDefaults，应用重启后仍能继续剩余禁用时间

**夜间优先级**:
- `NightRestrictionStatus.isLocked == true` 时不可启动临时禁用
- `NightRestrictionStatus.isOverrideActive == true` 时不可启动临时禁用，避免把正式夜间破例扩展成 1 小时
- 临时禁用跨入夜间完全禁用时，`TemporaryDisablePolicy.shouldInterruptActiveDisable` 会清理临时禁用并交回夜间锁定逻辑

---

## 5. 事件处理系统

### 5.1 系统事件监听

**监听的系统通知** ([`AppDelegate.swift:538-600`](../Sources/TwentyGuard/AppDelegate.swift#L538-L600)):

**NSWorkspace 通知**:
- 系统睡眠/唤醒: `willSleepNotification`, `didWakeNotification`
- 显示器睡眠/唤醒: `screensDidSleepNotification`, `screensDidWakeNotification`

**DistributedNotificationCenter 通知**:
- 屏幕锁定/解锁: `com.apple.screenIsLocked`, `com.apple.screenIsUnlocked`
- 屏保启动/停止: `com.apple.screensaver.didstart`, `com.apple.screensaver.didstop`

### 5.2 系统事件处理策略

**核心原则**: 屏保/睡眠本身相当于休息，唤醒后应开始新的工作会话

**处理策略** ([`AppDelegate.swift:1423-1501`](../Sources/TwentyGuard/AppDelegate.swift#L1423-L1501)):

1. **屏保/睡眠/显示器睡眠** → 清理休息窗口 + 重置为新工作会话（用户已得到休息）
2. **屏幕锁定/解锁** → 根据时长决定：
   - 超时 > 5分钟 → 重置为新工作会话
   - 工作时间已到 → 显示休息窗口
   - 其他 → 继续之前的会话

### 5.3 单实例检测

**问题**: 防止用户同时运行多个应用实例

**解决方案** ([`AppDelegate.swift:264-306`](../Sources/TwentyGuard/AppDelegate.swift#L264-L306)):
- 通过 `NSWorkspace.shared.runningApplications` 查找相同可执行路径的其他进程
- 如果发现已有实例运行 → 激活现有实例 + 当前实例退出
- 比较依据: 可执行文件路径 或 Bundle ID

---

## 6. 持久化方案

### 6.1 三层持久化架构

```mermaid
graph TB
    subgraph "持久化层次"
        A[UserDefaults<br/>用户设置] --> B[即时保存]
        C[SessionState<br/>会话状态] --> D[每10秒快照]
        E[SQLite + JSONL<br/>历史数据] --> F[事件触发]
    end

    B --> G[语言/模式/时长配置]
    D --> H[崩溃恢复]
    F --> I[长期统计分析]

    style A fill:#e3f2fd
    style C fill:#fff3e0
    style E fill:#e8f5e9
```

### 6.2 UserDefaults - 用户设置

**存储内容** ([`AppDelegate.swift:390-433`](../Sources/TwentyGuard/AppDelegate.swift#L390-L433)):
- `showCountdownInStatusBar`: 是否显示倒计时
- `isCustomMode`: 是否自定义模式
- `customWorkDuration` / `customBreakDuration`: 自定义时长
- `currentLanguage`: 当前语言
- `loginItemEnabled`: 是否开机启动
- `nightRestrictionEnabled` / `nightWindDownStartMinutes` / `nightLockStartMinutes` / `nightUnlockMinutes`: 夜间禁用配置
- `nightOverrideGrantedAt` / `nightOverrideUntil` / `nightOverrideReason` / `nightOverrideNightKey` / `nightOverrideNumberForNight`: 活跃夜间破例状态
- `nightOverrideCountNightKey` / `nightOverrideCountForNight`: 当前夜晚破例次数，用于递增等待成本
- `temporaryDisableStartedAt` / `temporaryDisableUntil`: 活跃临时禁用状态

**时机**: 应用启动时读取 (`loadSettings`)，设置变更时立即保存 (`saveSettings`)

旧版 `nightTestingExitEnabled` 和 `nightLockOverrideUntil` 会在启动时清理，不再参与
夜间禁用逻辑。

### 6.3 SessionState - 会话状态

**数据结构** ([`SessionState.swift`](../Sources/TwentyGuardCore/SessionState.swift)):
- `workStartTime` / `breakStartTime`: 会话开始时间
- `postponeStartTime` / `postponeDuration` / `totalPostponedTime`: 正在进行的推迟休息和累计推迟成本
- `currentWorkDuration` / `currentBreakDuration`: 当前时长设置
- `pausedBySystemEvent`: 是否因系统事件暂停
- `lastSaved`: 保存时间（用于判断有效性，30分钟内有效）

**保存时机**:
- 每 10 秒自动快照 (`stateSnapshotTimer`)
- 会话状态变更时、系统事件发生时

**恢复逻辑** ([`AppDelegate.swift`](../Sources/TwentyGuard/AppDelegate.swift)):
- 验证会话有效性（时间 < 30分钟，且非系统事件暂停）
- 若存在有效推迟休息：继续推迟倒计时；若推迟已过期：立即进入应有休息
- 否则恢复 `workSessionStartTime` 继续会话，或启动新会话

### 6.4 SQLite + JSONL - 历史数据

**SQLite**: 结构化统计数据，全部保留
**JSONL**: 调试日志，30天保留期

v1.7.0 后，`stats_events` 是 App 退出、临时禁用和夜间破例的长期统计源。
JSONL 仍用于事件审计、调试和崩溃恢复，但月度统计不依赖 30 天 JSONL 保留期。
v1.7.6 起，`session_debug` 记录关键会话诊断动作，常见 `action` 包括
`restore_session_decoded`、`restore_active_work_session`、`system_pause_current_session`、
`system_resume_evaluate`、`restore_reused_active_work_session`、`start_break_attached`
和 `complete_break_marked`。

**数据清理**:
- SQLite: 应用启动时清理 `sessions` 和 `stats_events`
- JSONL: 后台异步清理 ([`LogManager.swift:183-187`](../Sources/TwentyGuard/LogManager.swift#L183-L187))

---

## 7. 国际化系统

### 7.1 支持语言

- 简体中文 (`zh-Hans`)
- English (`en`)
- Español (`es`)
- 日本語 (`ja`)
- 한국어 (`ko`)

### 7.2 实现方式

**SwiftPM 资源化本地化**:
- 翻译文件位于 `Sources/TwentyGuardCore/Resources/<language>.lproj/Localizable.strings`
- `Package.swift` 设置 `defaultLocalization: "en"`，并通过 `TwentyGuardCore` target 处理本地化资源
- `AppLocalization` 统一负责语言检测、字符串查找和兜底策略
- `AppDelegate.localized(_:)` 只保留薄封装，UI 文本不再维护内联 Swift 字典
- `Makefile` 会复制 SwiftPM 生成的 resource bundle 到 `.app/Contents/Resources/`

**测试保护**:
- `AppLocalizationTests` 校验 5 种语言的 key 完全一致
- `AppLocalizationTests` 校验所有本地化格式占位符一致，避免 `%@` / `%d` / `%%` 运行时格式错误
- `StatsHealthVerdictTests` 覆盖健康判断文案在中文 localizer 下的输出

### 7.3 语言切换

**自动检测**:
- 优先使用保存的语言设置
- 否则根据 `Locale.preferredLanguages` 自动选择
- 匹配规则: `zh*` → 简体中文, `en*` → English, `es*` → Español, `ja*` → 日本語, `ko*` → 한국어
- 未匹配语言使用 English

**运行时切换**:
- 保存新语言 → 重建菜单 → 更新休息窗口文本
- 无需重启应用，立即生效

---

## 8. 构建与部署

### 8.1 构建系统

**Swift Package Manager** + **Makefile**

**关键命令**:
```bash
make build-app    # 构建 .app 包到 build/
make install      # 安装到 /Applications/
make launch       # 启动应用
make clean        # 清理构建产物
```

### 8.2 构建流程

**Makefile流程** ([`Makefile`](../Makefile)):
1. 清理旧构建产物
2. Swift Release编译
3. 创建 .app 目录结构
4. 复制可执行文件
5. 写入 `Info.plist` 和 `PkgInfo`
6. 复制运行时资源（图标、状态栏图标、版本历史）
7. 复制 SwiftPM 生成的 resource bundle 到 `.app/Contents/Resources/`
8. 进行 ad-hoc 签名
9. 执行 `scripts/verify-app-bundle.sh` 校验标准 app bundle 结构
10. 打包完成

**输出位置**: `build/TwentyGuard.app`

**标准 `.app` 内容要求**:
- `Contents/Info.plist`: 包含 `CFBundlePackageType=APPL`、`CFBundleInfoDictionaryVersion=6.0`、版本号、Bundle ID、最低系统版本等标准元数据
- `Contents/PkgInfo`: `APPL????`
- `Contents/MacOS/TwentyGuard`: 主可执行文件
- `Contents/Resources/AppIcon.icns`: 应用图标
- `Contents/Resources/statusbar_icon*.png`: 菜单栏图标
- `Contents/Resources/version-history.json`: About 页面版本历史
- `Contents/Resources/TwentyGuard_TwentyGuard.bundle`: App target 的 SwiftPM 资源 bundle
- `Contents/Resources/TwentyGuard_TwentyGuardCore.bundle`: Core target 的 SwiftPM 本地化资源 bundle
- `Contents/_CodeSignature/CodeResources`: 签名后的代码签名资源清单

构建校验会拒绝缺失上述关键文件、缺失标准 `Info.plist` 字段、SwiftPM resource
bundle 放错到 `.app` 根目录、`.DS_Store`、以及源码资产目录 `.xcassets`。

### 8.3 应用签名

`make build-app` 使用 ad-hoc 签名，只适合本机开发、测试和安装到 `/Applications`。
公开直接下载版本必须使用 Apple Developer Program 的 **Developer ID Application**
证书签名，并通过 Apple notarization 公证。

**Info.plist配置**:
```xml
<key>CFBundleIdentifier</key>
<string>com.javengroup.twentyguard</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundleVersion</key>
<string>1.7.6</string>
<key>LSMinimumSystemVersion</key>
<string>12.0</string>
```

**公开发布流程**:
```bash
# 一次性保存公证凭据，命令会安全提示输入 app-specific password
make notary-store-credentials APPLE_ID=<apple-id-email> TEAM_ID=<team-id>

# 每次发布
make release \
  TEAM_ID=<team-id> \
  DEVELOPER_ID_APPLICATION="Developer ID Application: <name> (<team-id>)"
```

`make release` 会执行：
1. 构建 `build/TwentyGuard.app`
2. 使用 hardened runtime 和 timestamp 重新签名 app
3. 创建并签名 `dist/TwentyGuard-v<version>.dmg`
4. 提交 Apple notarization
5. stapler 写入公证票据
6. 使用 `codesign`、`spctl` 和 `stapler validate` 验证发布产物

**v1.5.3 发布验证结果**:
- Developer ID: `Developer ID Application: Shenzhen Lifangjuzhen Technology Co., Ltd. (MDQ5F44RU5)`
- Notary submission: `691c1c24-24ca-45ba-a7da-efe7a36e13fe`
- Gatekeeper: `accepted`, source `Notarized Developer ID`
- 发布产物: `dist/TwentyGuard-v1.5.3.dmg`
- SHA-256: `322364e11c50a8ac7bccf71cceeeb136ff0bca338fb077b3664e53511be355cc`

v1.7.6 当前为功能实现版本；公开分发前需要重新执行 `make release`，生成签名、
公证并 staple 后的 `dist/TwentyGuard-v1.7.6.dmg`，再更新本节发布验证结果。

### 8.4 版本管理

**重要**: 避免多版本共存

**标准工作流**:
```bash
# 开发 → 测试
make build-app && make install

# 验证版本
ps aux | grep TwentyGuard

# 确保只有一个进程在运行
make install  # 自动终止旧进程
```

---

## 9. 关键技术决策

### 9.1 为什么使用绝对时间？

**问题**: 系统睡眠/屏保会暂停 Timer

**方案对比**:
| 方案 | 优点 | 缺点 |
|------|------|------|
| 相对时间计数 | 实现简单 | 累积误差、睡眠失效 |
| 绝对时间记录 | 精确、支持睡眠恢复 | 需处理时区/夏令时 |

**选择**: 绝对时间 + 实时计算

### 9.2 为什么双重记录系统？

**EventRecorder → SQLite + JSONL**

**原因**:
- SQLite: 高效查询、统计聚合
- JSONL: 调试友好、崩溃分析
- 未来可能移除 JSONL，目前保留用于调试

### 9.3 为什么使用累计时长限制推迟？ ⭐ v1.2.0 更新

**问题背景**:
- v1.0 设计：只限制 "推迟5分钟" 最多2次
- 用户可以通过反复点击 "推迟1分钟" 或 "推迟2分钟" 绕过限制
- 违背了防止过度推迟的初衷

**v1.1.0 解决方案**:
- **累计时长限制**: 所有推迟操作（1/2/5分钟）总计最多 10 分钟
- **动态UI反馈**: 剩余时间不足时自动禁用对应按钮
- **透明度**: 底部状态栏显示已用/剩余推迟时间

**v1.2.0 优化**:
- **更严格的默认值**: 默认推迟上限从 10 分钟降为 5 分钟
- **可配置性**: 自定义模式下可选择 5 分钟或 10 分钟上限
- **设计理由**: 5 分钟更符合护眼原则，同时保留灵活性给需要的用户

**设计权衡**:
- 5分钟默认上限：更好地保护眼睛健康
- 10分钟可选上限：允许灵活应对紧急情况
- 完成休息后重置：避免跨会话累积，每次休息都是新的机会

### 9.4 为什么屏保后重置会话？

**原理**: 屏保/睡眠本身就是眼睛休息

**实现**:
- 屏保启动 → 结束当前会话
- 屏保停止 → 开始新工作会话
- 用户回来时已经得到了休息

---

## 10. 维护指南

### 10.1 常见问题排查

#### 问题1: 倒计时不准确

**原因**: 可能运行了旧版本

**排查**:
```bash
# 检查进程
ps aux | grep TwentyGuard

# 查看可执行文件路径
lsof -p <PID> | grep TwentyGuard.app

# 重新安装
make install
```

#### 问题2: 推迟功能影响工作时长

**原因**: 推迟逻辑错误修改了 `currentWorkDuration`

**验证**:
```bash
# 查看会话状态文件
cat ~/Library/Application\ Support/com.javengroup.twentyguard/current_session.json

# currentWorkDuration 应该是 1800 (30分钟)
```

**修复**: 确保推迟逻辑只使用临时变量 ([`AppDelegate.swift:1332-1335`](../Sources/TwentyGuard/AppDelegate.swift#L1332-L1335))

#### 问题3: 多个休息窗口残留

**原因**: 窗口清理不彻底

**排查**:
```swift
// 检查日志中的窗口创建/清理消息
log show --predicate 'subsystem == "com.javengroup.twentyguard"' --last 1h

// 查找 "🧹 开始清理休息窗口" 和 "✅ 窗口清理完成"
```

**修复**: 确保 `cleanupBreakOverlays()` 在所有分支都被调用

### 10.2 日志位置

**应用支持目录**:
```
~/Library/Application Support/com.javengroup.twentyguard/
├── twentyguard_stats.db         # SQLite数据库
├── current_session.json      # 当前会话状态
└── logs/
    ├── 2025-10-31.jsonl      # 今日日志
    └── ...
```

旧版 `20-20-20` 数据目录不再兼容读取；TwentyGuard 使用该新目录重新开始记录统计、日志和会话状态。

**系统日志**:
```bash
# 查看应用日志
log show --predicate 'process == "TwentyGuard"' --last 1h

# 查看系统睡眠事件
log show --predicate 'subsystem == "com.apple.power"' --last 1h
```

### 10.3 数据库检查

```bash
# 打开数据库
sqlite3 ~/Library/Application\ Support/com.javengroup.twentyguard/twentyguard_stats.db

# 查看今日会话
SELECT id, datetime(start_time, 'unixepoch', 'localtime'), actual_work_duration, postpone_count, break_completed
FROM sessions
WHERE date(start_time, 'unixepoch', 'localtime') = date('now', 'localtime')
ORDER BY start_time DESC;

# 查看活跃会话
SELECT * FROM sessions WHERE status = 'active';

# 查看最近10次推迟
SELECT id, datetime(start_time, 'unixepoch', 'localtime'), postpone_count, postpone_total_duration, postpones
FROM sessions
WHERE postpone_count > 0
ORDER BY start_time DESC
LIMIT 10;

# 定位未闭合休息或推迟记录
SELECT id, datetime(start_time, 'unixepoch', 'localtime'), break_info, postpones
FROM sessions
WHERE json_extract(break_info, '$.status') = 'active'
   OR EXISTS (
      SELECT 1 FROM json_each(COALESCE(NULLIF(postpones, ''), '[]'))
      WHERE json_extract(value, '$.status') = 'active'
         OR json_extract(value, '$.end_time') IS NULL
   );
```

### 10.4 代码修改检查清单

**修改计时逻辑时必查**:
- [ ] 是否使用绝对时间而非相对计数？
- [ ] 是否处理了系统睡眠/屏保事件？
- [ ] 是否添加了重入保护标志？
- [ ] 是否保存了会话状态？
- [ ] 是否更新了 EventRecorder 记录？

**修改UI时必查**:
- [ ] 是否支持所有5种语言？
- [ ] 是否支持多显示器场景？
- [ ] 是否适配深色模式？
- [ ] 按钮是否支持键盘快捷键？

**修改数据存储时必查**:
- [ ] 是否同时更新 SQLite 和 JSONL？
- [ ] 是否设置了数据清理策略？
- [ ] 是否明确处理了数据 reset / schema reset 策略？
- [ ] 是否有备份恢复机制？

### 10.5 性能监控指标

**正常运行状态**:
- CPU 使用率: < 1%
- 内存占用: < 50MB
- 磁盘写入: < 1KB/min
- 数据库大小: < 10MB (90天数据)

**异常检测**:
```bash
# CPU 使用率
top -l 1 | grep TwentyGuard

# 内存占用
ps aux | grep TwentyGuard | awk '{print $6}'

# 数据库大小
du -h ~/Library/Application\ Support/com.javengroup.twentyguard/twentyguard_stats.db
```

---

## 附录

### A. 架构演进记录

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| v1.0.0 | 2025-08 | 初始架构，单一 AppDelegate，基础计时功能 |
| v1.0.1 | 2025-09 | 引入 EventRecorder 统一事件记录 |
| v1.0.2 | 2025-10 | 添加 SQLite 数据库，健康统计功能 |
| v1.1.0 | 2025-10-31 | 推迟机制重构：从单按钮限制改为累计时长限制 |
| v1.2.0 | 2026-04-26 | 默认推迟上限降为 5 分钟，自定义模式支持 5/10 分钟上限 |
| v1.4.0 | 2026-05-03 | 公开品牌迁移为 TwentyGuard，更新 bundle 元数据、构建产物和发布路径 |
| v1.5.0 | 2026-05-05 | 内部 SwiftPM target、可执行文件和本地数据路径统一为 TwentyGuard；旧版本地数据不迁移；发布 Developer ID 签名并公证的 DMG |
| v1.5.1 | 2026-05-07 | 更新 app 图标与状态栏图标资源；补充营销发布资料、渠道草稿和素材清单 |
| v1.5.2 | 2026-05-07 | 多语言系统迁移到 SwiftPM `.lproj/Localizable.strings` 标准资源；补齐夜间禁用和统计面板翻译；新增多语言完整性测试；发布 Developer ID 签名并公证的 DMG |
| v1.5.3 | 2026-05-07 | 修复分发版启动时 SwiftPM resource bundle 查找路径导致的崩溃；补齐标准 app bundle 元数据；新增 app/DMG 打包结构校验和资源查找回归测试；发布签名公证 DMG |
| v1.5.4 | 2026-05-08 | 夜间禁用移除测试出口，新增正式破例状态机、递增等待成本、确认句、事件日志、统计汇总和本地化回归测试 |
| v1.5.5 | 2026-05-08 | 推迟休息状态纳入 SessionState，重启后继续推迟倒计时或立即恢复欠下的休息；菜单栏推迟文案从“屏幕使用”改为“推迟休息”；新增会话恢复回归测试 |
| v1.6.0 | 2026-05-23 | 新增临时禁用 1 小时状态和策略；暂停当前工作/休息/推迟计时并在到期后开启新工作周期；夜间禁用和夜间破例优先；新增策略与本地化测试 |
| v1.7.0 | 2026-05-23 | 健康统计重构为保护遵守视角；新增 `stats_events` 长期记录 App 退出、临时禁用和夜间破例；新增月度切换、日历状态、选中日期明细和例外标记 |
| v1.7.1 | 2026-05-23 | 统计窗口拆分为「概览 / 月度」顶部 tab；月度页独立承载日历和日期明细；月份切换不再重建默认概览页 |
| v1.7.2 | 2026-05-23 | 修复推迟统计落库目标错误：break 已开始后 work session 已完成，推迟现在优先挂到当前未完成 break 所属会话；新增 app 层 SQLite 回归测试 |
| v1.7.3 | 2026-05-24 | 修复 break/postpone 生命周期闭合：推迟恢复休息时关闭 active postpone，完成欠下休息时完成同一 break opportunity，新工作周期中断遗留 active 记录；数据质量隐藏无害启动碎片并显示异常 session ID |
| v1.7.4 | 2026-05-24 | 统计窗口支持 ⌘W 关闭；右下角 Close 按钮配置 ⌘C key equivalent；新增 AppKit 快捷键回归测试 |
| v1.7.5 | 2026-05-24 | 恢复同一工作开始时间时复用 active session row；统计引擎按同一开始时间去重恢复副本，优先保留带休息/推迟证据的记录；新增 SQLite 与 StatsEngine 回归测试 |
| v1.7.6 | 2026-05-24 | 新增 `session_debug` JSONL 诊断事件；StatsDatabase 支持注入 debug logger；会话恢复、系统暂停/唤醒、工作会话复用、休息挂载和休息完成均带结构化定位字段；本机旧运行数据已清理后重新开始 |

### B. 相关文档

- [README.md](../README.md) - 用户使用指南
- [CLAUDE.md](../CLAUDE.md) - 项目开发指南
- [Package.swift](../Package.swift) - Swift Package配置

### C. 联系方式

**维护者**: Javen Fang (@javenfang)
**邮箱**: javen.out@gmail.com
**GitHub**: https://github.com/JavenGroup/TwentyGuard

---

**最后更新**: 2026-05-24
**文档版本**: v1.7.6
