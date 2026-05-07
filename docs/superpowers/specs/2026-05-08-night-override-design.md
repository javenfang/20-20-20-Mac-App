# Night Override Design

Date: 2026-05-08
Status: Approved for design, pending implementation plan
Scope: Replace the Night Screen Lock testing escape with a formal override flow.

## Context

TwentyGuard currently has a Night Screen Lock feature that can fully block screen
use during configured night hours. The current overlay exposes a "Testing
Escape" path intended for development and validation. That is not suitable as a
public product behavior: users need a legitimate emergency path, but it should
not be convenient enough to undermine the night boundary.

The new feature is a formal "Night Override" flow. It lets the user unlock the
computer for a limited period when necessary, while adding deliberate friction,
self-acknowledgement, and event recording.

## Goals

- Remove all user-facing "testing escape" language and behavior.
- Provide a formal override path that is always available during full night
  lock.
- Make the override slow and inconvenient enough to interrupt impulsive use.
- Keep the tone firm and slightly uncomfortable without insulting the user.
- Unlock for a fixed 30-minute window.
- Record override attempts and granted overrides as first-class product events.
- Preserve absolute-time behavior across sleep, wake, and app restart.

## Non-Goals

- No password, account, or remote approval system.
- No social sharing, public shaming, or external punishment.
- No historical trend chart in this iteration.
- No change to the normal 20-20-20 break postpone rules.
- No change to the existing night wind-down schedule model.

## Product Behavior

When the app enters full Night Screen Lock, the overlay shows a low-emphasis
button:

```text
Use Computer Anyway
```

In Simplified Chinese:

```text
破例使用电脑
```

Selecting it starts the override flow inside the same night lock overlay.

The flow has four required steps:

1. Select a reason.
2. Wait through the required cooling-off countdown.
3. Manually type the exact confirmation sentence.
4. Confirm the 30-minute unlock.

The override is granted only when all requirements are satisfied.

## Override Cost

Each override unlocks the computer for 30 minutes. The cost increases per night:

| Override count for the same night | Wait time | Unlock duration |
| --- | ---: | ---: |
| First | 60 seconds | 30 minutes |
| Second | 90 seconds | 30 minutes |
| Third and later | 120 seconds | 30 minutes |

The night key should follow the relevant night schedule rather than the calendar
day alone. An override after midnight still belongs to the night that started
before midnight.

## Reasons

The user must choose one reason before the final unlock button can be enabled:

- Urgent work
- Life task
- Family matter
- Other

Localized Simplified Chinese labels:

- 紧急工作
- 生活事务
- 家庭事务
- 其他

The selected reason is recorded with the override event. It does not alter the
unlock duration.

## Confirmation Sentences

The confirmation sentence must be typed exactly. Copy and paste should not
satisfy the input field. The button remains disabled until the reason is chosen,
the countdown is complete, and the text matches exactly.

First override:

```text
我正在破例使用电脑，30 分钟后必须停止。
```

Second override:

```text
我已经第二次破例。今晚继续用电脑，会影响明天的清醒。
```

Third and later:

```text
我正在重复破坏自己设定的夜间边界。这次仍只解锁 30 分钟。
```

These sentences are intentionally self-acknowledging and uncomfortable, but they
avoid direct personal insults. This keeps the product serious enough for public
release while preserving meaningful friction.

## Overlay States

### Locked

The full lock overlay shows:

```text
夜间禁用中
屏幕已禁用

恢复可用：07:00
今晚：20:00 收紧开始 · 21:00 完全禁用

[破例使用电脑]
```

The override button is visible but not visually primary.

### Override Request

After the user clicks the override button, the overlay changes to:

```text
破例使用电脑

选择原因：
[紧急工作] [生活事务] [家庭事务] [其他]

请等待 60 秒。
这段时间是为了确认你真的需要继续使用电脑。

确认句：
我正在破例使用电脑，30 分钟后必须停止。

[输入框]

[取消] [还需要等待 42 秒]
```

When the countdown reaches zero and the typed sentence matches, the action
button becomes:

```text
解锁 30 分钟
```

### Override Active

After the override is granted, the overlay is removed and the app returns to
normal work mode for the remaining override window.

The menu bar status should indicate the active exception:

```text
夜间破例中 · 剩余 29:42
```

