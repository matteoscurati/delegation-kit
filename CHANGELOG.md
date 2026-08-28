# Changelog

All notable changes to delegation-kit are documented here.

## Unreleased

### Changed

- Staged `glm-5.3-flash` / `claude-zai` / `max` as the sole GLM replacement
  candidate. The corrected v2 task pack passed 9/9 no-retry operational checks
  at score 1.0 with every builder checker green, but strict identity is `VOID`:
  retained v2 evidence did not record separately surfaced effective content
  identity or complete `modelUsage`. No lane is promoted; this does not establish
  what the provider originally exposed. Historical GLM-5.3 receipts
  and the earlier OpenRouter ox-alpha diagnostic remain contextual.
- Keep Claude Code and Bun temporary paths inside the evaluation scratch and
  preserve `USER` in the sanitized environment. The first Flash attempt never
  reached the provider because the frozen native CLI tried to create
  `/tmp/claude-501`; that attempt remains a terminal `VOID`.

## [0.18.0] — 2026-08-27

### Added

- Added `delegation-grok run --oauth shared` for concurrent Grok Build workers.
  Operational runs share one runner-owned persistent `GROK_HOME` generation,
  use the vendor auth lock for refresh coordination, and hold the kit lock only
  for generation adoption and atomic publication. External `grok login` wins a
  conflict; corrupt or superseded OAuth state fails closed. Evaluations remain
  serialized.

### Fixed

- Serialized Grok runs now hold an OAuth lock for the complete dispatch and
  atomically publish validated refreshed credentials back to the ambient login,
  instead of deleting a refreshed token with the ephemeral HOME. Sandbox
  attestation uses a unique per-run profile and ignores peer/malformed events;
  the agent cannot edit the credential, policy, or attestation files. Superseded
  credential generations are bounded instead of accumulating at rest.

### Verified

- The 0.18.0 release candidate passed all 12 regression suites in 52 seconds,
  59 routing checks, ShellCheck, evidence validation, version consistency, and
  `git diff --check`. A real two-worker Grok 4.6/high smoke returned `PONG`
  twice in about five seconds, left both workspaces empty, and finished with
  ambient/shared OAuth hashes aligned. The provider did not separately expose
  the effective content model, so the smoke is operational compatibility proof,
  not strict model-identity evidence. The installed release candidate matched
  source across the changed runner, gates, and skills; the live doctor command
  completed with `57 OK, 0 WARN, 0 FAIL`.

## [0.17.0] — 2026-08-18

### Changed

- Reworked the native routing policy so Sonnet and Luna are limited to very
  small, non-builder clerk/scout/routine-review tasks. The former
  `sonnet-builder` and `terra-scout` profiles are retired; the old
  `opus-reviewer/high` profile is replaced by a max-effort cross-family reviewer.
- Added `opus-builder` at `claude-opus-5` / `max` and made it the fallback to
  the default `terra-builder` at `gpt-5.6-terra` / `max`. Added separate
  read-only `opus-reviewer` and `terra-reviewer` profiles, also at `max`, so both
  high-level models can build or review without mixing permissions.
- Added an explicit model-family registry and fail-closed cross-family review
  rule. Every routine/material/security review resolution now requires the
  producer profile or family, removes all same-family reviewers, and exposes the
  exclusions in the router output. Runtime availability must still be checked;
  no eligible reviewer means stop, not self-review.
- This is a breaking routing migration: callers resolving a review lane must
  now pass `--producer-profile` or `--producer-family`; omission exits `64`
  instead of selecting a potentially same-family reviewer.
- Promoted security review from the former manual Opus-only route to
  producer-aware provisional defaults/fallbacks across Sol, Terra, and Opus.
  The Opus path continues to disclose Anthropic's possible Opus 4.8 fallback
  for classifier-flagged cyber requests; exact Opus 5 identity is not guaranteed
  on that path. The former native `senior` route now has no operational profile.
