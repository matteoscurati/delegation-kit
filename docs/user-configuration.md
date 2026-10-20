# User configuration

Models are user choices. No benchmark, gate, or kit qualification authorizes
or blocks a profile; the adapter's technical limits and the lead's verification
of the actual result are the only checks. The starting profiles ship in
`config/presets.json`.

## Configure

`delegation-config init` creates the personal configuration
(`"schema_version": 2`) at
`${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/config.json`; a file that
still declares `1` is read identically. Set
`DELEGATION_CONFIG_FILE` to use a different file. Project-local configuration
is never discovered automatically. An existing configuration is preserved.

`delegation-config validate` validates locally without accessing providers.
`show` displays validated configuration with credential variable names only.
`apply` regenerates `managed/profiles.json` and conservative native Claude and
Codex snippets next to the user configuration. Edited snippets are preserved
and listed in the output. These snippets are available for explicit host
integration; `delegation-run` always reads the configuration directly. Native
host profiles supplied by the kit retain their existing permissions.

A complete configuration for an existing provider and a local endpoint:

```json
{
  "schema_version": 2,
  "review_policy": "optional",
  "profiles": {
    "my-deepseek": {
      "adapter": "deepseek-api",
      "model": "deepseek-flash",
      "family": "deepseek",
      "roles": ["builder", "reviewer"],
      "credential_env": "DEEPSEEK_API_KEY",
      "parameters": {"effort": "max", "max_tokens": 4096, "timeout": 120}
    },
    "local-model": {
      "adapter": "openai-compatible",
      "model": "my-local-model",
      "family": "my-model-family",
      "roles": ["clerk", "builder", "reviewer"],
      "base_url": "http://127.0.0.1:8080/v1",
      "parameters": {"max_tokens": 2048, "timeout": 60}
    }
  }
}
```

Use the actual model identifier your endpoint accepts; it need not exist in any
kit benchmark. `family` is a user declaration for review policy, not model
attestation. `aliases` is an optional list of explicitly accepted response model
identifiers. Inline credentials, unknown fields and unsupported parameters are
rejected. Remote endpoints require HTTPS; loopback HTTP is permitted. The
custom adapter appends `/chat/completions`, uses one non-streaming text request,
optional Bearer authentication, and never calls `/models`, tools or a retry.

Gemini is excluded from the shipped presets by the owner's decision. The
adapter stays installed and usable by adding a profile by hand. Existing
personal configurations are preserved rather than silently rewritten.

## Adapter limits

| Adapter | Parameters | Execution boundary |
|---|---|---|
| `deepseek-api`, `token-plan-openai` | effort, max_tokens, timeout | Prompt only; text patch |
| `openai-compatible` | max_tokens, timeout | Prompt only; text patch |
| `agy` | effort: medium/high, timeout | Isolated prompt-only native runtime |
| `kimi-code-cli` | effort: max, timeout | Existing per-role sandbox; no senior/reviewer/judgement implementation |
| `claude-zai` | effort: max, timeout | Existing per-role native sandbox |
| `grok-build-cli` | effort: high, timeout | Existing builder sandbox |
| `codex`, `claude-code` | effort supported by the adapter, timeout | Native CLI; common entry is read-only/prompt-only |

## Timeouts

A dispatch has no time limit unless the profile sets `timeout` (seconds, at
most 86400). The kit does not decide how long a delegated task may take: a run
that hangs waits until you interrupt it, and Kimi and Grok hold their OAuth
lock for as long as it runs. When `timeout` is set it bounds the whole run on
every adapter: the process is killed after the deadline plus a ten-second
grace, no output or metrics are published, the diagnostic names `timeout`,
and the exit code is 75. The chat-completions adapters pass it to curl as the
request deadline (`deadline_exceeded`); Gemini passes it to `agy` as
`--print-timeout`, which otherwise receives 24h. Two guards stay regardless:
a 20-second connect timeout on HTTP adapters, and the ten-second probes that
`check` runs against a CLI. Neither judges the task.

Roles never grant capabilities. Custom `builder` means a textual patch, not
permission to edit. Native credential storage and restrictions remain in place;
`credential_env` is supported for the three HTTP adapters only. Without an
override, Qwen/DeepSeek retain their existing credential file lookup. Native
CLI model inventory and sandbox probes remain technical prerequisites.

## Selection and execution

```sh
delegation-route resolve --lane builder --json
delegation-route resolve --lane builder --selected-profile local-model --json
# Only after the user explicitly requested this dispatch:
delegation-run --profile local-model --lane builder \
  --prompt-file /tmp/task.txt --output /tmp/model-result.txt --workdir /path/to/repo
```

The router's schema 3 JSON reports `configuration_valid`,
`technical_compatibility` and `capabilities` per profile and role.
`check`, `lane`, `profile`, `resolve` and `table` remain read-only commands.
A selected row is validation only: `authorization_granted` remains false.

The runner emits output, metrics and a version 2 `.result.json` receipt.
Requested and reported model identities are distinct. Missing identity is
`requested-only`; a match or configured alias is `provider-reported`, never
independent certification. An unconfigured mismatch fails. HTTP authentication,
rate limiting, malformed output, truncation and timeout have separate diagnostic
reasons; failure never dispatches a replacement.

## Review

