#!/usr/bin/env bash
# delegation-router: policy table, router block, decide/check CLI and
# the loopback server, all against a fake provider. No provider account.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tests/router.py" -v
