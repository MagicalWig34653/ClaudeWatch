# ClaudeWatch — Product & Engineering Specification

## 1. Goal

Build a native macOS application named **ClaudeWatch**.

ClaudeWatch monitors Claude Code sessions and notifies the user when a session:

- requires user input,
- requires permission,
- waits for plan approval,
- finishes,
- fails,
- or reaches another configured attention-worthy state.

The primary use case is a developer running multiple Claude Code accounts, potentially switched through `cswap`, who wants one account-independent notification system.

The application must support:

1. a normal native macOS application window,
2. a menu bar interface,
3. Pushover notifications to mobile devices,
4. optional native macOS notifications,
5. persistent session/event history,
6. configurable notification rules,
7. secure storage of credentials,
8. local Claude Code hook ingestion,
9. an architecture that can later support remote/cloud session event relays.

The project should remain deliberately small, native, maintainable, and dependency-light.

---

# 2. Technology

Use:

- Swift
- SwiftUI
- SwiftData
- UserNotifications
- Security / Keychain APIs
- ServiceManagement
- Network.framework or another Apple-native networking API
- URLSession
- Observation where appropriate

Target:

- macOS 14 or newer

Do not use:

- Electron
- Catalyst
- a web UI
- Core Data directly
- manually managed SQLite
- JSON files as the primary application database
- third-party persistence libraries
- third-party HTTP frameworks
- third-party Keychain wrappers unless there is a compelling technical reason

Prefer Apple frameworks and standard library functionality.

---

# 3. Application Structure

ClaudeWatch is a normal macOS application with two presentation surfaces sharing the same data and services:

```text
ClaudeWatch.app
│
├── Main Window
│   ├── Overview
│   ├── Sessions
│   ├── Accounts
│   ├── Notifications
│   └── Settings
│
└── MenuBarExtra
    ├── attention-required sessions
    ├── running sessions
    ├── recently finished sessions
    └── quick actions
```

Both surfaces must use the same SwiftData ModelContainer and application state.

The menu bar implementation must use SwiftUI `MenuBarExtra`.

The main application should remain available even if the menu bar item is disabled.

---

# 4. Persistence

Use three distinct mechanisms according to the type of data.

## SwiftData

Store structured application data in SwiftData:

- Claude sessions
- received events
- account metadata
- notification rules
- project metadata
- delivery results
- optional session history

Do not create a manually managed SQLite database.

Do not persist these models as ad-hoc JSON files.

## UserDefaults / AppStorage

Use `@AppStorage` or UserDefaults for lightweight preferences such as:

- menu bar enabled
- native notifications enabled globally
- Pushover enabled globally
- start at login
- notification sound enabled
- history retention period
- application appearance preferences
- listener port if configurable

## Keychain

Store secrets exclusively in macOS Keychain:

- Pushover User Key
- Pushover Application/API Token
- optional future relay token
- other authentication material

Secrets must never be written to:

- SwiftData
- UserDefaults
- logs
- debug output
- source code

---

# 5. Core Domain Models

Create models along these conceptual lines.

Exact implementation details may be adjusted where SwiftData requires it.

## ClaudeSession

Fields:

```text
id: String                      unique
projectName: String
workingDirectory: String?
accountAlias: String?

source: SessionSource
status: SessionStatus

remoteSessionID: String?
remoteURL: URL?

startedAt: Date
updatedAt: Date
finishedAt: Date?

lastMessage: String?
lastEventType: EventType?

requiresAttention: Bool
```

Possible `SessionSource` values:

```text
local
cloud
relay
unknown
```

Possible `SessionStatus` values:

```text
running
needsInput
waitingForPermission
waitingForPlanApproval
finished
failed
unknown
```

Enums persisted through SwiftData should use stable raw values where appropriate.

---

## ClaudeEventRecord

Persist received events separately from the current session state.

Fields:

```text
id: UUID
sessionID: String
eventType: EventType
receivedAt: Date
sourceTimestamp: Date?

message: String?
toolName: String?
projectName: String?
accountAlias: String?

wasPushoverSent: Bool
wasNativeNotificationSent: Bool

pushoverError: String?
nativeNotificationError: String?
```

This model acts as:

- history,
- debugging aid,
- notification deduplication source.

---

## ClaudeAccount

ClaudeWatch must not store Claude credentials.

Account metadata only:

```text
id: UUID
alias: String
displayName: String?
notificationsEnabled: Bool
```

`cswap` remains the source of truth for actual Claude account configuration.

ClaudeWatch must never copy Claude authentication tokens from `cswap`.

Account detection should be best-effort and must not be required for event processing.

