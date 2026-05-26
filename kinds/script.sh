#!/usr/bin/env bash
# script.sh — dispatcher for kind=script. Executes the dispatched command and
# maps its exit code to a stage outcome via the payload's exitCodeSemantics.
#
# Default mapping: 0 → success, anything else → fail.
# Overrides in exitCodeSemantics.overrides re-map specific exit codes to one
# of {Success, Fail, Error}.
#
# Honors the dispatch payload's `timeout` for the command. The runner's own
# job timeout is the outer guard when the payload provides none.
#
# The script runs inside the read-only source checkout when the payload names
# a workspace source, so relative paths (e.g. `bash .aux/test.sh`) resolve
# against the task's repo rather than the runtime checkout.
#
# Authority: operators express what's permitted via the stage's
# allowedCliCommands list, but the adapter does not enforce a sandbox — it
# trusts the command string. The dispatch payload is signed and tenant-scoped,
# so the trust boundary is the control plane.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

dispatch_file="${AUX_DISPATCH_FILE:-${RUNNER_TEMP:-/tmp}/aux-dispatch.json}"
outcome_file="${AUX_OUTCOME_FILE:-${RUNNER_TEMP:-/tmp}/aux-outcome.json}"
source_dir="${AUX_SOURCE_DIR:-${RUNNER_TEMP:-/tmp}/aux-source}"
export AUX_SOURCE_DIR="$source_dir"

if [[ ! -f "$dispatch_file" ]]; then
  echo "script: dispatch payload not found at $dispatch_file" >&2
  exit 1
fi

# Optional read-only checkout of the task's repo. No-op when the payload
# names none — kept consistent with the agent path so callers don't have to
# remember which kind clones.
"$repo_root/shared/clone-source.sh"

command_str=$(jq -er '.command' <"$dispatch_file")
timeout_str=$(jq -r '.timeout // ""' <"$dispatch_file")

# Parse .NET TimeSpan ToString("c") format: [d.]hh:mm:ss[.fffffff].
# Returns the duration in whole seconds, or an empty string when unparseable
# (the caller treats that as "no timeout").
parse_timespan_seconds() {
  local ts="$1"
  [[ -z "$ts" ]] && return
  local days=0 rest="$ts"
  if [[ "$ts" =~ ^([0-9]+)\.([0-9]+:[0-9]+:[0-9]+.*)$ ]]; then
    days="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
  fi
  local h m s
  IFS=: read -r h m s <<<"$rest"
  s="${s%%.*}"
  if [[ ! "$h$m$s" =~ ^[0-9]+$ ]]; then
    return
  fi
  echo $(( 10#$days * 86400 + 10#$h * 3600 + 10#$m * 60 + 10#$s ))
}

timeout_seconds=$(parse_timespan_seconds "$timeout_str")

# Run inside the source checkout when one exists, so relative paths resolve.
if [[ -d "$source_dir/.git" ]]; then
  cd "$source_dir"
fi

echo "script: running command: $command_str"
[[ -n "$timeout_seconds" ]] && echo "script: timeout=${timeout_seconds}s"

set +e
if [[ -n "$timeout_seconds" ]]; then
  timeout "${timeout_seconds}s" bash -c "$command_str"
else
  bash -c "$command_str"
fi
exit_code=$?
set -e

echo "script: command exited with $exit_code"

# Resolve outcome via exitCodeSemantics.overrides first, falling back to the
# default mapping (0 → success, anything else → fail). Keys in `overrides`
# are stringified integers (JSON object keys); look up the exit code as-is.
override=$(jq -r --arg c "$exit_code" '.exitCodeSemantics.overrides[$c] // ""' <"$dispatch_file")
case "$override" in
  Success) outcome="success" ;;
  Fail)    outcome="fail" ;;
  Error)   outcome="error" ;;
  "")
    if [[ "$exit_code" -eq 0 ]]; then
      outcome="success"
    else
      outcome="fail"
    fi
    ;;
esac

if [[ "$outcome" == "success" ]]; then
  jq -nc --arg outcome success '{outcome: $outcome}' >"$outcome_file"
else
  jq -nc \
    --arg outcome "$outcome" \
    --arg reason "command exited with code $exit_code" \
    '{outcome: $outcome, reason: $reason}' >"$outcome_file"
fi

echo "script: outcome=$outcome"
