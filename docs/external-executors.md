# The common external-executor contract

Six external executor families are reachable from this kit — GLM, Kimi, Grok,
Qwen, DeepSeek, and Gemini. Each has its own runner, its own transport, its own
sandbox, and its own reasons for refusing. That is deliberate, and this page does
not change it.

What was missing was a **shared vocabulary**: the same words for the same things
across six runners, so drift is detectable instead of invisible.
[`config/external-executor-contract.json`](../config/external-executor-contract.json)
is that vocabulary, and `delegation-executor-contract` validates it.

## The boundary, stated once

- **The common contract describes and validates.** It is a declaration of what
  each runner already does, checked against
  [`config/routing-gates.json`](../config/routing-gates.json) and each
  executable `config/*-routing.json` gate.
- **Each provider runner remains the sole enforcement authority.** Permission
  enforcement stays runner-specific and explicit: `delegation-kimi` builds its
  own sandbox profile and tool allowlist, `delegation-grok` attests its own
  sandbox, `delegation-glm` chooses its own Claude Code permission mode, and the
  text-only bridges have no filesystem at all.
- **Declaring a lane grants it nothing.** No permission, no route, no capability
  is created by an entry in this file. If the contract and a runner disagree,
  the runner wins at runtime and the disagreement is a validation failure to be
  fixed in the contract — never a reason to widen a runner.
- **There is no universal dispatch layer, and none is planned here.** No runner
  reads the contract; the regression suite asserts that. The contract is
  inspected by people and by CI, not by dispatch code.

## Permission classes

Exactly three, mutually exclusive, and exhaustive over every declared lane:

| class | worktree writes | returns a patch | what it means |
|---|---|---|---|
| `read-only` | no | no | The runner grants no write capability and the lane's product is analysis text. |
| `text-patch` | no | yes | The runner has no filesystem write capability; the lane returns patch text the lead applies and verifies. |
| `worktree-edit` | yes | no | The runner grants scoped write access to the delegated worktree and the executor edits in place. |

`text-patch` is separated from `read-only` because the two impose different work
on the lead: a diff still has to be applied and checked. Mutual exclusivity is
mechanical — each class carries a distinct `(worktree_writes, returns_patch)`
pair, and the validator rejects a contract in which two classes collide, a fourth
class appears, or one of the three is removed.

Two descriptive fields sit alongside the class and are checked against it:

- `worktree_access` — `none` (prompt-only transports), `read`, or `read-write`.
- `tool_policy.write_scope` — `none` or `workdir`. Runner-private scratch space
  is not a worktree write and is deliberately out of scope.

`worktree-edit` requires `read-write` + `workdir`; every other class requires
`write_scope: none` and forbids `read-write`.

## Runtime controls, and how drift is caught

Every lane declares a complete `tool_policy`. There is no optional field and no
`null`: `permission_mode`, `allowed_tools`, `write_scope`, `terminal`,
`network`, `mcp`, `plugins`, and `subagents` are all mandatory, and a missing,
null, or unrecognised value fails `check`.

The five capability fields use a closed two-value vocabulary, because there are
exactly two honest things to say about them:

| value | meaning |
|---|---|
| `denied` | The runner removes the capability — an explicit deny, an omission from a runner-passed tool allowlist, or a transport with no such tool at all. |
| `permission-mode-gated` | The runner does **not** remove it. Whether a call succeeds follows from the permission mode the runner pins. |

`permission-mode-gated` is a deliberately narrowed claim. `delegation-glm`
launches Claude Code with `--permission-mode plan` (or `acceptEdits` for
builder), `--setting-sources ''`, and `--strict-mcp-config`. That authoritatively
denies MCP and plugins, but it passes no tool allowlist — so terminal, network,
and subagent availability follow from the pinned mode, and the contract says
exactly that instead of claiming a denial it cannot substantiate. `allowed_tools`
is `null` for the same reason, and only a permission-mode lane is allowed to
leave it null.

Each lane's controls are mirrored in that family's executable
`config/*-routing.json` gate under
`lanes.<lane>.backends.<backend>.runtime_controls`, and `check` compares all ten
security-relevant fields **exactly**:

`permission_mode`, `worktree_edits`, `worktree_access`, `write_scope`,
`terminal`, `network`, `mcp`, `plugins`, `subagents`, `tools`.