If an account cannot be identified, use `Unknown Account`.

Design the account integration behind a protocol so `cswap` behavior can change without affecting the rest of the app.

Example:

```swift
protocol AccountProvider {
    func accounts() async throws -> [DetectedAccount]
    func currentAccount() async throws -> DetectedAccount?
}
```

Create a `CSwapAccountProvider`.

Do not hardcode assumptions about undocumented `cswap` JSON fields without first inspecting actual output and creating decoder fixtures/tests.

---

## NotificationRule

Rules should be configurable per event type.

Fields conceptually:

```text
eventType
enabled

sendNativeNotification
sendPushover

pushoverPriority
playNativeSound

includeProjectName
includeAccountAlias
includeMessagePreview
```

Create sensible defaults on first launch.

Default enabled events:

- needs input
- permission required
- plan approval required
- finished
- failed

Session-start notifications should default to disabled.

---

# 6. Normalized Event Model

Claude Code hook payloads must not flow directly through the entire application.

Introduce a normalized internal type:

```swift
struct ClaudeEvent: Sendable {
    let type: ClaudeEventType
    let sessionID: String
    let timestamp: Date

    let workingDirectory: String?
    let projectName: String?
    let accountAlias: String?

    let source: SessionSource

    let remoteSessionID: String?
    let remoteURL: URL?

    let message: String?
    let toolName: String?
}
```

The pipeline must be:

```text
Claude hook payload
        ↓
HookPayloadDecoder
        ↓
ClaudeEventNormalizer
        ↓
ClaudeEvent
        ↓
ClaudeEventProcessor
        ├── update SessionStore
        ├── persist event
        ├── evaluate NotificationRules
        ├── NativeNotificationService
        └── PushoverService
```

Claude-specific payload parsing must stay isolated from application business logic.

This is important because hook schemas may evolve.

Unknown fields in hook payloads should not break decoding.

Unknown event types should be logged safely and ignored rather than crashing the listener.

---

# 7. Local Hook Listener

ClaudeWatch should provide a lightweight HTTP endpoint bound strictly to loopback:

```text
127.0.0.1
```

Suggested default port:

```text
17831
```

Endpoint:

```text
POST /v1/events
```

Requirements:

- accept JSON only,
- impose a reasonable request size limit,
- bind to loopback only,
- never execute arbitrary commands from received payloads,
- respond quickly,
- process persistence and notifications asynchronously after validation,
- tolerate duplicate events.

Example conceptual request:

```json
{
  "hook_event_name": "Stop",
  "session_id": "abc123",
  "cwd": "/Users/example/Projects/backend"
}
```

The exact Claude Code hook payload format must be verified against the currently installed Claude Code version/documentation during implementation.

Do not invent fields when the real hook payload can be inspected.

---

# 8. Claude Code Hook Integration

Create an example hook adapter/script inside the repository, e.g.:

```text
Integration/
└── claude-watch-hook.sh
```

Its responsibility is only to forward stdin from Claude Code to ClaudeWatch.

Conceptually:

```text
Claude Code hook
      ↓
stdin JSON
      ↓
claude-watch-hook.sh
      ↓
POST localhost:17831/v1/events
```

Keep the shell script very small.

ClaudeWatch itself owns:

- normalization,
- deduplication,
- session state,
- notification policy.

Support or normalize events corresponding to at least:

- session/turn completion,
- `AskUserQuestion`,
- permission request,
- plan approval / `ExitPlanMode`,
- errors where detectable.

When Claude Code exposes `AskUserQuestion` through a tool hook rather than a dedicated notification event, detect it from the appropriate tool event.

Do not rely solely on a generic notification hook for critical user-input states.

Provide documentation showing the required Claude Code hook configuration.

Do not automatically overwrite an existing Claude Code configuration.

If automated setup is implemented later, merge configuration safely.

---

# 9. Event Deduplication

Claude may produce multiple hook events that conceptually represent the same state.

Avoid duplicate notifications.

Create a deterministic fingerprint from data such as:

```text
sessionID
event type
relevant message/tool
short time window
```

Persist enough information to prevent the same logical event from repeatedly triggering Pushover.

Do not suppress genuinely new questions within the same session.

---

# 10. Session State Machine

Centralize state transitions.

Example:

```text
event                         resulting state

session activity              running
AskUserQuestion               needsInput
permission request            waitingForPermission
ExitPlanMode approval         waitingForPlanApproval
Stop / completion             finished
failure                       failed
new activity after finished   running
```

Do not spread state transition logic through SwiftUI views.

Implement it in a dedicated domain/service type.

Add unit tests for state transitions.

---

# 11. Pushover