- Re-pinned the read-only `sol-judge` profile from `high` to `max` and
  `fable-judge` from `xhigh` to its verified supported `max` on explicit owner
  effort decisions. Both remain manually qualified and explicit-only; coding
  rows at the exact max tuples are contextual, not judgement evidence.
- Recorded a scoped installed-profile smoke for `opus-builder`: the exact
  Opus/max request changed only its assigned file, passed `git diff --check`,
  and surfaced `canonicalModel: claude-opus-5`. The lane remains provisional;
  one synthetic edit is compatibility evidence, not general qualification.
- Updated installation, cleanup, doctor, routing tests, and policy documents to
  enforce the new role and family boundaries and remove stale installed profiles.
- Fixed the release doctor so its missing-producer probe preserves the caller's
  shell options, and added an end-to-end regression for Codex configurations
  without a root-level `sandbox_mode`.

## [0.16.0] — 2026-08-17

### Added

- Added `delegation-deepseek`, its executable and central gates, installer,
  doctor checks, executor skill, and regression suite. The official
  `deepseek-v4-pro` API is pinned to `max`; only the text-only `builder` lane is
  provisional/explicit-only after one exact live patch smoke, and every other
  lane remains blocked.

### Changed

- Re-pinned the fail-closed Antigravity bridge from Gemini 3.6 Flash to
  `gemini-3.7-flash`, including its gate, skill, policy, installer, doctor, and
  tests. No operational Gemini lane is inherited: the current local session
  cannot attest exact 3.7 inventory/OAuth, so all new routes remain blocked.
- Refreshed the evidence registry with first-party Gemini 3.7 Flash and DeepSeek
  V4 Pro sources and contextual benchmark claims; neither source auto-qualifies
  a lane.

## [0.15.0] — 2026-08-16

### Changed

- **Sol becomes Codex's default material reviewer without widening its role.**
  `sol-reviewer` at `high` moves from manual explicit selection to the
  provisional `material-review` default on an explicit owner decision. It
  remains read-only and provisional because no exact review precision/recall
  row exists. `sol-judge`, judgement, and `super-judgement` remain manual and
  explicit-only; routine review and executor lanes are unchanged.
- **GLM-5.3/max replaces every previous GLM route across the active executor.** The exact
  high/max comparison ran three no-retry attempts per lane on the same frozen
  runner. Both efforts scored 1.0 in all nine attempts and passed every builder
  checker; the preregistered efficiency rule selected high (372s, $0.334234)
  over max (505s, $0.719138), after which the owner explicitly selected max as
  the sole operational effort. Clerk and scout are qualified explicit-only and
  builder remains provisional explicit-only. The 5.2 and 5.3/high gates and
  central profiles were removed; upgrades delete stale installed copies while
  frozen receipts remain historical. The selected tuple was requalified 9/9 on
  the final max-only runner bytes; the public result records digests for both
  the comparison and operational receipts.
- The evidence snapshot records Z.ai's GLM-5.3 release, Coding Plan access,
  effort mapping, and launch benchmark claims as contextual-only evidence. No
  independent tracked leaderboard had a GLM-5.3 row on 2026-08-14.

### Fixed

- `delegation-glm` now reads model and profile identity from the selected
  executable gate, permits only `glm-5.3/max`, and
  capability-probes Claude Code with a ten-second fail-closed timeout. A
  separately verified native binary can be selected explicitly for diagnostics
  without weakening model, lane, effort, sandbox, or manifest checks.

## [0.14.0] — 2026-08-13

### Changed

- **Grok 4.6 replaces Grok 4.5 across the active integration.** The runner,
  central and executable gates, skills, installed Claude/Codex policy, doctor,
  documentation, and regression fixtures now pin `grok-4.6` through Grok Build
  at effort `high`. `builder` and `frontend-builder` remain provisional and
  `preferred-explicit`, so every dispatch still requires an explicit decision
  plus `--allow-provisional`; no reviewer, senior, or judgement lane was added.
