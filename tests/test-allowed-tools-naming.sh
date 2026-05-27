#!/usr/bin/env bash
# test-allowed-tools-naming.sh — verify invoke.sh translates dotted MCP tool
# names in `gatewayAuthority` to the underscore form Claude Code's
# `--allowedTools` flag expects.
#
# Claude Code names MCP tools as `mcp__<server>__<tool>` and replaces dots in
# the tool name with underscores, so a permitted tool like
# `github.submit_patch` must be written `mcp__aux__github_submit_patch` in
# the allowlist or the call is silently denied.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

dispatch="$work/dispatch.json"
mcp_config="$work/mcp.json"
argv_file="$work/claude-argv"
outcome="$work/outcome.json"

jq -n '{
  prompt: "test",
  model: "claude-sonnet-4-5",
  maxTurns: 1,
  gatewayAuthority: ["github.submit_patch", "github.add_comment"],
  runtimeTools: ["Read"]
}' >"$dispatch"
echo '{}' >"$mcp_config"

mkdir -p "$work/bin"
install -m 0755 "$script_dir/fake-claude.sh" "$work/bin/claude"

AUX_DISPATCH_FILE="$dispatch" \
AUX_MCP_CONFIG_FILE="$mcp_config" \
AUX_OUTCOME_FILE="$outcome" \
FAKE_CLAUDE_ARGV_FILE="$argv_file" \
ANTHROPIC_API_KEY="fake-key" \
PATH="$work/bin:$PATH" \
  "$repo_root/runtimes/claude-code/invoke.sh"

if [[ ! -s "$argv_file" ]]; then
  echo "test failed: fake claude did not record argv at $argv_file" >&2
  exit 1
fi

allowed=$(grep -A1 -- '--allowedTools' "$argv_file" | tail -n1)
echo "recorded --allowedTools: $allowed"

# Both dotted entries must arrive at claude with dots flattened to underscores.
for expected in "mcp__aux__github_submit_patch" "mcp__aux__github_add_comment"; do
  if ! grep -qF "$expected" <<<"$allowed"; then
    echo "test failed: expected '$expected' in --allowedTools value, got '$allowed'" >&2
    exit 1
  fi
done

# And the dotted form must NOT leak through — that's the exact regression.
for forbidden in "mcp__aux__github.submit_patch" "mcp__aux__github.add_comment"; do
  if grep -qF "$forbidden" <<<"$allowed"; then
    echo "test failed: unexpected dotted entry '$forbidden' in --allowedTools value" >&2
    exit 1
  fi
done

echo "test passed: dotted MCP tool names are flattened to underscores in --allowedTools"