`optional` is the default for new and migrated installs. `required` allows the
same family; `cross-family` requires both families to be declared and different.
Neither mandatory policy grants authorization for a reviewer call.

`--reviewer-profile ID --review-authorized` records an explicitly authorized
review plan, but does not call the reviewer. Required results remain
`pending-review` until the lead obtains and verifies that review. Without
review authorization the detailed state is `pending-authorization`; without
a compatible reviewer it stays pending as well. Optional results are
`ready-for-integration`, which is not a claim that tests or review passed.

`delegation-config init --preset strict` selects cross-family policy for a new
configuration. For an existing configuration explicitly change `review_policy`
and run `apply`; `init` never overrides later user decisions.

## Router

A `router` block names the decider — `decider`, required: one of
your profiles, Sage, Jev, a Dipylon, a local classifier, or `none` — and the
profiles it may pick from (`pool`, `default`, HTTP or native). Profiles may declare
routing metadata — `tier`, `code`, `price`, `context`, `json_mode` — which
otherwise comes from the shipped `config/catalog.json`. Without the block the
router is off; nothing else in the kit reads it. See [the router page](router.md) for the fields, the policy
and what each response discloses.

## Keys and environment

Nothing in the kit holds a key value: profiles name a variable, services
name a variable. A variable comes from, in this order: your environment;
the personal `.env` beside the configuration file
(`${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/.env`, or beside
`$DELEGATION_CONFIG_FILE`); for the adapters that have one, the kit's key
file under the data home. The installer creates the `.env` once from the
repository's `.env.example`, with mode 600 and every value empty, and never
overwrites it; fill in only the keys you use. The commands, the runners and
`delegation-run` read it; `doctor` reports its mode and how many variables
it sets, never their values. The variables a user sets:

| variable | meaning |
|---|---|
| `DELEGATION_CONFIG_FILE` | the personal configuration (default `${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/config.json`) |
| `DELEGATION_DATA_HOME` | commands, runners, key files, receipts and the local catalog (default `~/.local/share/delegation-kit`) |
| `DELEGATION_BIN_HOME` | where the installer links the commands (default `~/.local/bin`) |
| `CLAUDE_HOME`, `CODEX_HOME` | the host homes the installer writes profiles and the guard into |
| the name in a profile's `credential_env` | that profile's key, for the HTTP adapters |
| the name in `router.decider.credential_env` | the decision service's key (`SAGE_API_KEY`, `TYPESAFE_API_KEY` by default) |
| `AA_API_KEY` | the Artificial Analysis key for `delegation-router catalog refresh` |

Key files, read when the variable is unset in the environment and in the
`.env`, one `NAME=value` line each, mode 600, under
`$DELEGATION_DATA_HOME/config/`:

| file | variable | used by |
|---|---|---|
| `zai.env` | `ZAI_API_KEY` | `claude-zai` profiles |
| `qwen-token-plan.env` | `QWEN_TOKEN_PLAN_API_KEY` | `token-plan-openai` profiles |
| `deepseek.env` | `DEEPSEEK_API_KEY` | `deepseek-api` profiles |
| `artificial-analysis.env` | `AA_API_KEY` | `delegation-router catalog refresh` |

Every one of these files — the `.env` and the key files — is parsed, never
executed, and ignored when it is a symlink or readable by group or others.
The uninstaller keeps every key file beside the data home as
`<data home>.<name>.env.bak` and the installer restores it; the `.env`
lives in the configuration directory, which neither touches. There is no
`.env` in a project: the kit never reads one, and a key in a worktree would
be one `git add` away from a commit. The repository's `.env.example` is a
template with no values, and `.gitignore` keeps every other `.env*` out.

## Adding a model

Add a profile to the personal file, then `delegation-config validate` and
`delegation-config apply`. Nothing else in the kit has to change: choose the
adapter, the exact model identifier the endpoint accepts, the roles and the
parameters the adapter supports; for a custom OpenAI-compatible endpoint add
`base_url` and, if it needs a key, `credential_env` with the *name* of the
variable. The adapter owns capabilities — a `builder` role on a text adapter
yields a patch, never write access — and unsupported parameters are errors.
Declare `tier`, `price`, `code`, `context` or `json_mode` when the router
should rank the profile on your numbers rather than the catalog's. The
catalog's tiers come from the Artificial Analysis Intelligence Index through
a published band rule; `delegation-router catalog show` prints the source of
every tier and `catalog refresh`, with your key in `AA_API_KEY` or in
`$DELEGATION_DATA_HOME/config/artificial-analysis.env` (mode 600), writes a
current catalog beside the key files. See [the router page](router.md).

## Upgrading

The installer never overwrites the personal file; new keys are optional and
a file that still says `schema_version: 1` is read like `2`. Installs older than 0.25, which
kept their profiles in `routing-gates.json`, were migrated by 0.25 and 0.26;
that migration is gone, so bring such an install through 0.26 first or
recreate the profiles by hand from the shipped preset.

0.27.2 moves the shipped `opus-builder`, `opus-reviewer` and
`opus-policy-annotator` profiles to `claude-opus-5-5`. A personal file made
earlier keeps `claude-opus-5` in those profiles until you change their
`model`; the Claude Code agents the installer writes move to Opus 5.5 on the
next install either way.