- The 2026-08-12 evidence snapshot adds separate Grok 4.6 observations from
  CursorBench 3.2, FrontierCode 1.1, APEX-SWE, APEX Agents, Code Arena WebDev,
  and xAI's launch material. Every row is contextual: the independent results
  use non-production harnesses, WebDev is preliminary, and xAI's figures are
  first-party claims. Grok 4.5 benchmark rows remain historical evidence and do
  not support the new route.

### Fixed

- Grok metrics no longer mistake a `modelUsage` billing participant for the
  model that authored the content. They record the requested model, any
  separately surfaced effective content model, and all usage participants,
  summing their tokens and cost. A surfaced mismatch fails every lane closed;
  a strict evaluation with no content-model identity is `VOID` rather than a
  false pass.
- Upgrading removes the installed `grok-4.5-routing.json` and installs the 4.6
  gate atomically with the current router and evidence snapshot before checking
  a retained private CLI archive. A portable upgrade regression covers stale
  gate removal, new-gate installation, and archive retention without depending
  on the user's authentication state.

### Verified

- All ten regression suites, ShellCheck, JSON/evidence/gate validation, and the
  version/tag consistency checks pass. After reinstalling the dirty release
  candidate, `delegation-grok check --json` resolved Grok Build CLI `0.2.114`
  with `grok-4.6-build`, and `./doctor.sh --ping-grok` returned `PONG` with
  `42 OK, 0 WARN, 0 FAIL`.

## [0.13.2] — 2026-08-05

### Fixed

- **The Agent Arena row for Gemini 3.6 Flash had five of its six effects
  recorded with the wrong sign.** The board encodes each effect's direction as a
  coloured triangle rather than a character, so the automated capture that built
  the 0.13.0 snapshot read every value as positive; the row was committed with
  `sign_inferred` and only `net_improvement_pct` flipped, on an inference from
  the sort order. Read visually from the rendered board, the model is negative
  on **every** effect: net improvement `-3.01%`, confirmed success `-1.63%`,
  praise vs complaint `-5.19%`, bash recovery `-2.69%`, and steerability
  `-6.70%` — that last one being the scout lane's own supporting metric, which
  makes this the difference between "unproven" and "measurably worse than the
  baseline agent in real sessions". The flag is gone and the row now states that
  its signs were read, not inferred. The rows near the boundary were re-read too:
  GPT 5.6 Sol, Luna, and Terra at ranks 5, 17, and 18 are positive as recorded,
  so the error was isolated to the one row below the inflection.
- `skills/qwen-executor` now tells the brief to demand `a/` and `b/` diff header
  prefixes. The text-only builder lane returns a patch the lead applies, and left
  to itself the model emits `--- <path>` on both sides; `git apply` defaults to
  `-p1` and strips one leading component precisely because of that convention, so
  an unprefixed header resolves to a path that does not exist and a correct patch
  fails to apply — which reads like a wrong answer and is not one. Re-dispatched
  with the instruction, the model returned prefixed headers and the patch applied
  with a bare `git apply`. The skill also records `-p0` as the recovery for a
  patch already in hand.

## [0.13.1] — 2026-08-05

### Fixed

- **The Gemini lane was unreachable from an SSH session, whatever the user did.**
  `agy` picks its credential store from the environment: seeing `SSH_CLIENT`,
  `SSH_CONNECTION`, or `SSH_TTY` it switches to a file-based token store and
  never consults the macOS Keychain. `delegation-gemini` supplies credentials the
  opposite way — `prepare_isolated_home` symlinks the user's
  `~/Library/Keychains` into the isolated home and carries nothing else — so over
  SSH the CLI looked in a store that was never written, `agy_status` reported
  `agy model inventory unavailable`, and every dispatch failed closed with exit
  69. Signing in again could not help: the login landed in the Keychain that the
  CLI had already decided to ignore. The runner now clears the three markers for
  every `agy` call that can touch credentials — the plugin inventory, the model
  inventory, and the dispatch itself. On a local session they are unset already,
  so this is a no-op there, and it grants nothing new: no additional tools, no
  filesystem access, only which credential store the CLI consults. Verified end
  to end from an SSH session: `check` reports `ready` and a real `scout` dispatch
  returned a correct answer at exit 0.
