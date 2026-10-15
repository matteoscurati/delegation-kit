#!/usr/bin/env bash
# delegation-router: policy table, router block, catalog, decide/check CLI,
# deciders, eval and the loopback server, all against fake providers and
# services. No provider account.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/tests"
python3 -m unittest discover -s router -t . -p 'test_*.py' -v
