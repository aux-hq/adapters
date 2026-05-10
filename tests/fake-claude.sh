#!/usr/bin/env bash
# fake-claude.sh — PATH-shadowed `claude` binary used by the integration test.
#
# Behavior is controlled by $FAKE_CLAUDE_OUTCOME:
#   success | unset → exit 0, print JSON with is_error=false (→ outcome=success)
#   fail            → exit 0, print JSON with is_error=true  (→ outcome=fail)
#   error           → exit 1, write to stderr                (→ outcome=error)
set -euo pipefail

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