- The unavailable-runtime reason now says to keep the login keychain unlocked,
  since that is the only store this runner can read; the previous text sent the
  reader to an interactive sign-in that would not have fixed the SSH case.
- `tests/gemini-runner-diagnostics.sh` now runs its whole suite with SSH markers
  exported, and its `agy` stub exits 90 if any of them reaches the CLI. Neutering
  the fix makes the suite fail, so the regression is real rather than vacuous.

## [0.13.0] — 2026-08-05

### Changed

- **Routing gate — the three Codex executor lanes are re-pinned above the effort
  cliff.** `luna-clerk` moves `low` → `max`, `terra-scout` `low` → `medium`, and
  `terra-builder` `medium` → `max`. Lanes, models, harnesses, sandboxes, and
  statuses are unchanged; only the pinned effort moved. The reason is that the
  cheap models do not degrade gracefully and the kit had its two highest-volume
  lanes pinned where they collapse: on the exact Artificial Analysis rows
  `gpt-5.6-luna` at `low` scores 15% SWE-Atlas-QnA — the clerk *required* metric
  — against 33% at `max`, and the Epoch effort ladder puts the same model at
  1.5% DeepSWE at `low` against 67.2% at `max`. `terra-builder` gains both
  builder required metrics: DeepSWE 46% → 67% and Terminal-Bench v2 69% → 84%,
  at $2.76 rather than $0.90 per task. Each new effort was chosen because it
  already carries an *exact* benchmark row, so no lane trades measured evidence
  for expected capability. Owner decision on measured evidence, recorded in each
  lane's `qualification_basis`.
- **Routing gate — Kimi K3 and Grok 4.5 become `preferred-explicit` on
  `builder`** (they already were on `frontend-builder`). Both remain
  `provisional` and still require an explicit decision plus
  `--allow-provisional`; only the ordering among external builders changed. They
  are the only two carrying both builder required metrics on an exact production
  tuple, so they now rank above `glm-builder` and `qwen3.8-max`, which carry
  none. This records preference, not qualification: Kimi's local evaluation is
  still a quota-truncated run and Grok's a single non-held-out task.
- Codex reasoning-effort support is per model, not global, and reaches further
  than this repository claimed. Probed against the provider on 2026-08-05:
  `gpt-5.6-terra` enumerates `none · minimal · low · medium · high · xhigh ·
  max` and ran at `high`, `xhigh`, and `max`; `gpt-5.6-sol` and `gpt-5.6-luna`
  ran at `xhigh` and `max`; `gpt-5.5` **refuses** `max`. The effort table in
  `model-routing.md` previously stopped every Codex row at `high`.

### Fixed

- `delegation-evidence check` silently passed a broken snapshot. It ran
  `age="$(validate)"`, and a command substitution does not inherit `set -e`, so
  the `jq -e` covering schema, id uniqueness, and source references could fail
  while `check` still printed `valid` and exited 0 — only the freshness check,
  which uses an explicit `return`, was effective. The validation now fails with
  exit 65 and a message naming the file. Caught when a snapshot whose rows
  referenced three nonexistent sources was reported as valid.
- `preferred-explicit` had no positional meaning: `delegation-route resolve`
  emitted the `explicit` array in profile-insertion order, so a plain
  `explicit-only` profile could be listed ahead of a preferred one. Preferred
  entries now come first, insertion order preserved within each group.

### Added

- 65 dated evidence rows and three sources in `config/model-evidence.json`:
  Agent Arena (data 2026-08-03, 1,607,993 sessions — first Claude Opus 5 rows,
  entering at ranks 1 and 3), Code Arena WebDev (data 2026-08-01, 510,194 votes
  — first `qwen3.8-max` row at rank 4, which is the `frontend-builder` required
  metric for a model that has no such lane), and the Epoch AI ZIP of 2026-08-04,
  whose first import of the DeepSWE effort ladder is what made the cliff visible.
  Existing rows are untouched; the gates reference them by id. Every Epoch row is
  `contextual_only` because `mini-swe-agent` is not a production harness, and the
  Gemini Agent Arena row carries `sign_inferred` because the board's sign is not
  machine-readable.

