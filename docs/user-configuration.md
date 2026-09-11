# User configuration

Models are user choices. No benchmark, gate, or kit qualification authorizes
or blocks a profile; the adapter's technical limits and the lead's verification
of the actual result are the only checks. The starting profiles ship in
`config/presets.json`.

## Configure

`delegation-config init` creates schema version 1 at
`${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/config.json`. Set
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
  "schema_version": 1,
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
| `agy` | effort: medium/high | Isolated prompt-only native runtime |
| `kimi-code-cli` | effort: max | Existing per-role sandbox; no senior/reviewer/judgement implementation |
| `claude-zai` | effort: max | Existing per-role native sandbox |
| `grok-build-cli` | effort: high | Existing builder sandbox |
| `codex`, `claude-code` | effort supported by the adapter | Native CLI; common entry is read-only/prompt-only |

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

## Migration

Before the installer replaces distributed configuration it snapshots the old
configuration directory as `migration-v1-backup` next to the personal config.
The original model choices and supported parameters are imported, credential
files remain in place, and the summary announces optional review. The backup is
retained on repeated initialization/installations. The personal file and later
policy changes are preserved.

`--allow-provisional` remains accepted as a deprecated no-op for one release.
A legacy `routing-gates.json` that does not parse, or has no profiles, falls
back to the shipped preset; the snapshot is kept either way. The installer
removes the retired gate, contract, and evidence files from the data directory.
