#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-schema-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
SCHEMA="$ROOT/bin/delegation-schema"
SOURCE="$ROOT/evaluation/policy-annotation-qualification-v3/output-schema.json"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

"$SCHEMA" check --provider claude --schema "$SOURCE" >"$TMP/claude-check.json"
jq -e '.valid == true and .changes == ["removed /$schema"]' \
  "$TMP/claude-check.json" >/dev/null || fail "Claude dialect removal was not reported"

"$SCHEMA" compile --provider claude --schema "$SOURCE" >"$TMP/claude.json"
jq -e 'has("$schema") | not' "$TMP/claude.json" >/dev/null \
  || fail "Claude transport retained the unsupported dialect declaration"
jq -e 'has("$schema")' "$SOURCE" >/dev/null \
  || fail "the compiler modified the normative schema"
"$SCHEMA" verify --provider claude --schema "$SOURCE" \
  --transport "$TMP/claude.json" >/dev/null

"$SCHEMA" compile --provider codex --schema "$SOURCE" >"$TMP/codex.json"
jq -e '
  (has("$schema") | not) and
  .properties.schema_version.type == "string" and
  .properties.records.items.properties.label.type == "string"
' "$TMP/codex.json" >/dev/null || fail "Codex literal types were not inferred"
"$SCHEMA" verify --provider codex --schema "$SOURCE" \
  --transport "$TMP/codex.json" >/dev/null

printf '%s\n' \
  '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"payload":{"const":{"$schema":"literal","value":1}}},"required":["payload"]}' \
  >"$TMP/literal-schema-key.json"
"$SCHEMA" compile --provider claude --schema "$TMP/literal-schema-key.json" \
  >"$TMP/literal-schema-key.transport.json"
jq -e '
  (has("$schema") | not) and
  .properties.payload.const == {"$schema":"literal","value":1}
' "$TMP/literal-schema-key.transport.json" >/dev/null \
  || fail "Claude compilation altered a literal object containing \$schema"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{"zeta":{"type":"string"},"alpha":{"type":"string"}},"required":["zeta","alpha"]}' \
  >"$TMP/ordered.json"
"$SCHEMA" compile --provider codex --schema "$TMP/ordered.json" \
  >"$TMP/ordered.transport.json"
jq -e '(.properties | keys_unsorted) == ["zeta","alpha"]' \
  "$TMP/ordered.transport.json" >/dev/null \
  || fail "Codex compilation changed property order"
jq '.properties = {alpha:.properties.alpha,zeta:.properties.zeta}' \
  "$TMP/ordered.transport.json" >"$TMP/reordered.transport.json"
rc=0
"$SCHEMA" verify --provider codex --schema "$TMP/ordered.json" \
  --transport "$TMP/reordered.transport.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "reordered Codex transport returned $rc instead of 65"

jq '.properties.schema_version.type = "number"' "$TMP/codex.json" \
  >"$TMP/drifted.json"
rc=0
"$SCHEMA" verify --provider codex --schema "$SOURCE" \
  --transport "$TMP/drifted.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "drifted transport returned $rc instead of 65"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{"a":{"type":"string"},"b":{"type":"string"}},"required":["a"]}' \
  >"$TMP/optional.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/optional.json" \
  >"$TMP/optional.stdout" 2>"$TMP/optional.stderr" || rc=$?
[ "$rc" -eq 65 ] || fail "optional Codex property returned $rc instead of 65"
grep -Fq '/required: Codex object schemas must require every property exactly once' \
  "$TMP/optional.stderr" || fail "optional Codex property lacked an actionable error"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{"value":{"enum":["one",2]}},"required":["value"]}' \
  >"$TMP/mixed-enum.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/mixed-enum.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "mixed Codex enum returned $rc instead of 65"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{},"required":[],"not":{"type":"null"}}' \
  >"$TMP/unsupported-keyword.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/unsupported-keyword.json" \
  >"$TMP/unsupported.stdout" 2>"$TMP/unsupported.stderr" || rc=$?
