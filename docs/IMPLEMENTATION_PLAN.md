# ClaudeWatch — Implementation Plan & Deviations

This document maps the work to the milestones in `SPEC.md` and records every
material deviation together with the reason for it.

## Verified facts (not assumptions)

| Topic | How it was verified | Result |
|---|---|---|
| Repository | `git log`, file listing | Only `SPEC.md`; no Xcode project existed. |
| Dev environment | `uname`, toolchain probing | Linux container, no Xcode. Swift 6.1 is available through the `swift:6.1-noble` Docker image, so platform-independent code can be compiled and unit-tested on Linux. The macOS app target is built and tested on a GitHub Actions macOS runner (`.github/workflows/ci.yml`). |
| Claude Code hook format | Ran Claude Code 2.1.283 with a hook that dumps stdin; read the hook input schemas from the installed CLI | Payloads are a JSON object on stdin with `session_id`, `transcript_path`, `cwd`, `hook_event_name`, plus event-specific fields (`tool_name`, `tool_input`, `permission_suggestions`, `last_assistant_message`, `notification_type`, `message`, `error`, `error_details`, `reason`, `prompt_id`, …). Fixtures in `ClaudeWatchCore/Tests/ClaudeWatchCoreTests/Fixtures/hooks` are real captures with machine paths replaced. |
| Hook config format | Same run | `{"hooks": {"<Event>": [{"matcher": "…", "hooks": [{"type": "command", "command": "…"}]}]}}`. Claude Code also supports `{"type": "http", "url": "…"}` hooks, which send `Content-Type: application/json` with a `Content-Length` (verified against a local capture server). |
| `AskUserQuestion` / `ExitPlanMode` | CLI schema + tool schema | Exposed as tool events (`PreToolUse` / `PermissionRequest` with `tool_name` `AskUserQuestion` or `ExitPlanMode`). `tool_input.questions[].question` holds question text; `tool_input.plan` holds the plan (optional). Not reproducible in headless `claude -p` mode (tools disabled), so these two fixtures are built from the real envelope plus the documented `tool_input` schema. |
| `Notification` hook | CLI schema | `message`, optional `title`, `notification_type` ∈ `permission_prompt`, `idle_prompt`, `elicitation_dialog`, `agent_needs_input`, … |
| `StopFailure` hook | CLI schema | `error` ∈ `rate_limit`, `authentication_failed`, `server_error`, …; optional `error_details`. |
| `cswap` | Installed `claude-swap` 0.26.0 (PyPI) into an isolated HOME, registered fake API-key accounts, captured real output | `cswap list --json` → `{"schemaVersion":1,"activeAccountNumber":…,"accounts":[{"number","email","alias"?,"active","disabled"?,…}]}`; `cswap status --json` → `{"schemaVersion":1,"active":null | {"number","email","alias"?,"managed",…}}`. `cswap run` sessions use `CLAUDE_CONFIG_DIR=~/.claude-swap-backup/sessions/<n>-<email-slug>` on macOS, so `transcript_path` identifies the account for per-session runs. |

## Milestone plan

| Milestone | Deliverables | Where |
|---|---|---|
| 1 — Shell | Xcode project (macOS 14, SwiftUI, SwiftData), `Window` + `MenuBarExtra` sharing one `ModelContainer` and one `AppState`, sidebar, preferences (`AppStorage`) | `ClaudeWatch.xcodeproj`, `ClaudeWatch/App` |
| 2 — Event pipeline | Loopback `NWListener`, HTTP request parser, `HookPayloadDecoder`, `ClaudeEventNormalizer`, `SessionStateMachine`, `EventDeduplicator`, `ClaudeEventProcessor`, SwiftData models, fixture posting script | `ClaudeWatchCore`, `ClaudeWatch/Services`, `Integration/post-fixture.sh` |
| 3 — Native notifications | `NativeNotificationService` (authorization state, no re-prompting after denial, foreground presentation, sounds), `NotificationActionHandler` click routing | `ClaudeWatch/Services` |
| 4 — Pushover | `KeychainService`, `PushoverClient` (injectable transport), settings UI with test button, human-readable errors, remote URL support | `ClaudeWatchCore/Pushover`, `ClaudeWatch/Features/Notifications` |
| 5 — Full UI | Overview, sessions list/detail/history, rule editor, settings with listener health and "Send Test Event" (goes through the real HTTP listener) | `ClaudeWatch/Features` |
| 6 — cswap | Executable discovery (known paths + login shell `command -v`), `CSwapAccountProvider`, account metadata & enable/disable, graceful fallback | `ClaudeWatchCore/Accounts`, `ClaudeWatch/Features/Accounts` |
| 7 — Claude Code integration | `Integration/claude-watch-hook.sh`, example settings, real fixtures, README | `Integration/`, `README.md` |
| 8 — Polish | Launch at login (`SMAppService`), pause, retention cleanup, menu bar attention icon, error states, tests | throughout |

