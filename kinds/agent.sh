#!/usr/bin/env bash
# agent.sh — dispatcher for kind=agent. Branches on $AUX_RUNTIME and chains
# the install / configure / invoke scripts for that runtime.
#
# A new runtime is added by creating runtimes/<runtime>/{install,generate-mcp-config,invoke}.sh
# and adding a case branch here. No other file changes are required.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

runtime="${AUX_RUNTIME:-claude-code}"
outcome_file="${AUX_OUTCOME_FILE:-${RUNNER_TEMP:-/tmp}/aux-outcome.json}"

case "$runtime" in
  claude-code)
    "$repo_root/runtimes/claude-code/install.sh"
    "$repo_root/runtimes/claude-code/generate-mcp-config.sh"
    "$repo_root/runtimes/claude-code/invoke.sh"
    ;;
  *)
    echo "agent: unsupported runtime '$runtime'" >&2
    jq -nc \
      --arg outcome error \
      --arg reason "unknown runtime" \
      --arg detail "Adapter does not support runtime '$runtime'. Supported: claude-code." \
      '{outcome: $outcome, reason: $reason, detail: $detail}' \
      >"$outcome_file"
    exit 1
    ;;
esac
