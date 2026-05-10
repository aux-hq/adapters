#!/usr/bin/env bash
# install.sh — install Claude Code (the @anthropic-ai/claude-code npm package).
#
# If the `claude` binary is already on PATH (test mode, pre-built runner image),
# the install is skipped — this keeps the script idempotent and lets integration
# tests inject a stub binary.
#
# Pin via $CLAUDE_CODE_VERSION (default: latest).
set -euo pipefail

if command -v claude >/dev/null 2>&1; then
  echo "install: claude already on PATH at $(command -v claude)"
  claude --version || true
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "install: npm is required to install @anthropic-ai/claude-code but is not available" >&2
  exit 1
fi

version="${CLAUDE_CODE_VERSION:-latest}"
echo "install: installing @anthropic-ai/claude-code@$version"
npm install -g "@anthropic-ai/claude-code@$version"
claude --version