When the 30-minute window expires, full Night Screen Lock resumes automatically
if the schedule still requires it.

## Persistence

The app should persist the active override in `UserDefaults` so app restarts do
not accidentally bypass or lose the override state:

- `nightOverrideUntil`
- `nightOverrideGrantedAt`
- `nightOverrideReason`
- `nightOverrideNightKey`
- `nightOverrideCountForNight`

The existing absolute-time model applies. Sleep does not pause or extend the
override. If the Mac sleeps for the whole 30-minute window, the override expires
while asleep.

On app launch:

- If `nightOverrideUntil` is still in the future, keep the override active.
- If it has expired, clear the override and apply normal night lock state.

## Events

Override behavior should be recorded as formal product events:

- `night_override_requested`
- `night_override_granted`
- `night_override_cancelled`
- `night_override_expired`

Each event should include the relevant subset of:

- reason
- night key
- override count for the night
- wait seconds
- unlock minutes
- granted at
- override until
- schedule wind-down time
- schedule lock time
- schedule unlock time

The implementation should reuse the existing local-first event/logging model.
No network behavior is introduced.

## Statistics

This iteration adds only a small summary to the Night metric in the health
report. It should not add a new trend chart.

If there were no overrides last night:

```text
夜间：已启用 · 昨晚无破例
```

If there were overrides:

```text
夜间：已启用 · 昨晚破例 1 次，共 30 分钟
```

For multiple overrides:

```text
夜间：已启用 · 昨晚破例 3 次，共 90 分钟
```

## Architecture

Keep the night schedule decision and the override-cost decision separate.

Existing `NightRestrictionPolicy` remains responsible for:

- Whether night restriction is enabled.
- Whether the current time is normal, wind-down, or full lock.
- When the next unlock occurs.
- The effective work duration during wind-down.

Add a separate `NightOverridePolicy` responsible for:

- Wait seconds for the current night count.
- Unlock duration.
- Confirmation sentence selection.
- Night-key based count behavior.
- Active override expiry checks.

The App target owns overlay presentation and persistence wiring. Core policy
logic should live in `TwentyGuardCore` so it can be tested without UI.

## Localization

Remove the user-facing testing escape localization keys:

- `nightTestingExit`
- `nightTestingExitShown`
- `nightTestingExitHidden`

Add formal override keys for all supported languages:

- `nightOverride`
- `nightOverrideReasonUrgentWork`
- `nightOverrideReasonLifeTask`
- `nightOverrideReasonFamily`
- `nightOverrideReasonOther`
- `nightOverrideConfirmPrompt`
- `nightOverrideUnlock`
- `nightOverrideCancel`
- `nightOverrideWaiting`
- `nightOverrideActiveStatus`
- `nightOverrideMismatch`

The existing localization completeness tests should fail if any supported
language misses one of these keys.

## Error Handling

- Incomplete input: keep the unlock button disabled.
- Wrong input: show `确认句必须完全一致。`
- Cancelled request: return to the locked overlay and record
  `night_override_cancelled`.
- App restart during active override: preserve the override if still valid.
- App restart after override expiry: clear the override and restore full lock.
- System sleep during override: calculate expiry by absolute time.

## Testing

Add unit tests for `NightOverridePolicy`:

- First override requires 60 seconds and grants 30 minutes.
- Second override requires 90 seconds and grants 30 minutes.
- Third and later overrides require 120 seconds and grant 30 minutes.
- Confirmation sentences map correctly by count.
- Expired overrides are considered inactive.
- Active overrides remain active across a simulated app restart.
- Night-key behavior groups after-midnight overrides with the same night.

Add app-level tests or focused integration seams where practical:

- Testing escape settings are no longer used by the UI state.
- Override events are emitted with count, reason, wait seconds, and unlock
  minutes.
- Localization keys are complete across English, Simplified Chinese, Spanish,
  Japanese, and Korean.

## Versioning and Documentation

This is a user-visible behavior change. Implementation must bump the app version
from `1.5.3` to `1.5.4` in the same change set:

- `Info.plist`
- `Sources/TwentyGuard/Resources/version-history.json`
- `docs/REQUIREMENTS.md`
- `docs/architecture.md`
- `CLAUDE.md`

The docs should describe the formal override behavior and remove references to
testing escape as a user-facing capability.