Implement a dedicated:

```text
PushoverService
```

using `URLSession`.

Configuration screen:

```text
Pushover

User Key
[ secure field ]

Application Token
[ secure field ]

[ Send Test Notification ]

Status:
✓ Test notification delivered
```

Retrieve credentials from Keychain only when needed.

The notification should contain useful context.

Suggested title:

```text
Claude · work · backend
```

Example messages:

```text
❓ Claude needs input
Which migration strategy should be used?
```

```text
✅ Claude finished
backend-api
```

```text
🔐 Permission required
Claude wants permission to run a command.
```

If a remote session URL exists, include it as the Pushover URL/action target.

The Pushover integration must handle:

- HTTP errors
- API errors
- network failures
- malformed credentials

Show human-readable errors in Settings without exposing secrets.

---

# 12. Native macOS Notifications

Implement:

```text
NativeNotificationService
```

using `UNUserNotificationCenter`.

On first use, request authorization appropriately.

Do not repeatedly prompt if permission has already been denied.

Settings must show current authorization state where possible.

Native notifications are configurable independently from Pushover.

Examples:

```text
Claude · backend-api

Needs your input
Which migration strategy should be used?
```

and:

```text
Claude · website

Session finished
```

Rules must allow:

```text
Needs Input:
[x] macOS
[x] Pushover

Finished:
[x] macOS
[x] Pushover

Started:
[ ] macOS
[ ] Pushover
```

Support optional notification sounds.

When the application is foregrounded, native notifications should still follow explicit user preferences rather than silently disappearing because the app happens to be active.

Clicking a native notification should:

- activate ClaudeWatch,
- open the relevant session detail,
- or open the remote Claude session URL where appropriate.

Centralize routing through a notification action handler.

---

# 13. Main Window

Use a native macOS sidebar/navigation layout.

Sections:

```text
Overview
Sessions
Accounts
Notifications
Settings
```

## Overview

Show:

- active session count,
- sessions requiring attention,
- recently finished sessions,
- recent events.

Prioritize attention-required sessions visually.

Example:

```text
3 Active       1 Needs Attention       8 Finished Today

backend-api
work
Needs Input

"Which migration strategy should be used?"

[Open Session]
```

Avoid dashboard-style visual clutter.

---

# 14. Sessions Screen

Provide a searchable/filterable session list.

Filters:

- Active
- Needs Attention
- Finished
- All

Each row should display:

- project name
- account alias where known
- state
- last update
- local/cloud source

Session detail should show:

- session ID
- project
- account
- working directory
- current status
- timestamps
- relevant message
- event history
- remote link if available

Provide a delete action for historical records.

Never delete active sessions accidentally.

---

# 15. Accounts Screen

Show accounts discovered through configured account providers such as `cswap`.

Example:

```text
Alias        Notifications

work         On
personal     On
client-a     Off
```

Account-specific enable/disable is sufficient for MVP.

Do not implement Claude authentication.

Provide:

```text
Refresh Accounts
```

and show a helpful state if `cswap` cannot be found.

Executable discovery should not assume a single Homebrew location.

Search sensible locations and/or invoke the user's login shell appropriately.

Avoid running shell commands through string interpolation where arguments can be passed directly to `Process`.

---

# 16. Notification Settings

Provide one central notification configuration page.

Global settings:

```text
Pushover                  On/Off
Native macOS notifications On/Off
Sound                      On/Off
```

Per-event rules:

```text
Event                    macOS   Pushover

Needs Input                ✓        ✓
Permission Required        ✓        ✓
Plan Approval              ✓        ✓
Finished                    ✓        ✓
Failed                      ✓        ✓
Started                     -        -
```

Allow Pushover priority customization where useful without making the UI unnecessarily complex.

---

# 17. General Settings

Include:

```text
Launch ClaudeWatch at login
Show menu bar item
History retention
Listener status
Listener port
```

Display listener health:

```text
Local listener
● Running on 127.0.0.1:17831
```

Provide a button:

```text
Send Test Event
```

This should pass through the complete real application pipeline rather than bypassing it.

---

# 18. Launch at Login

Implement launch-at-login using Apple's ServiceManagement APIs.

Expose it as a normal setting.

Do not create or manually modify files in `~/Library/LaunchAgents`.

---

# 19. Menu Bar

Use `MenuBarExtra`.

Prefer `.window` style if it provides a better compact session overview.

The menu bar should not reproduce the full application.

Show at most the information needed for immediate awareness:

```text
ClaudeWatch

Needs Attention

● backend-api
  work · Needs Input

Running

● ios-app
  personal · Running

Recently Finished

✓ docs
  work · 4 min ago

────────────────────

Open ClaudeWatch
Pause Notifications
Quit
```

