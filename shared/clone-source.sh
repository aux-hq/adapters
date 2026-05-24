#!/usr/bin/env bash
# clone-source.sh — if the dispatch payload names a repository, clone it
# read-only into $AUX_SOURCE_DIR so the agent can read the code it works on.
#
# The token in the payload is short-lived and scoped to read-only contents, so
# it cannot push. We still strip it from the clone's remote afterward so it is
# never persisted in .git/config. All write side effects go through the Aux
# gateway (e.g. github.submit_patch), never `git push`.
set -euo pipefail

dispatch_file="${AUX_DISPATCH_FILE:-${RUNNER_TEMP:-/tmp}/aux-dispatch.json}"
source_dir="${AUX_SOURCE_DIR:-${RUNNER_TEMP:-/tmp}/aux-source}"

if [[ ! -f "$dispatch_file" ]]; then
  echo "clone-source: dispatch payload not found at $dispatch_file" >&2
  exit 1
fi

# First git workspace source, if any. Other kinds are ignored by this script.
git_source=$(jq -c 'first(.workspaceSources[]? | select(.kind == "git")) // {}' <"$dispatch_file")
repository=$(jq -r '.location // ""' <<<"$git_source")
token=$(jq -r '.access // ""' <<<"$git_source")

if [[ -z "$repository" || -z "$token" ]]; then
  echo "clone-source: no git workspace source in dispatch payload; skipping checkout"
  exit 0
fi

rm -rf "$source_dir"
git clone --depth 1 \
  "https://x-access-token:${token}@github.com/${repository}.git" "$source_dir"
# Strip the embedded credential so the agent cannot reuse it from .git/config.
git -C "$source_dir" remote set-url origin "https://github.com/${repository}.git"

echo "clone-source: cloned $repository into $source_dir"
