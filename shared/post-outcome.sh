#!/usr/bin/env bash
# post-outcome.sh — POST the recorded stage outcome to $AUX_CALLBACK_URL.
#
# Reads the structured outcome from $AUX_OUTCOME_FILE. If that file does not
# exist (the adapter aborted before any kind/runtime script wrote one), an
# "error" outcome is synthesized with the tail of any captured stderr.
#
# Retries up to 3 times with linear backoff. The endpoint is idempotent.
set -euo pipefail

if [[ -z "${AUX_CALLBACK_URL:-}" || -z "${AUX_TOKEN:-}" ]]; then
  echo "post-outcome: AUX_CALLBACK_URL or AUX_TOKEN is empty — cannot report outcome" >&2
  exit 1
fi

outcome_file="${AUX_OUTCOME_FILE:-${RUNNER_TEMP:-/tmp}/aux-outcome.json}"

if [[ ! -f "$outcome_file" ]]; then
  stderr_file="${AUX_STDERR_FILE:-${RUNNER_TEMP:-/tmp}/aux-stderr.log}"
  detail="adapter exited before recording an outcome"
  if [[ -f "$stderr_file" ]]; then
    detail+=$'\n'"$(tail -c 2048 "$stderr_file")"
  fi
  jq -nc \
    --arg outcome error \
    --arg reason "adapter aborted before completion" \
    --arg detail "$detail" \
    '{outcome: $outcome, reason: $reason, detail: $detail}' \
    >"$outcome_file"
fi

response=$(mktemp)
trap 'rm -f "$response"' EXIT

attempt=1
max_attempts=3
while :; do
  status=$(curl -sS -o "$response" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer $AUX_TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary "@$outcome_file" \
    "$AUX_CALLBACK_URL" || echo "000")

  if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
    outcome=$(jq -r '.outcome' <"$outcome_file")
    echo "post-outcome: callback accepted (HTTP $status, outcome=$outcome)"
    exit 0
  fi

  echo "post-outcome: callback returned $status (attempt $attempt/$max_attempts)" >&2
  head -c 2048 "$response" >&2 || true

  if (( attempt >= max_attempts )); then
    exit 1
  fi
  sleep $(( attempt * 2 ))
  attempt=$(( attempt + 1 ))
done