Use a menu bar symbol/state that indicates attention when at least one session requires action.

Do not constantly animate the menu bar icon.

---

# 20. Pause Notifications

Support temporarily pausing outbound notifications without disabling monitoring.

When paused:

- events are still received,
- sessions are still updated,
- history is still recorded,
- Pushover is not sent,
- native notifications are not sent.

Expose the paused state clearly in both main UI and menu bar.

---

# 21. Cloud Sessions

The architecture must be ready for cloud/remote Claude Code sessions.

Do not require cloud relay support for the first local-listener milestone, but do not bake assumptions into the domain model that all events originate locally.

Use:

```text
SessionSource.local
SessionSource.cloud
SessionSource.relay
```

A future relay may send the exact same normalized event envelope to ClaudeWatch or directly invoke Pushover.

Remote session identifiers and URLs must already be supported by the models.

Document the proposed future architecture:

```text
Claude Cloud Session
       ↓
Claude hook
       ↓
HTTPS relay
       ├── Pushover
       └── optional ClaudeWatch synchronization
```

Do not implement APNs or a cloud backend as part of the MVP unless explicitly requested.

---

# 22. Security

Security requirements:

1. Pushover secrets live only in Keychain.
2. Never log Pushover credentials.
3. Never persist Claude credentials.
4. Local listener binds only to `127.0.0.1`.
5. Incoming requests have a size limit.
6. Hook payloads cannot request arbitrary command execution.
7. Session messages are treated as untrusted strings.
8. Shell/process invocations use explicit argument arrays.
9. UI rendering must not interpret session content as executable content.
10. The application must function without broad filesystem scans.

Because this is a developer utility distributed outside the Mac App Store, do not spend substantial effort on App Store sandbox compatibility during MVP development if it interferes with required developer-tool integrations.

Keep the design compatible with future signing/notarization.

---

# 23. Logging

Use Apple's unified logging via `Logger`.

Create useful categories such as:

```text
listener
events
sessions
pushover
notifications
cswap
persistence
```

Never log secrets.

Avoid logging complete Claude prompts/messages at normal log levels.

---

# 24. Error Handling

The application must not crash because:

- Pushover is offline,
- notification permission was denied,
- `cswap` is unavailable,
- an unknown hook payload arrives,
- malformed JSON is posted,
- SwiftData contains an old historical event,
- the local listener port is already occupied.

Surface actionable errors in the UI.

For listener port conflicts, clearly show that the listener failed to start and allow changing the port.

---

# 25. Testing

At minimum create unit tests for:

## Hook normalization

Fixtures for:

- Stop/completion
- AskUserQuestion
- permission
- plan approval
- malformed payload
- unknown event

## State machine

Test transitions:

```text
running → needsInput
needsInput → running
running → finished
finished → running
running → failed
```

## Notification policy

Verify:

- disabled rules do not send,
- paused mode does not send,
- account-disabled mode does not send,
- Pushover and native channels are evaluated independently.

## Deduplication

Verify duplicate hook deliveries do not produce duplicate notifications.

## Pushover

Make the HTTP transport injectable so API behavior can be tested without real requests.

Do not make real Pushover requests in automated tests.

---

# 26. Project Organization

Prefer a feature/domain-oriented structure similar to:

```text
ClaudeWatch/
├── App/
│   ├── ClaudeWatchApp.swift
│   ├── AppState.swift
│   └── AppCommands.swift
│
├── Domain/
│   ├── ClaudeEvent.swift
│   ├── ClaudeEventType.swift
│   ├── SessionStatus.swift
│   └── SessionStateMachine.swift
│
├── Models/
│   ├── ClaudeSession.swift
│   ├── ClaudeEventRecord.swift
│   ├── ClaudeAccount.swift
│   └── NotificationRule.swift
│
├── Services/
│   ├── ClaudeEventListener.swift
│   ├── ClaudeEventProcessor.swift
│   ├── PushoverService.swift
│   ├── NativeNotificationService.swift
│   ├── KeychainService.swift
│   ├── AccountProvider.swift
│   ├── CSwapAccountProvider.swift
│   └── LaunchAtLoginService.swift
│
├── Features/
│   ├── Overview/
│   ├── Sessions/
│   ├── Accounts/
│   ├── Notifications/
│   └── Settings/
│
├── MenuBar/
│   └── MenuBarView.swift
│
└── Integration/
    └── claude-watch-hook.sh
```

Do not create abstractions solely for architectural aesthetics.

