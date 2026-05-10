#!/usr/bin/env bash
# generate-mcp-config.sh — write a Claude Code MCP config that points the agent
# at the Aux gateway with the per-StageRun bearer token.
#
# Tool surface comes from the gateway's tools/list — there is no per-tool
# configuration in this file.
set -euo pipefail

if [[ -z "${AUX_GATEWAY_URL:-}" || -z "${AUX_TOKEN:-}" ]]; then
  echo "generate-mcp-config: AUX_GATEWAY_URL or AUX_TOKEN is empty" >&2
  exit 1
fi

# Canonical path; invoke.sh reads from the same default. Not exported via
# $GITHUB_ENV because invoke.sh runs in the same workflow step (chained from
# agent.sh) and $GITHUB_ENV is only processed between steps.
config_file="${AUX_MCP_CONFIG_FILE:-${RUNNER_TEMP:-/tmp}/aux-mcp.json}"

jq -n \
  --arg url "$AUX_GATEWAY_URL" \
  --arg auth "Bearer $AUX_TOKEN" \
  '{
     mcpServers: {
       aux: {
         type: "http",
         url: $url,
         headers: { Authorization: $auth }
       }
     }
   }' \
  >"$config_file"

echo "generate-mcp-config: wrote $config_file"
