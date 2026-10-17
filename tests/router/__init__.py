"""The router suite: pure policy, configuration, catalog, CLI, deciders, eval
and the loopback server, all against fake providers and services. Run it
with `tests/router.sh` (unittest discovery)."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bin/lib"))
