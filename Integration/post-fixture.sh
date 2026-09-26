#!/bin/sh
# Development helper: posts a hook fixture to a running ClaudeWatch through the
# real hook script, e.g.
#   Integration/post-fixture.sh stop
#   Integration/post-fixture.sh pre-tool-use-ask-user-question my-session-id
#   Integration/post-fixture.sh ./some-payload.json
# Available fixtures: ClaudeWatchCore/Tests/ClaudeWatchCoreTests/Fixtures/hooks/
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$DIR/../ClaudeWatchCore/Tests/ClaudeWatchCoreTests/Fixtures/hooks"
if [ $# -lt 1 ]; then
  echo "usage: $0 <fixture-name|path.json> [session-id]" >&2
  for f in "$FIXTURES"/*.json; do basename "$f" .json; done >&2
  exit 64
fi
FILE="$1"
[ -f "$FILE" ] || FILE="$FIXTURES/$1.json"
[ -f "$FILE" ] || { echo "no such fixture: $1" >&2; exit 66; }
if [ $# -ge 2 ]; then
  case "$2" in
    ''|*[!A-Za-z0-9._:-]*) echo "session id may only contain letters, digits and . _ : -" >&2; exit 65 ;;
  esac
  sed "s/\"session_id\": *\"[^\"]*\"/\"session_id\": \"$2\"/" "$FILE" | "$DIR/claude-watch-hook.sh"
else
  "$DIR/claude-watch-hook.sh" < "$FILE"
fi
echo "posted $(basename "$FILE")"