A small concrete type is preferable to an unnecessary protocol unless the boundary benefits from mocking, replacement, or isolation.

---

# 27. UX Principles

ClaudeWatch is a developer utility.

Optimize for:

- fast status recognition,
- low visual noise,
- native macOS conventions,
- keyboard usability,
- useful empty states,
- predictable behavior.

Use SF Symbols.

Do not create a custom design system.

Do not imitate an iOS application on macOS.

Use standard macOS:

- sidebars,
- tables/lists,
- forms,
- toolbar actions,
- context menus,
- confirmation dialogs.

Attention-required states may use semantic warning/accent styling but should not be visually aggressive.

---

# 28. MVP Milestones

Implement in this order.

## Milestone 1 — Application shell

- create macOS app
- SwiftData container
- sidebar navigation
- MenuBarExtra
- placeholder screens
- preferences infrastructure

The app must build and launch.

## Milestone 2 — Event pipeline

- local HTTP listener
- payload decoder
- normalizer
- event processor
- session state machine
- SwiftData persistence
- event history

Provide a development mechanism for posting fixture events.

## Milestone 3 — Native notifications

- authorization
- NativeNotificationService
- per-event rule handling
- click routing
- test notification

## Milestone 4 — Pushover

- Keychain storage
- configuration UI
- PushoverService
- test notification
- error handling
- URLs for remote sessions

## Milestone 5 — Full UI

- overview
- session list/detail
- event history
- notification rule editor
- settings
- listener health

## Milestone 6 — cswap integration

- executable discovery
- account provider
- account metadata
- account enable/disable
- graceful fallback

## Milestone 7 — Claude Code integration

- hook forwarding script
- example hook configuration
- real payload fixtures
- README setup instructions

## Milestone 8 — polish

- launch at login
- notification pause
- retention cleanup
- menu bar attention state
- error states
- tests

Do not attempt all milestones as one giant unverified change.

Build and test after each milestone.

---

# 29. Acceptance Criteria

The MVP is complete when all of the following work:

1. ClaudeWatch launches as a normal macOS application.
2. It also exposes a menu bar item.
3. Data survives application restarts through SwiftData.
4. Pushover credentials survive restarts through Keychain.
5. A Claude hook can POST an event to localhost.
6. The event appears in ClaudeWatch.
7. The corresponding session state updates.
8. A configured native macOS notification appears.
9. A configured Pushover notification is sent.
10. Either channel can be independently disabled.
11. Duplicate events do not cause duplicate notifications.
12. Notification history is visible.
13. Clicking a native notification opens the relevant session context.
14. `cswap` being missing does not break the application.
15. No Claude credentials are persisted by ClaudeWatch.
16. Launch-at-login can be enabled and disabled.
17. The app contains automated tests for the critical event pipeline.

---

# 30. Non-Goals for MVP

Do not implement unless required to satisfy another acceptance criterion:

- Claude authentication
- Claude API chat functionality
- editing Claude sessions
- terminal emulation
- APNs backend
- iOS companion app
- CloudKit synchronization
- collaborative/multi-user support
- analytics
- telemetry
- automatic software updates
- Mac App Store distribution
- custom server infrastructure
- complex plugin systems

---

# 31. Implementation Rules for Claude Code

When implementing this specification:

1. Inspect the repository before making architectural assumptions.
2. If an Xcode project already exists, preserve its existing conventions unless there is a concrete reason not to.
3. Verify current Claude Code hook schemas rather than guessing.
4. Verify actual `cswap` command/output behavior on the machine before implementing its decoder.
5. Prefer native Apple APIs.
6. Keep dependencies at zero unless a dependency clearly reduces complexity or risk.
7. Implement one milestone at a time.
8. Build after meaningful changes.
9. Run relevant tests after meaningful changes.
10. Fix warnings introduced by this project.
11. Do not silently skip failing tests.
12. Do not weaken security or disable validation to make tests pass.
13. Do not commit credentials, generated secrets, provisioning data, or local machine paths.
14. Keep README/setup documentation synchronized with implementation.
15. If the specification conflicts with an observed platform/API constraint, document the issue and choose the smallest reasonable adaptation.

---

# 32. Initial Deliverables

Before implementing substantial functionality:

1. inspect the repository,
2. produce a concise implementation plan mapped to the milestones above,
3. identify any platform assumptions that need verification,
4. then begin Milestone 1 without waiting for additional confirmation unless a destructive or externally visible action is required.

Continue through milestones while keeping the project buildable.

At the end, provide:

- summary of implemented functionality,
- relevant architectural decisions,
- build/test status,
- remaining limitations,
- exact Claude Code hook setup instructions.