# Changelog

All notable changes to delegation-kit are documented here.

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