[ "$rc" -eq 65 ] || fail "unsupported Codex keyword returned $rc instead of 65"
grep -Fq '/not: is not supported by the Codex structured-output subset' \
  "$TMP/unsupported.stderr" || fail "unsupported Codex keyword lacked an actionable error"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{"value":{"type":["string","number"]}},"required":["value"]}' \
  >"$TMP/non-null-union.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/non-null-union.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "non-null Codex union returned $rc instead of 65"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{"value":{"$ref":"#/$defs/missing"}},"required":["value"],"$defs":{}}' \
  >"$TMP/dangling-ref.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/dangling-ref.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "dangling Codex ref returned $rc instead of 65"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{"value":{"type":"string","enum":["one","one"]}},"required":["value"]}' \
  >"$TMP/duplicate-enum.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/duplicate-enum.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "duplicate Codex enum returned $rc instead of 65"

printf '%s\n' \
  '{"type":"object","additionalProperties":false,"properties":{"value":{"type":["string","null"],"enum":["one",null]}},"required":["value"]}' \
  >"$TMP/nullable-enum.json"
"$SCHEMA" check --provider codex --schema "$TMP/nullable-enum.json" \
  >/dev/null || fail "explicit nullable Codex enum was rejected"

printf '%s\n' '{"type":"object","required":["value","value"]}' \
  >"$TMP/duplicate-required.json"
rc=0
"$SCHEMA" check --provider claude --schema "$TMP/duplicate-required.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "malformed Claude schema returned $rc instead of 65"

for constant in NaN Infinity -Infinity; do
  rc=0
  printf '{"type":"object","properties":{"value":{"const":%s}},"required":["value"]}\n' \
    "$constant" | "$SCHEMA" check --provider claude --schema - \
    >/dev/null 2>"$TMP/non-standard-$constant.stderr" || rc=$?
  [ "$rc" -eq 65 ] || fail "non-standard JSON constant $constant returned $rc instead of 65"
done

rc=0
printf '%s\n' '{"type":"object","type":"object","properties":{},"required":[]}' \
  | "$SCHEMA" check --provider claude --schema - >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "duplicate JSON key returned $rc instead of 65"

jq -n '
  (reduce range(0;5001) as $index ({};
    .["property_\($index)"] = {"type":"string"})) as $properties |
  {type:"object",additionalProperties:false,properties:$properties,
   required:($properties | keys_unsorted)}
' >"$TMP/too-many-properties.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/too-many-properties.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "Codex property limit returned $rc instead of 65"

jq -n '
  reduce range(0;11) as $index ({type:"string"};
    {type:"object",additionalProperties:false,
     properties:{child:.},required:["child"]})
' >"$TMP/too-deep.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/too-deep.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "Codex nesting limit returned $rc instead of 65"

jq -n '
  {type:"object",additionalProperties:false,
   properties:{value:{type:"integer",enum:[range(0;1001)]}},
   required:["value"]}
' >"$TMP/too-many-enum-values.json"
rc=0
"$SCHEMA" check --provider codex --schema "$TMP/too-many-enum-values.json" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] || fail "Codex enum limit returned $rc instead of 65"

mkdir -p "$TMP/fake-bin" "$TMP/doctor-claude" "$TMP/doctor-codex"
cat >"$TMP/fake-bin/delegation-schema" <<'FAKE_SCHEMA'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$SCHEMA_TEST_LOG"
FAKE_SCHEMA
chmod 755 "$TMP/fake-bin/delegation-schema"
: >"$TMP/doctor-schema.log"
PATH="$TMP/fake-bin:/usr/bin:/bin" \
  CLAUDE_HOME="$TMP/doctor-claude" CODEX_HOME="$TMP/doctor-codex" \
  SCHEMA_TEST_LOG="$TMP/doctor-schema.log" \
  "$ROOT/doctor.sh" >/dev/null 2>&1 || true
grep -Fq -- '--provider claude' "$TMP/doctor-schema.log" \
  || fail "doctor did not check the installed Claude schema path"
grep -Fq -- '--provider codex' "$TMP/doctor-schema.log" \
  || fail "doctor did not check the installed Codex schema path"

printf 'schema transport tests passed\n'