A gate row without a `runtime_controls` object, missing one of the ten, or
carrying a field the contract does not declare, fails. This is the fail-closed
part: a check is never skipped because a field happens to be absent. Gates may
carry additional descriptive keys — `sandbox`, `oauth_modes`, `max_turns`,
`timeout_seconds`, and the rest listed in
`executable_gate_controls.descriptive_fields` — and the contract makes no claim
about those.

### Isolation metadata is a claim, so it is checked

The two isolation keys are the exception, because an overstated isolation claim
reads as a security property. `isolated_home` and `isolated_config_dir` are
listed in `executable_gate_controls.isolation_cross_checked_against` and compared
against the family's `runtime_isolation`: a gate row that states one must state
exactly the declared value, and a family that declares one must have it stated by
at least one row of its own gate. A row may omit an isolation key — it then
claims nothing — but it may never claim an isolation the family does not declare.

The distinction the two keys draw is deliberate:

| key | claim |
|---|---|
| `isolated_home` | the runner pins a private `HOME` for an **ordinary** dispatch, not merely inside an evaluation harness |
| `isolated_config_dir` | only the harness's own configuration directory is redirected per run |

`delegation-glm` is the case that forced the distinction. An ordinary GLM
dispatch sets `CLAUDE_CONFIG_DIR` to a per-run temporary directory and leaves
`HOME` as the caller's; only the evaluation path runs under `env -i` with a
temporary `HOME`. So every GLM lane declares `isolated_home: false` and
`isolated_config_dir: true`, and the regression suite pins both. Kimi, Grok, and
Gemini do isolate `HOME` on an ordinary run and declare `isolated_home: true`;
the two chat-completions bridges have no home to isolate and declare neither.

`runtime_controls` is metadata. No runner and no router reads it; `tests/routing-gates.sh`
asserts that stripping it from every external gate changes no route decision.

## Current declarations

| family | runner | transport | lanes with a class other than read-only |
|---|---|---|---|
| `glm-5.3-flash` | `delegation-glm` | Claude Code against Z.AI | `builder` → `worktree-edit` (`acceptEdits`) |
| `kimi-k3` | `delegation-kimi` | native Kimi Code CLI | `builder`, `frontend-builder` → `worktree-edit` |
| `grok-4.6` | `delegation-grok` | Grok Build CLI | `builder`, `frontend-builder` → `worktree-edit` |
| `qwen3.8-max` | `delegation-qwen` | chat-completions | `builder` → `text-patch` |
| `deepseek-v4-pro` | `delegation-deepseek` | chat-completions | `builder` → `text-patch` |
| `gemini-3.7-flash` | `delegation-gemini` | Antigravity, prompt-only | `builder`, `frontend-builder` → `text-patch` |

Every other declared lane is `read-only`, and every judgement, reviewer, and
policy-annotation lane is non-dispatchable. Blocked and candidate lanes are
declared so the contract stays complete, and the validator refuses a contract in
which any of them becomes dispatchable.

Run `delegation-executor-contract table` for the full 35-row picture.

## Identity, usage, permission, qualification

Four things that are routinely conflated are kept apart:

| concept | field | what it proves |
|---|---|---|
| requested identity | `identity.requested_model`, `requested_model` | what the gate told the runner to pin — never read from a provider response |
| observed / effective identity | `observed_identity_sources`, `effective_content_model` | what the provider says actually produced the content |
| usage participation | `usage_participation`, `usage_participants` | that a model appears in the provider's own billing accounting — **not** that it wrote the content |
| permission class | `permission_class` | what the runner is allowed to touch |
| qualification status | `status` / `selection` | whether the lane may be dispatched at all, and how |

Usage participation is graded, because the transports genuinely differ:
`first-party-model-usage` (GLM), `model-usage-participants` (Grok),
`provider-usage-totals` (Qwen, DeepSeek), and `none` (Kimi, Gemini). Where it is
`none`, the zero and null token counters are recorded as *absent measurement*,
never as measured cost.

Each family declares an identity contract that `validate --family` enforces on
a real artifact:

- `effective_content_identity` — `must-equal-requested` (GLM, Grok) or
  `not-reported` (the rest). A family that does not report an effective-content
  model may not carry one; a family that does may not carry a different one.