## [0.12.0] — 2026-08-04

### Added

- `delegation-kimi run --oauth shared` (or `DELEGATION_KIMI_OAUTH_MODE=shared`):
  concurrent Kimi dispatches. Until now the kit lock spanned the whole run, so
  a second agent died instantly with exit 75 — but the vendor supports ~30
  concurrent instances when they share one `KIMI_CODE_HOME`, coordinating
  refresh-token rotation through the CLI's own cross-process oauth lock. In
  shared mode, OAuth state lives in a runner-owned *generation* under
  `$DELEGATION_DATA_HOME/kimi-shared-oauth`; each run's isolated home symlinks
  its `credentials/` and `oauth/` dirs at that generation so the vendor lock
  coordinates the children, and the kit lock shrinks to two brief critical
  sections (seeding the generation, publishing it back to the ambient home).
  Generations — not hash markers — keep a dead token family from clobbering a
  credential after an external `kimi login`; a busy kit lock at publish time
  defers to the next run instead of failing. The serialized default and its
  sandbox profile are byte-for-byte unchanged, `--evaluation` runs always
  serialize, and the live two-parallel smoke against the real CLI passed on
  2026-08-04 with a real mid-run rotation through the symlinked generation.
- `DELEGATION_KIMI_OAUTH_WAIT_SECONDS` (default 5, 0 = fail immediately):
  bounded wait on the kit lock for shared-mode seed and publish.
- delegation-glm now distinguishes two 429 shapes in `<output>.error.json`:
  reason `rate_limited` (retry with backoff) versus `quota_exhausted`, which
  carries the window-reset epoch in the new `next_flush_time` field
  (diagnostic `schema_version` 2). Z.AI's numeric body codes never reach the
  runner — a captured stream shows `api_retry` carries only the HTTP status —
  so quota detection keys on the `rate_limit_event` reset epoch instead.

### Fixed

- The delegation-glm stderr fallback grepped for Z.AI code `1312`, which does
  not exist in the published error table, and missed `1302` — the actual
  rate/concurrency code.
- A stray 429 event in an otherwise-completed GLM stream no longer overwrites
  an extract-phase reason (`empty_result`, `model_mismatch`, …) with
  `rate_limited`: reclassification is now scoped to dispatch failures.

## [0.11.1] — 2026-08-03

### Fixed

- Made the CI release-tag check fetch the real tag object before validating it.
  `actions/checkout` maps the commit SHA onto `refs/tags/<name>`, leaving a
  lightweight ref even when the pushed tag is annotated, so the 0.11.0 tag run
  failed with `tag is annotated: expected 'tag', got 'commit'` while the tag
  itself was correct on both the server and locally.
- Made `tests/version-consistency.sh --tag` fail when the tag object is absent
  instead of silently skipping the annotation and subject checks. A silent skip
  left the convention unenforced in exactly the environment it was written for.

## [0.11.0] — 2026-08-03

### Added

- `install.sh` now writes `installed-version.json` into the data home, and
  `doctor.sh` compares it against the checkout. Until now a stale install was
  undetectable: every other doctor check inspects the installed copy against
  itself and passes while it lags the repository. A version mismatch is a FAIL,
  a same-version commit mismatch is a warning, and installs from a dirty
  checkout or with `--claude-only`/`--codex-only` scope are recorded so the
  marker never overstates what was installed.
- Added `tests/install-version-marker.sh`, which installs into isolated homes
  and asserts both the marker's contents and that doctor detects version drift,
  commit drift, a missing marker, and a missing install.
- Added `run-tests.sh`, which runs every suite in parallel on one machine and
  prints the full log of any that fails. CI uses it, cutting the macOS job's
  test step from ~116s to well under half without allocating a second runner.
  `--sequential` restores one-at-a-time output for debugging.

