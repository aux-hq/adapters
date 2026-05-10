#!/usr/bin/env bash
# fetch-dispatch.sh — GET the full stage payload from $AUX_DISPATCH_URL.
#
# Writes the response body to $AUX_DISPATCH_FILE (default: $RUNNER_TEMP/aux-dispatch.json)
# and exports AUX_KIND (and, for agent kinds, AUX_RUNTIME) to $GITHUB_ENV.
set -euo pipefail

if [[ -z "${AUX_DISPATCH_URL:-}" || -z "${AUX_TOKEN:-}" ]]; then
  echo "fetch-dispatch: AUX_DISPATCH_URL or AUX_TOKEN is empty" >&2
  exit 1
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "fetch-dispatch: GITHUB_ENV is unset; this script must run inside GitHub Actions" >&2
  exit 1
fi

payload_file="${AUX_DISPATCH_FILE:-${RUNNER_TEMP:-/tmp}/aux-dispatch.json}"

http_status=$(curl -sS -o "$payload_file" -w '%{http_code}' \
  -H "Authorization: Bearer $AUX_TOKEN" \
  -H 'Accept: application/json' \
  "$AUX_DISPATCH_URL")

if [[ "$http_status" != "200" ]]; then
  echo "fetch-dispatch: expected HTTP 200, got $http_status" >&2
  head -c 4096 "$payload_file" >&2 || true
  exit 1
fi

if ! jq -e . <"$payload_file" >/dev/null; then
  echo "fetch-dispatch: response body is not valid JSON" >&2
  exit 1
fi

kind=$(jq -er '.kind' <"$payload_file")
{
  echo "AUX_KIND=$kind"
  echo "AUX_DISPATCH_FILE=$payload_file"
} >>"$GITHUB_ENV"

if [[ "$kind" == "agent" ]]; then
  runtime=$(jq -r '.runtime // "claude-code"' <"$payload_file")
  echo "AUX_RUNTIME=$runtime" >>"$GITHUB_ENV"
  echo "fetch-dispatch: kind=agent runtime=$runtime"
else
  echo "fetch-dispatch: kind=$kind"
fi
