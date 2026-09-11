# External executors: adapters and their limits

Six provider runners ship with the kit: `delegation-glm`, `delegation-kimi`,
`delegation-grok`, `delegation-qwen`, `delegation-deepseek`, and
`delegation-gemini`, plus `delegation-openai-compatible` for any
`/chat/completions` endpoint. Each runner is the sole enforcement authority for
its own transport, credentials, sandbox, tools, and refusals. Nothing in the
personal configuration, the router, or a skill can widen what a runner allows.

Which model runs is a user choice recorded in the personal configuration (see
[user configuration](user-configuration.md)). This page records what each
adapter can technically do, and what the lead still has to do afterwards.

## Adapters

| adapter | runner | transport | permission class | roles | efforts |
|---|---|---|---|---|---|
| `claude-zai` | `delegation-glm` | Claude Code CLI against the Z.AI endpoint | `read-only` (clerk, scout, reviewer, policy-annotation) · `worktree-edit` (builder) | clerk, scout, builder, reviewer, policy-annotation | max |
| `kimi-code-cli` | `delegation-kimi` | Kimi Code CLI in a macOS `sandbox-exec` profile | `read-only` (clerk, scout, policy-annotation) · `worktree-edit` (builder, frontend-builder) | clerk, scout, builder, frontend-builder, policy-annotation | max |
| `grok-build-cli` | `delegation-grok` | Grok Build CLI in its attested custom sandbox | `read-only` (policy-annotation) · `worktree-edit` (builder, frontend-builder) | builder, frontend-builder, policy-annotation | high |
| `token-plan-openai` | `delegation-qwen` | one chat-completions request | `text-patch` | builder, clerk, scout, reviewer, senior, judgement, policy-annotation | minimal … max (default xhigh) |
| `deepseek-api` | `delegation-deepseek` | one chat-completions request | `text-patch` | same as Qwen | minimal … max (default max) |
| `openai-compatible` | `delegation-openai-compatible` | one chat-completions request, HTTPS or loopback | `text-patch` | same as Qwen | none … max |
| `agy` | `delegation-gemini` | Antigravity CLI, prompt-only, empty isolated workspace | `read-only` | scout, builder, frontend-builder, reviewer, judgement | medium, high |

`<runner> check --json` is the authority for this table on a given machine. It
reports `model`, `adapter`, `roles`, `efforts`, `selected_backend`, and a
`backends` object whose `available` and `reason` fields say whether the runtime
can dispatch right now. Native runners add their runtime controls (sandbox,
process allowlist, OAuth mode, isolation). Run it immediately before a dispatch;
a runner that reports `selected_backend: "none"` will refuse with exit 69.

Gemini is excluded from the shipped presets. The adapter remains installed and
usable by adding a profile to the personal configuration.

## Permission classes

Exactly three, mutually exclusive, and fixed per adapter and role:

| class | worktree writes | returns a patch | what it means |
|---|---|---|---|
| `read-only` | no | no | The runner grants no write capability and the product is analysis text. |
| `text-patch` | no | yes | The runner has no filesystem; the product is patch text the lead applies and verifies. |
| `worktree-edit` | yes | no | The runner grants scoped write access to the delegated worktree and the executor edits in place. |

Assigning the builder role to a text adapter does not grant it a filesystem.
Its builder output is a unified diff, and the trust boundary sits where the lead
applies that diff, not where the runner stands.

## The patch verifier, for text-patch output

[`config/external-patch-policy.json`](../config/external-patch-policy.json) is
the versioned policy for that moment and `delegation-patch-verify` enforces it.
The verifier never applies a patch: it parses it, holds it against the policy,
fixes the strip level from the header shape, asks `git apply --check` whether
the patch applies at that one level, and prints a receipt with no patch content.

```sh
# 1. verify — read-only; nothing is applied and nothing is written
delegation-patch-verify check --patch "$patch" --workdir "$repo" --json >receipt.json

# 2. inspect the receipt: verdict, paths, operations, and the strip level
jq '{verdict, file_count, operations, strip, files: [.files[].path], violations}' receipt.json

# 3. the LEAD applies it, with the strip level the receipt recorded
git -C "$repo" apply -p"$(jq -r '.strip.chosen' receipt.json)" -- "$patch"

# 4. the LEAD runs the tests — provider output is never proof that a change works
( cd "$repo" && ./run-tests.sh )
```

The default policy is fail-closed: unified diff text only; no absolute,
traversing, or non-representable paths; denied paths (`.git`, hooks, CI, `.env*`,
shell startup files, keys, credential stores, this kit's provider auth
directories); new files only as `100644`, no symlinks, submodules, or mode
changes; add and modify only, delete refused unless `--allow-delete`, rename and
copy refused with no override; bounded file count, bytes, lines, hunks, and added
lines; a strip level fixed by the header shape and never guessed. The verifier
attests its own read-only behaviour by digesting the patch, worktree, index, and
git control directory before and after, and reports `attestation-failed` with
exit 70 if anything moved. `delegation-patch-verify policy --json` prints the
installed policy; `tests/external-patch-verify.sh` is its regression suite.

## Model identity

Every runner records the requested model separately from what the provider
reported:

| field | meaning |
|---|---|
| `requested_model` | what the profile asked for, never read from a response |
| `provider_reported_model` | the model the provider named in its response, or `null` |
| `model_identity_source` | `provider-reported` when a response named the requested model or a configured alias; `requested-only` when the provider named nothing |

A response that names a *different* model is a silent substitution and fails
every run with exit 70 (`provider_identity_mismatch`), unless the name was
declared in the profile's `model_aliases`. A provider report is not independent
certification of anything, and `requested-only` is not a defect: several
transports never surface a content model. For Grok, `usage_model`
(`grok-4.6-build`) is the billing participant, not the content identity.

## Exit codes

| code | retryable | meaning |
|---|---|---|
| 64 | no | invalid input: unknown argument, missing or colliding path, refused flag combination |
| 69 | no | unavailable: runtime, login, entitlement, key, or quota |
| 70 | no | dispatch, sandbox, identity, extraction, or publication failure |
| 75 | **yes** | temporary: rate limit, overload, 5xx, timeout, credential lock |
| 78 | no | the adapter does not support the requested role or effort |
| 130 | no | the caller interrupted (Kimi); the runner stopped the child and released its locks |

Failures write a sanitized `<output>.error.json` (phase, reason, sizes, exit
codes) and publish no output or metrics. Raw provider responses are preserved
only under an explicit `--debug-dir`, mode 700.

## Flags retired in 0.25.0

`--evaluation`, `--evaluation-manifest`, and `--preflight-only` no longer
exist; passing them is an unknown argument (exit 64). `--allow-provisional` is
accepted as a deprecated no-op for one more release and only prints a warning.
The frozen artifacts under `evaluation/` are an archive and are not read by any
command.
