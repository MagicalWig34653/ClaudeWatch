# Architecture

## Event pipeline

```text
Claude Code hook ──stdin JSON──▶ Integration/claude-watch-hook.sh ──POST──▶ 127.0.0.1:17831/v1/events
                                                                                  │
ClaudeEventListener (NWListener, app)                                             ▼
  HTTPRequestParser      (core)  size limits, Content-Length, no chunked bodies
  HookRequestRouter      (core)  path/method/content type/Origin checks → 200 "{}" / 4xx
  HookPayloadDecoder     (core)  lenient decoding, unknown fields ignored
        │  (response already sent; everything below is asynchronous)
        ▼
AppState.handle
  AccountService.alias   (app → core AccountResolver) best-effort, never blocks
  ClaudeEventNormalizer  (core)  the only Claude-specific mapping → ClaudeEvent
        ▼
ClaudeEventProcessor     (app, @MainActor, shared ModelContainer.mainContext)
  EventFingerprint + EventDeduplicator (core)
  SessionStateMachine    (core)  → ClaudeSession (SwiftData)
  ClaudeEventRecord      (SwiftData) history / dedup source
  NotificationPolicy     (core)  rule × global prefs × pause × account × duplicate
  NotificationContentBuilder (core)
        ├── NativeNotificationService (UserNotifications)
        └── PushoverService → PushoverClient (core, injectable HTTPTransport)
```

The core (`ClaudeWatchCore`, a local Swift package) has no UI or Apple-only
dependencies and is tested with `swift test` on macOS and Linux. The app target holds
SwiftData models, Apple-framework services and SwiftUI.

Both surfaces, the `Window` scene and the `MenuBarExtra`, get the same `AppState`
and the same `ModelContainer`. `@Query` views update whenever the processor saves.

### Notification click routing

`NativeNotificationService` (the `UNUserNotificationCenter` delegate) passes clicks to
`NotificationActionHandler`. That handler opens the session's `https` remote URL if there is
one. Otherwise it selects the session in `AppState` and brings up the main window,
through a captured `openWindow` action or, as a fallback, the `claudewatch://` URL
scheme, which the `Window` scene handles.

## Persistence

| Data | Store |
|---|---|
| Sessions, events, account metadata, notification rules | SwiftData at `~/Library/Application Support/ClaudeWatch/ClaudeWatch.store` |
| Preferences (menu bar, channels, sound, pause, retention, port, cswap path) | UserDefaults / `@AppStorage` |
| Pushover user key and application token | Keychain (generic password, service `<bundle id>.secrets`) |
| Launch at login | `SMAppService.mainApp` (system state) |

Enums are stored as stable raw strings. Records with unknown raw values, for example from
a newer build, are shown as-is and skipped by deduplication.

## Future: cloud / remote sessions

The domain already has `SessionSource.cloud` / `.relay`, `remoteSessionID` and
`remoteURL`. `ClaudeEvent` is `Codable`, so a relay can send the normalized envelope
unchanged. Proposed design (not implemented):

```text
Claude Code cloud session
        │  hook (type: "http" or command + curl)
        ▼
HTTPS relay (small serverless function, authenticated with a per-user relay token)
        ├── Pushover            (direct, works while the Mac is asleep)
        └── ClaudeWatch sync    (optional)
              e.g. ClaudeWatch polls/streams the relay with the relay token (stored in the
              Keychain) and feeds received ClaudeEvent envelopes into ClaudeEventProcessor
              with source = .relay / .cloud
```

Things this would need:

- The relay normalizes hook payloads with the same rules as `ClaudeEventNormalizer`, or
  forwards raw payloads and lets ClaudeWatch normalize them.
- Deduplication already works across sources, because fingerprints depend on the session,
  event type, turn and message, not on the transport.
- If the relay sends Pushover itself, ClaudeWatch should mark relayed events as "already
  notified". This would be a new flag on the envelope; `NotificationPolicy` would treat it
  like a duplicate for the Pushover channel.
- There is no APNs or custom backend in the MVP.
