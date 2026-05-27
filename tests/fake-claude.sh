#!/usr/bin/env bash
# fake-claude.sh — PATH-shadowed `claude` binary used by the integration test.
#
# Behavior is controlled by $FAKE_CLAUDE_OUTCOME:
#   success | unset → exit 0, print JSON with is_error=false (→ outcome=success)
#   fail            → exit 0, print JSON with is_error=true  (→ outcome=fail)
#   error           → exit 1, write to stderr                (→ outcome=error)
#
# If $FAKE_CLAUDE_ARGV_FILE is set, the binary writes its received argv (one
# argument per line) to that file so tests can assert on the constructed
# command — e.g. that --allowedTools entries use Claude Code's underscore form
# for dotted MCP tool names.
set -euo pipefail

if [[ -n "${FAKE_CLAUDE_ARGV_FILE:-}" ]]; then
  printf '%s\n' "$@" >"$FAKE_CLAUDE_ARGV_FILE"
fi

if [[ "${1:-}" == "--version" ]]; then
  echo "fake-claude 1.0.0"
  exit 0
fi

case "${FAKE_CLAUDE_OUTCOME:-success}" in
  fail)
    cat <<'JSON'
{"is_error": true, "stop_reason": "max_turns", "result": "agent gave up after max turns", "session_id": "fake-session", "num_turns": 5}
JSON
    ;;
  error)
    echo "fake-claude: simulated runtime error" >&2
    exit 1
    ;;
  *)
    cat <<'JSON'
{"is_error": false, "stop_reason": "end_turn", "result": "ok", "session_id": "fake-session", "num_turns": 1}
JSON
    ;;
esac