- Added `.github/workflows/ci.yml`. Until now nothing verified a release except
  the person cutting it. Every pull request and push to `main` now runs
  shellcheck at `-S warning`, the version-surface check, and the regression
  suites on macOS; a tag push additionally validates the tag against the
  manifest version. Suites run on macOS because the Kimi runner requires
  `/usr/bin/sandbox-exec` and the Grok suite asserts BSD `stat -f` modes.
- Added `tests/version-consistency.sh`, which enforces the CLAUDE.md release
  rules: the five version surfaces must agree, the newest changelog section must
  be the shipped version, and `--tag` validates the
  `delegation-kit--v<semver>` annotated-tag convention.

## [0.10.0] — 2026-08-03

### Changed

- Repinned the Qwen bridge from `qwen3.8-max-preview` to `qwen3.8-max` after the
  model left preview on 2026-08-02. The rename rests on a local Token Plan probe
  confirming `GET /models` lists the unsuffixed id and that a chat completion
  pinned to it returns `.model == "qwen3.8-max"` with `reasoning_effort: xhigh`
  accepted; the `-preview` id still resolves in parallel. Renamed
  `config/qwen3.8-max-preview-routing.json` to `config/qwen3.8-max-routing.json`
  and the central gate profile to `qwen3.8-max`.
- Promoted the Qwen `builder` lane to **provisional / explicit-only** at `xhigh`
  on an explicit owner routing decision. `delegation-qwen run` now accepts
  `--allow-provisional`, which is mutually exclusive with `--evaluation`; the
  previous blanket refusal of every provisional lane is gone. Every other lane
  stays a blocked candidate, and `judgement` stays disabled.
- Cleared the Qwen `policy-annotation` manifest allowlist in both gates. The
  frozen manifest was bound to the `qwen3.8-max-preview` profile, model, and
  runner hash, so it can no longer validate; regenerate it against the new tuple
  before any evaluation run. The frozen v2/v3 evaluation artifacts are
  historical records and were deliberately left unrewritten.

### Documentation

- Recorded the promotion as an owner decision rather than measured capability.
  A 2026-08-03 re-check of the Artificial Analysis coding-agent board and
  Terminal-Bench 2.1 still found no `qwen3.8-max` row, so both builder required
  metrics (`coding.deep_swe_pass_pct`, `coding.terminal_bench_v2_pass_pct`)
  remain unmet and `exact_evidence_ids` stays empty. Alibaba has published no
  benchmark table for the model.
- Added the contextual `qwen-3.8-max-ga-launch` evidence row and its
  `qwen-3.8-max-ga-2026-08-03` source. Its metrics live under `launch.*` so they
  cannot satisfy any lane's `required_metrics`. The snapshot date stays
  2026-07-31 because this was a targeted re-check, not a full refresh.
- Documented that the Qwen builder lane is text-only: the chat-completions
  transport exposes no tools and no terminal, so it returns a patch the lead
  applies and verifies rather than editing a worktree, and it is prompt-only.

## [0.9.0] — 2026-08-01

### Added

- Added `delegation-schema`, a read-only deterministic compiler and verifier for
  Claude Code and Codex structured-output transport schemas.

### Fixed

- Made GLM lane evaluation compile its manifest-bound schema for Claude before
  dispatch, while leaving the normative schema and frozen protocols unchanged.
- Made schema compilation preserve literal objects and property order, reject
  non-standard JSON, and fail closed on unsupported Codex keywords, unions, and
  documented Structured Outputs limits.
- Made `doctor.sh` use Claude's provider-free auth status and warn when a
  sanitized macOS environment drops `USER` and therefore Keychain resolution.
- Made `doctor.sh` exercise both the Claude and Codex compiler paths before
  reporting the installed schema transport helper healthy.

### Documentation

- Defined separate requested, effective, and observed-usage model evidence for
  Claude safety fallback and internal classifier telemetry, including aggregate
  token/cost accounting and exact-identity `VOID` behavior.
- Documented provider-specific schema preflights for raw Claude and Codex
  bridges; `--help` checks alone are not semantic compatibility checks.

