#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-epoch-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT

pass=0
expect_failure() {
  local expected="$1"; shift
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  [ "$actual" -eq "$expected" ] || {
    printf 'expected exit %s, got %s: ' "$expected" "$actual" >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    exit 1
  }
  pass=$((pass + 1))
}

python3 - "$TMP/fixture.zip" <<'PY'
import sys
import zipfile

target = sys.argv[1]
with zipfile.ZipFile(target, "w") as archive:
    archive.writestr("README.md", "Epoch AI data; preserve attribution.\n")
    archive.writestr(
        "deepswe_external.csv",
        "Model version,Pass@1,Harness,Reasoning effort,Organization,Source\n"
        "gpt-5.6-sol_max,0.72,mini-swe-agent,max,OpenAI,https://example.test/deepswe\n",
    )
    archive.writestr(
        "webdev_arena_external.csv",
        "Model version,Arena Score,Organization,Source link\n"
        "glm-5.2_max,1593.25,Z.ai,https://example.test/webdev\n",
    )
    archive.writestr(
        "additional_eci_data/eci_benchmark_difficulties_and_slopes.csv",
        "benchmark_name,is_anchor,edi\nDeepSWE,true,1.2\n",
    )
PY

cd "$ROOT"
before_gate="$(shasum -a 256 config/routing-gates.json | awk '{print $1}')"

bin/delegation-epoch --source "$TMP/fixture.zip" check --json >"$TMP/manifest.json"
jq -e '
  .policy.routing_gate_mutation == false and
  .summary.csv_files == 3 and
  .summary.rows == 3 and
  .summary.normalized_records == 2 and
  .summary.exact_records == 1 and
  .summary.contextual_records == 1 and
  ([.datasets[] | select(.name == "deepswe_external.csv") | .license.id] == ["upstream-original"])
' "$TMP/manifest.json" >/dev/null
pass=$((pass + 1))

bin/delegation-epoch --source "$TMP/fixture.zip" normalize --output "$TMP/records.json"
jq -e '
  .policy.advisory_only == true and
  .summary.selected_records == 2 and
  ([.records[].evidence_class] | sort) == ["contextual", "exact"] and
  (.records[] | select(.model == "gpt-5.6-sol") |
    .benchmark == "deepswe" and
    .harness == "mini-swe-agent" and
    .effort == "max" and
    .license.id == "upstream-original" and
    .metrics["Pass@1"] == 0.72)
' "$TMP/records.json" >/dev/null
pass=$((pass + 1))

bin/delegation-epoch --source "$TMP/fixture.zip" normalize \
  --model glm-5.2 --benchmark webdev_arena >"$TMP/filtered.json"
jq -e '
  .summary.selected_records == 1 and
  .summary.selected_exact_records == 0 and
  .records[0].model == "glm-5.2" and
  .records[0].harness == "unknown"
' "$TMP/filtered.json" >/dev/null
pass=$((pass + 1))

bin/delegation-epoch --source "$TMP/fixture.zip" evidence >"$TMP/evidence.json"
jq -e '
  .policy.routing_gate_mutation == false and
  .summary.mapped_evidence_rows == 2 and
  .summary.exact_rows == 1 and
  .summary.contextual_rows == 1 and
  (.evidence[] | select(.model == "gpt-5.6-sol") |
    .metrics.coding.deep_swe_pass_pct == 72 and
    .provenance.dataset_license.id == "upstream-original" and
    (.source | startswith("epoch-ai-zip-")))
' "$TMP/evidence.json" >/dev/null
pass=$((pass + 1))

after_gate="$(shasum -a 256 config/routing-gates.json | awk '{print $1}')"
[ "$before_gate" = "$after_gate" ] || {
  echo "routing gate changed during advisory import" >&2
  exit 1
}
pass=$((pass + 1))

python3 - "$TMP/unsafe.zip" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("README.md", "attribution")
    archive.writestr("../escape.csv", "Model version,Score\nmodel_max,1\n")
PY
expect_failure 65 bin/delegation-epoch --source "$TMP/unsafe.zip" check

printf 'Epoch ZIP tests: %s passed\n' "$pass"