- `usage_participant_model` — the name a participant must carry to count as the
  target. For GLM it is the model itself; for Grok it is `grok-4.6-build`, the
  billing SKU, which is **not** the content identity. Reporting the billing name
  as `effective_content_model` fails.
- `usage_participant_provider` / `usage_participant_canonical_model` — GLM's
  first-party accounting additionally requires `provider: firstParty` and a
  matching `canonicalModel`; Grok's does not, and the contract does not pretend
  otherwise.

`target_usage_participant_present` is true **exactly when** a participant carries
the declared usage-participant model. An artifact with an empty participant list
that still claims the target participated — and still claims
`exact_model_identity_attested` — is rejected. So is an identity attestation
without the effective-content model that substantiates it, a participant object
with an undeclared key or a negative counter, a negative token, cost, or
duration, a `finished_at_epoch` before `started_at_epoch`, a duration longer than
the window it claims, a `usage_source` that contradicts the participant list, and
a status envelope that lists a lane as qualified when the family declares it
provisional.

The participant map is closed by **type** as well as by key. Every field a
participant actually carries is checked against the type declared in
`usage_accounting.participant_fields`, including the nullable ones: the optional
provider identity fields `canonical_model` and `provider` may be a name or
`null` and nothing else, and each token, cache, reasoning, call, and cost counter
must be a nonnegative number. `input_tokens: "ten"` and `cost_usd: "free"` fail;
they are not coerced to zero. The result envelope's token counter object is typed
the same way through `token_counter_value_type`, so `tokens.input: "ten"` fails
too. Type checking reaches the declared envelope fields, that participant map,
and that counter object; provider extension objects are governed by
`extension_policy` instead, and the contract does not claim to type them.

Lane lists in a status envelope are an inventory, not a sample. `qualified_lanes`
and `provisional_lanes` — and `candidate_lanes`, for the runners that emit it —
must equal exactly the lanes the contract puts in that state for the family.
Listing a lane the family declares provisional as qualified fails, and so does
quietly dropping one. A runner that emits no `candidate_lanes` at all is not
required to start; every runner derives these lists from
`config/routing-gates.json`, which the contract is cross-checked against in both
directions.

## Exit codes

The dispatch vocabulary is closed at six values, and the validator rejects any
seventh:

| code | name | retryable | meaning |
|---|---|---|---|
| 64 | `invalid_input` | no | unknown argument, missing/colliding path, refused flag combination |
| 69 | `unavailable` | no | runtime, login, entitlement, key, or quota-window unavailability |
| 70 | `dispatch_failure` | no | dispatch, sandbox, extraction, or publication failure |
| 75 | `temporary_failure` | **yes** | rate limit, overload, 5xx, timeout, transient credential conflict |
| 78 | `gate_refusal` | no | lane not dispatchable, effort not pinned, gates inconsistent, explicit decision missing |
| 130 | `caller_cancelled` | no | the caller interrupted; the runner stopped the child and released its locks |

64/69/70/75/78 are universal — every family must emit them. 130 is not: only a
runner with cancellation handling (today, `delegation-kimi`) declares it.

**These are the runners' codes.** `delegation-executor-contract` is an inspector
and uses its own: `0` ok, `64` invalid input, `65` validation failure, `66`
unreadable file, `69` missing dependency.

## Envelopes

Three artifacts, with a *common minimum* that all six families genuinely emit
today:

| envelope | produced by | common required fields |
|---|---|---|
| status | `<runner> check --json` | `model`, `efforts`, `selected_backend`, `qualified_lanes`, `provisional_lanes`, `backends` |
| result | `<runner> run --metrics <path>` | `model`, `backend`, `effort`, `lane`, `started_at_epoch`, `finished_at_epoch`, `tokens`, `provider_cost_usd` |
| diagnostic | `<runner> run`, on failure, at `<output>.error.json` | `phase`, `reason` |

The diagnostic minimum is small on purpose: it is what is *true today*, not what
would be convenient. `delegation-kimi` names its envelope `schema`, carries
`exit_code`/`vendor_exit_code`, and omits `model`/`backend`/`effort`/`lane`;
`delegation-grok` omits `schema_version` and calls the debug pointer
`debug_path`. Those are recorded in `known_divergences` rather than papered over,
and each family additionally declares the fields *it* guarantees — so
`validate --family glm-5.3-flash` requires the identity fields GLM really emits
while `--family kimi-k3` does not.

