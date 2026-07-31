# Changelog

All notable changes to delegation-kit are documented here.

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
