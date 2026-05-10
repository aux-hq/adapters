#!/usr/bin/env bash
# invoke.sh — run Claude Code with the dispatched prompt, model, max-turns,
# allowed-tool list, and Aux MCP config. Maps the result to a structured
# outcome written to $AUX_OUTCOME_FILE.
#
# Outcome rules:
#   exit 0 + JSON output with is_error=false  → success
#   exit 0 + JSON output with is_error=true   → fail   (reason from stop_reason)
#   any other case                            → error  (detail = tail of stderr)
#
# Credentials: prefers $CLAUDE_CODE_OAUTH_TOKEN (subscription auth) when set;
# otherwise uses $ANTHROPIC_API_KEY (API-key auth). Tenants set whichever they
# have as a repo secret; `secrets: inherit` from the caller exposes it here.
set -euo pipefail

dispatch_file="${AUX_DISPATCH_FILE:-${RUNNER_TEMP:-/tmp}/aux-dispatch.json}"
mcp_config="${AUX_MCP_CONFIG_FILE:-${RUNNER_TEMP:-/tmp}/aux-mcp.json}"
outcome_file="${AUX_OUTCOME_FILE:-${RUNNER_TEMP:-/tmp}/aux-outcome.json}"

if [[ ! -f "$dispatch_file" ]]; then
  echo "invoke: dispatch payload not found at $dispatch_file" >&2
  exit 1
fi
if [[ ! -f "$mcp_config" ]]; then
  echo "invoke: mcp config not found at $mcp_config" >&2
  exit 1
fi

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  jq -nc \
    --arg outcome error \
    --arg reason "missing claude credentials" \
    --arg detail "Set CLAUDE_CODE_OAUTH_TOKEN (subscription) or ANTHROPIC_API_KEY (API key) as a repo secret." \
    '{outcome: $outcome, reason: $reason, detail: $detail}' \
    >"$outcome_file"
  echo "invoke: no Claude credentials available" >&2
  exit 1
fi

prompt=$(jq -er '.prompt' <"$dispatch_file")
model=$(jq -er '.model' <"$dispatch_file")
max_turns=$(jq -er '.maxTurns' <"$dispatch_file")

allowed=""
gateway_tools=$(jq -r '(.gatewayAuthority // []) | .[]' <"$dispatch_file")
while IFS= read -r tool; do
  [[ -z "$tool" ]] && continue
  allowed+="mcp__aux__${tool},"
done <<<"$gateway_tools"

runtime_tools=$(jq -r '(.runtimeTools // []) | .[]' <"$dispatch_file")
while IFS= read -r tool; do
  [[ -z "$tool" ]] && continue
  allowed+="${tool},"
done <<<"$runtime_tools"
allowed="${allowed%,}"

stdout_file="${RUNNER_TEMP:-/tmp}/claude-stdout.log"
stderr_file="${RUNNER_TEMP:-/tmp}/claude-stderr.log"

# Build args without `--allowedTools ""` when no tools are configured.
args=(
  --print
  --output-format json
  --model "$model"
  --max-turns "$max_turns"
  --mcp-config "$mcp_config"
)
if [[ -n "$allowed" ]]; then
  args+=(--allowedTools "$allowed")
fi

set +e
claude "${args[@]}" -- "$prompt" >"$stdout_file" 2>"$stderr_file"
exit_code=$?
set -e

if [[ "$exit_code" -eq 0 ]] && jq -e . <"$stdout_file" >/dev/null 2>&1; then
  is_error=$(jq -r '.is_error // false' <"$stdout_file")
  stop_reason=$(jq -r '.stop_reason // empty' <"$stdout_file")
  result_text=$(jq -r '.result // empty' <"$stdout_file" | head -c 2048)

  if [[ "$is_error" == "true" ]]; then
    jq -nc \
      --arg outcome fail \
      --arg reason "${stop_reason:-agent reported error}" \
      --arg detail "$result_text" \
      '{outcome: $outcome, reason: $reason, detail: $detail}' \
      >"$outcome_file"
    echo "invoke: agent gave up (stop_reason=${stop_reason:-unknown})"
    exit 0
  fi

  jq -nc --arg outcome success '{outcome: $outcome}' >"$outcome_file"
  echo "invoke: agent succeeded"
  exit 0
fi

detail=$(tail -c 2048 "$stderr_file" 2>/dev/null || echo "")
jq -nc \
  --arg outcome error \
  --arg reason "claude exited with code $exit_code" \
  --arg detail "$detail" \
  '{outcome: $outcome, reason: $reason, detail: $detail}' \
  >"$outcome_file"
echo "invoke: claude exit_code=$exit_code" >&2
exit "$exit_code"