### What is normative, and what is not

- **Normative and fail-closed:** the contract file itself. Every map in it is
  closed by key — `vocabularies`, `authority`, `identity_kinds`,
  `usage_participation_values`, `usage_accounting.participant_fields`, each
  lane's `tool_policy`, each family's `identity`, `extension_policy`,
  `executable_gate_controls`, and the envelope declarations. An unknown key
  anywhere, an unknown permission class or capability, a seventh exit code, or a
  lane that contradicts the central gate or an executable gate all fail `check`.
  The two maps that stay open by key are `families` and each family's `lanes`,
  because their key sets are cross-checked bidirectionally against
  `routing-gates.json` and the executable gates — an invented family or lane has
  nowhere to hide.
- **Normative for artifacts:** required fields, declared types — for envelope
  fields, for every participant field a participant carries, and for every
  counter in the token object — closed vocabularies, exact lane inventories, the
  family identity and usage-accounting invariants above, and nonnegative/ordered
  numeric fields.
- **Supported, and filtered:** provider extension fields. Each runner emits its
  own attestations — Kimi's `search_runtime` digests, Grok's sandbox and OAuth
  state, GLM's assistant-event identity accounting — and `validate` reports them
  as `extension_fields` and passes. Rejecting them would push runners toward a
  lowest common denominator, which is precisely the weakening this contract must
  not cause.

What extensions may **not** do is carry a credential or raw provider content.
`extension_policy` rejects, recursively and at any depth, a key whose name is a
credential or raw-content name (`api_key`, `authorization`, `token`,
`credential`, `secret`, `prompt`, `messages`, `request_body`, `response_body`,
`raw_response`, `stdout`, `stderr`, and the rest of the declared list), a key
containing a credential substring (`access_token`, `client_secret`,
`private_key`, …), and a string value shaped like a bearer token or a PEM private
key. Digests of sensitive material — `prompt_sha256`, `contract_sha256` — are the
safe form and stay allowed, as do benign names that merely contain a sensitive
word, such as Grok's `credential_state_shared` boolean.

Be precise about what that buys: it is a **name and shape filter, not a secrecy
proof.** It cannot detect a credential stored under an innocuous key name, and
the contract says so in `extension_policy.notes`. Beyond it, `validate` reads
back and prints only field names, declared vocabulary values, and its own
findings; an offending value is reported as `<credential-shaped value>` and never
echoed. Raw provider material belongs only under an explicit private
`--debug-dir`.

## Using it

```sh
delegation-executor-contract check --json      # contract + both gate cross-checks
delegation-executor-contract families          # the six families and their lanes
delegation-executor-contract family kimi-k3    # one family, in full
delegation-executor-contract classes           # the three permission classes
delegation-executor-contract exit-codes        # the closed dispatch vocabulary
delegation-executor-contract table             # every declaration, as Markdown

delegation-executor-contract validate --envelope result \
  --file "$metrics" --family grok-4.6 --json
```

`check` is what CI, `doctor.sh`, and a gate change should run. It validates the
contract, then cross-checks every declaration against `routing-gates.json`
(model, harness, effort, status, selection, and coverage in **both** directions)
and against each executable gate (model, lane set, status, selection, effort, and
all ten `runtime_controls` fields, which every gate row must declare in full).

Overrides, for tests and diagnostics only:
`DELEGATION_EXECUTOR_CONTRACT_FILE`, `DELEGATION_ROUTING_GATES_FILE`,
`DELEGATION_EXECUTOR_GATE_DIR`.

## Changing it

A contract edit is a *description* change and must follow reality:

1. Change the runner first, if runner behaviour is what moved. The contract never
   leads.
2. Update the declaration **and** the matching `runtime_controls` block in the
   family's executable gate — they are compared exactly, so one without the other
   fails — then run `tests/external-executor-contract.sh`.
3. Never edit a lane's `status`/`selection` here to make `check` pass. Those
   mirror `config/routing-gates.json`, and a promotion remains an explicit owner
   decision made in the gates — see [`../CLAUDE.md`](../CLAUDE.md).
4. If a runner genuinely diverges from the common envelope, record it in
   `known_divergences`. A recorded gap is honest; a silently relaxed required
   field is not.
