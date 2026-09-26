#!/bin/sh
# Forwards a Claude Code hook payload (JSON on stdin) to ClaudeWatch.
#
# ClaudeWatch owns normalization, deduplication, session state and notification
# policy; this script only relays. It prints nothing and always exits 0, so it
# can never block or alter Claude Code, even when ClaudeWatch is not running.
PORT="${CLAUDE_WATCH_PORT:-17831}"
case "$PORT" in
  ''|*[!0-9]*) exit 0 ;;
esac
curl --silent --max-time 2 --connect-timeout 1 --noproxy '*' \
  -H 'Content-Type: application/json' -H 'Expect:' \
  --data-binary @- "http://127.0.0.1:${PORT}/v1/events" >/dev/null 2>&1
exit 0