## [0.8.1] — 2026-07-31

### Changed

- Raised the maximum manifest-bound Kimi evaluation timeout from 600 to 1200
  seconds. Operational Kimi runs remain capped at 900 seconds.

## [0.8.0] — 2026-07-31

### Added

- Added hash-allowlisted, manifest-bound qualification for GLM clerk, scout,
  and builder at the exact `glm-5.2` / `claude-zai` / `high` tuple.
- Added portable lane-specific structured-output schemas, per-attempt receipts,
  full worktree and Git-control attestation, and a public minimal aggregate for
  the frozen repeated comparison.
- Refreshed current GLM and cross-model context from Agent Arena, Code Arena
  WebDev, Terminal-Bench 2.1, SWE-bench-Live, OpenBench, Z.ai, and Epoch.

### Changed

- Qualified GLM clerk and scout as explicit-only routes after three valid
  repeats matched the best incumbent on each bounded pack.
- Moved GLM builder from candidate/blocked to provisional/explicit-only after
  all three GLM attempts and all three Terra incumbent attempts passed the
  deterministic checker. Builder still requires `--allow-provisional`.
- Extended central gate validation so private GLM qualification allowlists may
  cover clerk, scout, and builder without creating an operational route by
  themselves.

### Fixed

- Made the GLM runner actually pass the manifest-bound output schema to Claude
  Code and extract structured output without changing the historical
  policy-annotation path.
- Replaced a non-portable generic comparison schema with lane-specific schemas
  accepted by both Claude Code and Codex.
- Hardened GLM qualification with fixture-only data reads, a native-CLI process
  allowlist, an empty environment, immutable `.git`, ignored/untracked file and
  executable-mode hashing, and disabled Claude keychain prefetch. The final
  runner passed independent security review and macOS sandbox canaries.

### Documentation

- Documented the exact local decisions, costs, latency limitation, invalidated
  runner/preflight series, and two `VOID` Claude builder comparator attempts
  caused by an out-of-fixture write. No attempt in the final v6 series was
  retried.

## [0.7.2] — 2026-07-31

### Changed

- Removed downstream Dipylon evaluation packs from the repository, installer,
  doctor, routing allowlists, and pack-specific tests.
- Kept only kit-owned qualification manifests in the central routing allowlist
  and added a generic invariant that every allowlisted manifest is tracked.
- Preserved the generic Qwen 900-second evaluation ceiling and timeout
  classification introduced alongside the downstream packs.

### Documentation

- Documented that project-specific evaluation packs belong in their owning
  repository or artifact registry and are deliberately ignored here.
- Kept the 0.7.1 Claude Code, Codex, and external-runner compatibility matrix as
  the reproducible compatibility snapshot for this patch release.

## [0.7.1] — 2026-07-31

### Added

- Added a reproducible compatibility matrix for all shipped Claude Code agents,
  Codex profiles, and gated external runners.
- Recorded semantic smoke expectations, cross-CLI round-trip verification,
  fail-closed Qwen behavior, and byte-for-byte installation checks.

### Documentation

- Clarified that `codex exec --ephemeral -p <profile>` must not be combined
  with `--ignore-user-config`, which also suppresses the selected profile.
- Clarified that Claude read-only roles expose Bash for inspection and therefore
  do not have the same OS-enforced write isolation as Codex read-only sandboxes.
- Preserved all existing provisional, candidate, and blocked routing decisions;
  successful runtime verification is not a model promotion.

## [0.7.0] — 2026-07-31

### Added

- Upgraded the Kimi bridge to a capability-probed Kimi Code runtime with
  lane-specific agent files and a digest-attested ripgrep allowlist.
- Added bounded cancellation, timeout handling, sanitized heartbeat/error
  diagnostics, and explicit OAuth finalization.

### Security

- Confined Kimi process execution to the selected CLI, `/usr/bin/true`, and the
  exact pinned ripgrep runtime under the macOS sandbox.
- Kept all Kimi lanes provisional and explicit-only without changing historical
  evaluation manifests.
