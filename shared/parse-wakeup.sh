#!/usr/bin/env bash
# parse-wakeup.sh — extract canonical AUX_* env vars from the wakeup payload.
#
# Reads the JSON-serialized client_payload from $AUX_PAYLOAD and exports the
# five wakeup fields to $GITHUB_ENV so subsequent steps can read them. The
# bearer token is masked in workflow logs.
set -euo pipefail

if [[ -z "${AUX_PAYLOAD:-}" ]]; then
  echo "parse-wakeup: AUX_PAYLOAD env var is empty" >&2
  exit 1
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "parse-wakeup: GITHUB_ENV is unset; this script must run inside GitHub Actions" >&2
  exit 1
fi

require_field() {
  local field=$1
  local value
  value=$(jq -er --arg f "$field" '.[$f] // empty' <<<"$AUX_PAYLOAD") || true
  if [[ -z "$value" ]]; then
    echo "parse-wakeup: required field '$field' missing from client_payload" >&2
    exit 1
  fi
  printf '%s' "$value"
}

stage_run_id=$(require_field aux_stage_run_id)
token=$(require_field aux_token)
dispatch_url=$(require_field aux_dispatch_url)
callback_url=$(require_field aux_callback_url)
gateway_url=$(require_field aux_gateway_url)

echo "::add-mask::$token"

{
  echo "AUX_STAGE_RUN_ID=$stage_run_id"
  echo "AUX_DISPATCH_URL=$dispatch_url"
  echo "AUX_CALLBACK_URL=$callback_url"
  echo "AUX_GATEWAY_URL=$gateway_url"
  echo "AUX_TOKEN<<__AUX_EOF__"
  echo "$token"
  echo "__AUX_EOF__"
} >>"$GITHUB_ENV"

echo "parse-wakeup: stage_run_id=$stage_run_id"
