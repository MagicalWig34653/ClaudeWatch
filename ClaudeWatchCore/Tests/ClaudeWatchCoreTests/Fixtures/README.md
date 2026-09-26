# Test fixtures

## `hooks/`

Claude Code hook payloads (stdin JSON), captured from Claude Code 2.1.283 by a hook that
dumps its input. Machine-specific paths and IDs were replaced with `/Users/example/...`
and a fixed session ID; prompt/assistant text was replaced with neutral examples.

Captured verbatim (apart from the substitutions above): `session-start`,
`user-prompt-submit`, `pre-tool-use-bash`, `permission-request-bash`,
`post-tool-use-failure-bash`, `stop`, `session-end`.

Built from a captured envelope plus the hook/tool input schema shipped in the same
Claude Code build, because the events cannot be triggered in headless mode:
`pre-tool-use-ask-user-question`, `permission-request-ask-user-question`,
`pre-tool-use-exit-plan-mode`, `permission-request-exit-plan-mode`,
`notification-permission-prompt`, `notification-idle-prompt`, `stop-failure`.

Negative cases: `malformed.json` (truncated JSON), `missing-session-id.json`,
`unknown-event.json` (a real but unhandled event name, `TeammateIdle`).

## `cswap/`

Real output of claude-swap 0.26.0 (`cswap list --json`, `cswap status --json`) in an
isolated HOME with two placeholder API-key accounts (`work` active, `personal` disabled),
plus the empty-state output.
