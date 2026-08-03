# Changelog

All notable changes to delegation-kit are documented here.

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