## Deviations and why

1. **Platform-independent core as a local Swift package (`ClaudeWatchCore`).**
   The spec suggests one app target with `Domain/`, `Services/`, …. Payload
   decoding, normalization, the state machine, deduplication, notification
   policy, notification text, the HTTP request parser, the Pushover client and
   the cswap decoder have no UI or Apple-only dependencies. Putting them in a
   package isolates Claude-specific parsing (a spec requirement), and makes the
   critical pipeline testable with `swift test` on any machine, including this
   Linux environment. SwiftData models, `NWListener`, `UserNotifications`,
   Keychain, `ServiceManagement` and the UI stay in the app target.
2. **Low-signal activity events are not all persisted.** With a `PostToolUse`
   hook on every tool, persisting each tool call would flood history. Activity
   events (prompt submitted, tool finished, …) update the session's
   `updatedAt`, and are stored as `ClaudeEventRecord` only when they change the
   session status (e.g. `needsInput → running`). All attention, completion,
   failure, start and end events are always stored, including duplicates
   (flagged `isDuplicate`) for debugging.
3. **Extra event types.** In addition to the spec's list, the normalized
   `ClaudeEventType` has `activity`, `sessionEnded` and `idle` (Claude Code's
   `idle_prompt` notification). Their notification rules default to disabled.
4. **`ClaudeEvent` carries two extra fields**: `turnID` (Claude Code's
   `prompt_id`, observed in real payloads) so that two turns that end with the
   same text are not mistaken for duplicates, and `isSupplementary`, set for
   events derived from the generic `Notification` hook. A supplementary event
   never produces a second notification for a state that a specific hook
   (e.g. `PermissionRequest`) has just reported.
5. **Notification click routing uses a `claudewatch://session/<id>` URL.**
   The notification delegate records the target session in `AppState`, then
   opens the app URL; the main `Window` scene handles it via
   `handlesExternalEvents`, which also reopens the window if it was closed.
   Remote sessions open their `remoteURL` instead.
6. **Browser requests are rejected by the listener.** Besides binding to
   `127.0.0.1` and requiring `application/json`, requests carrying an `Origin`
   header get `403`, which closes the "web page POSTs to localhost" hole.
7. **No App Sandbox**, as allowed by §22: the app has to run `cswap` and the
   user's login shell. Hardened Runtime is on so the app can be notarized.
8. **Pushover priority is limited to −2…1.** Emergency priority (2) requires
   retry/expire receipts, which adds UI and API surface the spec does not ask for.
9. **No separate `Project` model.** Project name and working directory are stored on
   each `ClaudeSession` (and each event record). A separate model would have no
   behavior of its own in the MVP; it can be introduced once projects carry settings.
10. **"Mark as Finished" for active sessions.** Active sessions cannot be deleted. A
    Claude Code process that is killed never sends `Stop`/`SessionEnd`, so instead of
    allowing deletion of "active" sessions, the UI offers an explicit Mark as Finished
    action that goes through `SessionStateMachine`. The session can then be deleted
    normally.
11. **Xcode 26 and macOS 26 CI runners.** The app icon is an Icon Composer document,
    which only Xcode 26 compiles. CI runs on `macos-26`: compiling the icon with Xcode
    26.3 on macOS 15 failed, while Xcode 26.6 on macOS 26 renders it. The deployment
    target stays macOS 14; Xcode generates the fallback `.icns`.
