# aux-hq/adapters

Reusable GitHub Actions runtime adapter for [Aux](https://github.com/jasoneisen/aux) — a control plane for governed AI agent task execution.

Aux dispatches one bounded run (one stage of one Task) to a runtime adapter that executes inside a sandboxed environment. This repo provides the GitHub Actions adapter: a single reusable workflow that internally branches on stage **kind** and (for agent kinds) **runtime**.

## The "one PR ever" principle

A tenant repo is installed once by the Aux GitHub App. Every future capability — new stage kinds, new runtimes, new gateway features — ships in this repo and reaches tenants automatically via the `@v1` moving major tag. **The only future tenant-side action ever needed is adding a new repo secret** when a new runtime requires a new credential. That's a settings change, not a PR.

## Tenant install

Install once. The Aux App's install PR adds a single 5-line caller workflow to your repo:

```yaml
# .github/workflows/aux.yml
on:
  repository_dispatch:
    types: ['*']
jobs:
  run:
    uses: aux-hq/adapters/.github/workflows/dispatch.yml@v1
    secrets: inherit
    with:
      payload: ${{ toJSON(github.event.client_payload) }}
```

`secrets: inherit` exposes whatever credentials are in repo settings. The dispatcher picks the right one at runtime based on the resolved runtime — no per-secret naming in the workflow.

## What's inside

```
.github/workflows/
  dispatch.yml             # the single tenant-facing reusable workflow
  ci.yml                   # shellcheck + actionlint on every push/PR
  integration-test.yml     # end-to-end test against a stub Aux endpoint
shared/
  parse-wakeup.sh          # extract AUX_* env from client_payload
  fetch-dispatch.sh        # GET AUX_DISPATCH_URL with AUX_TOKEN, parse the stage payload
  post-outcome.sh          # POST AUX_CALLBACK_URL with the structured outcome
kinds/
  agent.sh                 # branches on $AUX_RUNTIME → runtimes/<runtime>/
runtimes/
  claude-code/
    install.sh
    generate-mcp-config.sh
    invoke.sh
tests/
  stub-server.py           # stub for /dispatch + /result used in CI
  fake-claude.sh           # PATH-shadowed `claude` binary used in CI
```

## Wakeup payload

Aux delivers five fields via `repository_dispatch.client_payload`:

| Field               | Description                                                      |
| ------------------- | ---------------------------------------------------------------- |
| `aux_stage_run_id`  | Identifier of the stage run.                                     |
| `aux_token`         | Per-StageRun HMAC bearer token. Authenticates all three calls.   |
| `aux_dispatch_url`  | `GET` URL — returns the full stage payload.                      |
| `aux_callback_url`  | `POST` URL — accepts the structured outcome.                     |
| `aux_gateway_url`   | URL Claude Code's MCP client uses to reach the Aux MCP gateway.  |

## Dispatch payload (agent kind)

```json
{
  "kind": "agent",
  "runtime": "claude-code",
  "prompt": "...",
  "model": "claude-sonnet-4-5",
  "maxTurns": 7,
  "gatewayUrl": "...",
  "gatewayAuthority": ["..."],
  "runtimeTools": ["..."],
  "cliCommands": ["..."],
  "stageTimeout": "00:30:00"
}
```

`gatewayAuthority` lists tool names the agent may call through the Aux MCP gateway; `runtimeTools` lists in-runtime tools (e.g. Claude Code's built-in `Read`, `Write`). The adapter unions them into Claude Code's `--allowedTools` list.

## Outcome callback

```json
{ "outcome": "success" }
{ "outcome": "fail",  "reason": "max_turns", "detail": "..." }
{ "outcome": "error", "reason": "claude exited with code 1", "detail": "..." }
```

The adapter always posts an outcome — even on failure — so Aux is told about errors.

## Supported `kind` × `runtime` matrix

| Kind  | Runtime       | Status              |
| ----- | ------------- | ------------------- |
| agent | `claude-code` | supported in v1.0.0 |

Future runtimes (`codex`, `aider`, …) and stage kinds (`script`, `http`, `wait`) plug into the existing branches without changing the workflow's external contract.

## Secret name conventions

Tenants set credentials in repo secrets. The adapter resolves them by convention.

### `runtime: claude-code`

| Secret                    | Use                                                                                |
| ------------------------- | ---------------------------------------------------------------------------------- |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code subscription auth (Pro/Max). **Preferred** when both are set.          |
| `ANTHROPIC_API_KEY`       | Anthropic API-key auth. Used if `CLAUDE_CODE_OAUTH_TOKEN` is not set.              |

If neither is set, the adapter posts `outcome=error` with reason `missing claude credentials`.

## Hooks

**v1.0.0 ships with no in-runtime hooks.** All external-call enforcement and external-action telemetry lives server-side in the [Aux MCP gateway](https://github.com/jasoneisen/aux), which is immune to prompt-injection attempts that tell the agent to ignore its tool list. Adding a hook layer here would be redundant.

## Versioning

Tenants pin a major tag. Minor and patch tags are non-breaking. New `kind`s and new `runtime`s are additive (new branch in the existing dispatcher) and do not bump the major.

| Tag      | What it means                                                                  |
| -------- | ------------------------------------------------------------------------------ |
| `@v1`    | **Recommended.** Moving major — picks up non-breaking additions automatically. |
| `@v1.0.0` | Immutable release tag.                                                         |

Breaking changes (a new tenant-side requirement, a wakeup-payload schema change) ship behind `@v2` with a migration note.

## Adding a new runtime

Plumbing this into the dispatcher is a one-place change:

1. Add `runtimes/<new-runtime>/{install,generate-mcp-config,invoke}.sh`.
2. Add a case in `kinds/agent.sh`.
3. Add a row to the support matrix above.
4. (If the runtime needs a new credential) Add a secret-name row.
5. Tag a new minor (`v1.1.0`).

No change to `dispatch.yml`, no change to `shared/`, no tenant-side PR.

## Adding a new stage kind

1. Add `kinds/<new-kind>.sh`.
2. Add a case in `dispatch.yml`'s "Dispatch by kind" step.
3. Add a payload-shape row to the docs above.
4. Tag a new minor.

## Local development

```sh
# Static analysis (matches CI)
shellcheck -x shared/*.sh kinds/*.sh runtimes/**/*.sh tests/*.sh
actionlint -color
```

The integration test pipeline can be exercised end-to-end on any Linux host by emulating the GitHub Actions environment — see `.github/workflows/integration-test.yml` for the canonical recipe.

## License

Public repo. License TBD.
