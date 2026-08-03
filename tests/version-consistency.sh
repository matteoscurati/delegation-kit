#!/usr/bin/env bash
# Enforce the version and tagging rules recorded in CLAUDE.md.
#
# A partial bump is the failure this catches: the installed plugin then reports
# a version the repository does not claim, and nothing else notices.
#
# Usage:
#   tests/version-consistency.sh              check the five version surfaces
#   tests/version-consistency.sh --tag NAME   additionally validate a release tag
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 69; }

TAG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag) TAG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { pass=$((pass + 1)); }
same() { # label expected actual
  [ "$2" = "$3" ] || fail "$1: expected '$2', got '$3'"
  ok
}

# The plugin manifest is the source of truth; every other surface follows it.
VERSION="$(jq -r '.version' .claude-plugin/plugin.json)"
[ -n "$VERSION" ] && [ "$VERSION" != null ] || fail 'plugin.json carries no version'
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "version '$VERSION' is not bare semver"
ok

same 'marketplace.json metadata.version' "$VERSION" \
  "$(jq -r '.metadata.version' .claude-plugin/marketplace.json)"
same 'marketplace.json plugin entry version' "$VERSION" \
  "$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)"
same 'marketplace.json plugin count' 1 \
  "$(jq -r '.plugins | length' .claude-plugin/marketplace.json)"

readme="$(sed -n 's/^## Current release: \(.*\)$/\1/p' README.md | head -1)"
same 'README "Current release" heading' "$VERSION" "$readme"

grep -Eq "^## \[$(printf '%s' "$VERSION" | sed 's/\./\\./g')\] — [0-9]{4}-[0-9]{2}-[0-9]{2}\$" CHANGELOG.md \
  || fail "CHANGELOG.md has no '## [$VERSION] — YYYY-MM-DD' section"
ok

# The newest CHANGELOG section must be the version being shipped, so a bump
# cannot silently land under an older heading.
newest="$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | sed 's/^## \[\([^]]*\)\].*/\1/')"
same 'newest CHANGELOG section' "$VERSION" "$newest"

# No other surface may still advertise a previous version.
stale="$(grep -rn --exclude-dir=.git --exclude=CHANGELOG.md \
  -E '^## Current release: |"version": "' README.md .claude-plugin/*.json \
  | grep -v "$VERSION" || true)"
[ -z "$stale" ] || fail "stale version reference(s):"$'\n'"$stale"
ok

if [ -n "$TAG" ]; then
  # CLAUDE.md: delegation-kit--v<semver>, annotated, matching the manifest.
  expected="delegation-kit--v$VERSION"
  same 'tag name' "$expected" "$TAG"
  # Requiring the object rather than skipping when it is absent: a silent skip
  # would let the annotation rule go unenforced exactly where it matters. Note
  # that actions/checkout maps the commit SHA onto refs/tags/<name>, producing a
  # lightweight ref, so CI must fetch the real tag object before calling this.
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    || fail "tag '$TAG' is not present locally; fetch the tag object first:
    git fetch --force origin \"refs/tags/$TAG:refs/tags/$TAG\""
  ok
  same 'tag is annotated' tag "$(git cat-file -t "$TAG")"
  subject="$(git tag -l --format='%(contents:subject)' "$TAG")"
  same 'tag message subject' "delegation-kit $VERSION" "$subject"
fi

printf 'version consistency: %s checks passed (version %s)\n' "$pass" "$VERSION"
