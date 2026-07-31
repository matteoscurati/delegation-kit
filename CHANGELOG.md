# Changelog

All notable changes to delegation-kit are documented here.

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
