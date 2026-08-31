#!/usr/bin/env bash
# Fail-closed regression suite for the external-executor patch verifier.
#
# `delegation-patch-verify` is the reading side of the text-patch trust
# boundary: a Qwen or DeepSeek builder lane has no filesystem and returns diff
# text that somebody has to apply. This suite proves four things:
#   1. the shapes those lanes actually produce — a/b-prefixed and the Qwen
#      no-prefix shape — are accepted at the strip level their headers fix,
#      and no other level is ever chosen,
#   2. every way of escaping the worktree, smuggling a capability, or blowing
#      past a limit is refused, and refused by a named rule,
#   3. the command is read-only: a dirty worktree, its index, the git control
#      directory, and the patch file itself come out byte-identical, and
#   4. the receipt carries paths, counts, and digests — never patch content.
#
# The strip rule is the fiddly one, so it is stated once here and asserted
# below. The level comes from the header grammar, never from what happens to
# apply: `a/<rest>` opposite `b/<rest>` means -p1, no prefix on either side
# means -p0, and any other shape fixes nothing and is refused. git is then asked
# whether the patch applies at that one level. The other candidate is probed
# only to describe it — for a/b headers it merely leaves the prefix on, which is
# why every ordinary add also "applies" at -p0, and it is never chosen; for
# unprefixed headers it drops a real component and lands on a different file, at
# git's own default -p1, so a patch that also applies there is ambiguous and is
# refused.
#
# It never dispatches a model, never applies a patch, never touches a real home,
# and never writes into this checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-patch-verify-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 69; }
command -v git >/dev/null 2>&1 || { printf 'git is required\n' >&2; exit 69; }
cd "$ROOT"

CMD="$ROOT/bin/delegation-patch-verify"
POLICY="$ROOT/config/external-patch-policy.json"
[ -x "$CMD" ] || { printf 'bin/delegation-patch-verify is not executable\n' >&2; exit 1; }

export GIT_AUTHOR_NAME=delegation-kit-tests GIT_AUTHOR_EMAIL=tests@example.invalid
export GIT_COMMITTER_NAME=delegation-kit-tests GIT_COMMITTER_EMAIL=tests@example.invalid

pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# A worktree with real content, so an "accepted" verdict means the patch really
# does apply rather than merely parse.
# ---------------------------------------------------------------------------
WT="$TMP/wt"
mkdir -p "$WT/src" "$WT/docs"
git -C "$WT" init -q
printf 'alpha one\nalpha two\nalpha three\nalpha four\n' >"$WT/src/alpha.txt"
printf 'beta one\nbeta two\nbeta three\n' >"$WT/src/beta.txt"
printf 'notes\n' >"$WT/docs/notes.md"
printf '#!/bin/sh\necho one\n' >"$WT/src/exec.sh"
chmod 755 "$WT/src/exec.sh"
git -C "$WT" add -A
git -C "$WT" update-index --chmod=+x src/exec.sh
git -C "$WT" commit -q -m init

mkpatch() { # $1=output, then a heredoc on stdin
  cat >"$1"
  chmod 600 "$1"
}

run_json() { # $1=patch, rest=extra flags; prints receipt to $TMP/out.json, returns rc
  local patch="$1"; shift
  local rc=0
  set +e
  "$CMD" check --patch "$patch" --workdir "$WT" --json "$@" >"$TMP/out.json" 2>"$TMP/out.err"
  rc=$?
  set -e
  return "$rc"
}

accepted() { # $1=patch, rest=extra flags
  local patch="$1"; shift
  run_json "$patch" "$@" || {
    sed 's/^/    /' "$TMP/out.err" >&2
    jq -c '.violations' "$TMP/out.json" 2>/dev/null >&2 || true
    fail "expected the verifier to accept $(basename "$patch")"
  }
  # Every accepted receipt carries the same strip invariant: the level applied is
  # the level the headers fixed, and the alternate reading was never selected.
  jq -e '.verdict == "accepted" and .read_only == true and .applies_patch == false and
         .applied_by == "lead" and .attestation.unchanged == true and
         .git_apply_check.result == "clean" and (.violations | length) == 0 and
         .strip.chosen == .strip.required and .strip.alternate_chosen == false and
         .strip.fixed_by == "header-grammar" and .git_apply_check.strip == .strip.required' \
    "$TMP/out.json" >/dev/null || fail "$(basename "$patch"): accepted receipt is not well formed"
  pass=$((pass + 1))
}

rejected_with() { # $1=patch, $2=expected rule, rest=extra flags
  local patch="$1" rule="$2"; shift 2
  local rc=0
  run_json "$patch" "$@" || rc=$?
  [ "$rc" -eq 65 ] || {
    sed 's/^/    /' "$TMP/out.err" >&2
    fail "$(basename "$patch"): expected exit 65 for $rule, got $rc"
  }
  jq -e --arg r "$rule" '.verdict == "rejected" and any(.violations[]; .rule == $r)' \
    "$TMP/out.json" >/dev/null || {
    jq -c '.violations' "$TMP/out.json" >&2
    fail "$(basename "$patch"): expected violation $rule"
  }
  # A rejected patch is never handed to git for anything but a check, and never
  # even that when a structural or path rule already refused it.
  jq -e '.applies_patch == false and .git_apply_check.result != "clean" and
         .attestation.unchanged == true' "$TMP/out.json" >/dev/null \
    || fail "$(basename "$patch"): a rejected receipt claimed a clean apply"
  pass=$((pass + 1))
}

exit_code() { # $1=expected, rest=command
  local expected="$1"; shift
  local actual=0
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  [ "$actual" -eq "$expected" ] || {
    printf 'expected exit %s, got %s: ' "$expected" "$actual" >&2
    printf '%q ' "$@" >&2; printf '\n' >&2; exit 1
  }
  pass=$((pass + 1))
}

# ---------------------------------------------------------------------------
# 1. The shapes the text-patch lanes actually produce.
# ---------------------------------------------------------------------------

# One file, conventional a/ and b/ headers. Generated by git, so it is exactly
# what a well-briefed lane is asked to return.
printf 'alpha one\nalpha two changed\nalpha three\nalpha four\n' >"$WT/src/alpha.txt"
git -C "$WT" diff >"$TMP/one-file.patch"
git -C "$WT" checkout -q -- .
chmod 600 "$TMP/one-file.patch"
accepted "$TMP/one-file.patch"
jq -e '.file_count == 1 and .strip.required == 1 and .strip.chosen == 1 and
       .strip.header_style == "git-prefixed" and .strip.alternate == 0 and
       .strip.alternate_applies == false and
       .operations == ["modify"] and .files[0].path == "src/alpha.txt" and
       .files[0].added_lines == 1 and .files[0].removed_lines == 1' "$TMP/out.json" >/dev/null \
  || fail 'the one-file receipt did not describe the patch'
pass=$((pass + 1))

# Multiple files in one patch.
printf 'alpha one\nalpha two changed\nalpha three\nalpha four\n' >"$WT/src/alpha.txt"
printf 'beta one\nbeta two changed\nbeta three\n' >"$WT/src/beta.txt"
git -C "$WT" diff >"$TMP/multi-file.patch"
git -C "$WT" checkout -q -- .
chmod 600 "$TMP/multi-file.patch"
accepted "$TMP/multi-file.patch"
jq -e '.file_count == 2 and .strip.chosen == 1 and
       ([.files[].path] | sort) == ["src/alpha.txt","src/beta.txt"]' "$TMP/out.json" >/dev/null \
  || fail 'the multi-file receipt lost a file'
pass=$((pass + 1))

# The Qwen no-prefix shape. Left to itself the lane emits `--- <path>` on both
# sides; the strip level must be established deterministically rather than
# guessed, and recorded so the lead applies it with the right -p.
printf 'alpha one\nalpha two changed\nalpha three\nalpha four\n' >"$WT/src/alpha.txt"
git -C "$WT" diff --no-prefix >"$TMP/qwen-style.patch"
git -C "$WT" checkout -q -- .
chmod 600 "$TMP/qwen-style.patch"
accepted "$TMP/qwen-style.patch"
jq -e '.strip.required == 0 and .strip.chosen == 0 and .git_apply_check.strip == 0 and
       .strip.header_style == "unprefixed" and .strip.alternate == 1 and
       .strip.alternate_applies == false and
       .files[0].path == "src/alpha.txt"' "$TMP/out.json" >/dev/null \
  || fail 'the unprefixed Qwen shape did not resolve to strip level 0'
pass=$((pass + 1))

# A new file is an ordinary add — and the case that makes the strip rule
# concrete. `git apply --check -p0` succeeds on it too, because at -p0 the
# target is `b/src/gamma.txt`, which does not exist and which `--check` will
# happily create. That is not a second reading of the patch, it is the prefix
# left on, so the headers still fix -p1, the receipt still names -p1, and the
# `b/` reading is recorded as refused rather than counted as an alternative.
printf 'gamma\n' >"$WT/src/gamma.txt"
git -C "$WT" add -N src/gamma.txt
git -C "$WT" diff >"$TMP/add.patch"
git -C "$WT" reset -q
rm -f "$WT/src/gamma.txt"
chmod 600 "$TMP/add.patch"
git -C "$WT" apply --check -p0 "$TMP/add.patch" \
  || fail 'the add fixture no longer applies at -p0, so it cannot prove the strip rule'
accepted "$TMP/add.patch"
jq -e '.operations == ["add"] and .files[0].path == "src/gamma.txt" and
       .strip.required == 1 and .strip.chosen == 1 and
       .strip.header_style == "git-prefixed" and
       .strip.alternate == 0 and .strip.alternate_applies == true and
       .strip.alternate_chosen == false and
       any(.policy_decisions[];
           .rule == "alternate_strip_level_cannot_redirect" and .result == "prefix-only")' \
  "$TMP/out.json" >/dev/null \
  || fail 'a new-file patch was not accepted at the level its headers fix'
pass=$((pass + 1))
[ "$(jq -r '[.files[].path] | join(",")' "$TMP/out.json")" = "src/gamma.txt" ] \
  || fail 'the add receipt named a path under an a/ or b/ component'
pass=$((pass + 1))

# The same rule where the alternate reading would hit real files: this worktree
# really does hold `a/x.txt` and `b/x.txt`, so the patch applies at -p0 as well
# and -p0 would edit `b/x.txt`. The headers still say -p1, the receipt still
# names `x.txt`, and the alternate is still refused.
SHADOW="$TMP/shadow"
mkdir -p "$SHADOW/a" "$SHADOW/b"
git -C "$SHADOW" init -q
printf 'one\n' >"$SHADOW/x.txt"
printf 'one\n' >"$SHADOW/a/x.txt"
printf 'one\n' >"$SHADOW/b/x.txt"
git -C "$SHADOW" add -A
git -C "$SHADOW" commit -q -m init
mkpatch "$TMP/shadow.patch" <<'EOF'
--- a/x.txt
+++ b/x.txt
@@ -1 +1 @@
-one
+two
EOF
git -C "$SHADOW" apply --check -p0 "$TMP/shadow.patch" \
  || fail 'the shadow fixture no longer applies at -p0, so it cannot prove the strip rule'
"$CMD" check --patch "$TMP/shadow.patch" --workdir "$SHADOW" --json >"$TMP/shadow.json" \
  || { jq -c '.violations' "$TMP/shadow.json" >&2; fail 'a conventional a/b patch was refused'; }
jq -e '.verdict == "accepted" and .strip.chosen == 1 and .strip.header_style == "git-prefixed" and
       .strip.alternate == 0 and .strip.alternate_applies == true and
       .strip.alternate_chosen == false and
       [.files[].path] == ["x.txt"]' "$TMP/shadow.json" >/dev/null \
  || { jq -c '.strip, .files' "$TMP/shadow.json" >&2
       fail 'the a/b receipt did not pin the change to x.txt at -p1'; }
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# 2. Malformed input, and the strip level it cannot be guessed from.
# ---------------------------------------------------------------------------

# Prose around the diff is the commonest chat-completions failure. Refusing it
# is the point: a parser that skips what it does not recognise is not a boundary.
mkpatch "$TMP/prose.patch" <<'EOF'
Sure! Here is the patch you asked for:

--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ -1,4 +1,4 @@
 alpha one
-alpha two
+alpha two changed
 alpha three
 alpha four
EOF
rejected_with "$TMP/prose.patch" unexpected_line

mkpatch "$TMP/bad-hunk-header.patch" <<'EOF'
--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ this is not a hunk header @@
-alpha two
+alpha two changed
EOF
rejected_with "$TMP/bad-hunk-header.patch" malformed_hunk_header

mkpatch "$TMP/truncated.patch" <<'EOF'
--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ -1,4 +1,4 @@
 alpha one
-alpha two
EOF
rejected_with "$TMP/truncated.patch" truncated_hunk

mkpatch "$TMP/no-hunks.patch" <<'EOF'
--- a/src/alpha.txt
+++ b/src/alpha.txt
EOF
rejected_with "$TMP/no-hunks.patch" no_hunks

mkpatch "$TMP/mixed-prefix.patch" <<'EOF'
--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ -1,1 +1,1 @@
-alpha one
+alpha ONE
--- src/beta.txt
+++ src/beta.txt
@@ -1,1 +1,1 @@
-beta one
+beta ONE
EOF
rejected_with "$TMP/mixed-prefix.patch" mixed_path_prefixes

# A header shape that fixes no level is refused before git is consulted at all.
# `a/x.txt` opposite `a/x.txt` does not say whether `a` is the prefix git strips
# or a directory in the repository, and the same goes for a half-stripped pair.
# Neither is guessed at.
mkpatch "$TMP/unpaired-same.patch" <<'EOF'
--- a/x.txt
+++ a/x.txt
@@ -1 +1 @@
-one
+two
EOF
rejected_with "$TMP/unpaired-same.patch" unpaired_path_prefixes
jq -e '.strip.required == null and .strip.chosen == null and
       .strip.header_style == null and .strip.alternate == null and
       .git_apply_check.ran == false' "$TMP/out.json" >/dev/null \
  || fail 'an unpaired header shape still fixed a strip level'
pass=$((pass + 1))

mkpatch "$TMP/unpaired-half.patch" <<'EOF'
--- a/src/alpha.txt
+++ src/alpha.txt
@@ -1 +1 @@
-alpha one
+alpha ONE
EOF
rejected_with "$TMP/unpaired-half.patch" unpaired_path_prefixes

mkpatch "$TMP/unpaired-swapped.patch" <<'EOF'
--- b/src/alpha.txt
+++ a/src/alpha.txt
@@ -1 +1 @@
-alpha one
+alpha ONE
EOF
rejected_with "$TMP/unpaired-swapped.patch" unpaired_path_prefixes

# A genuine second reading is still refused. These headers carry no prefix, so
# they fix -p0 — but this worktree also holds `x.txt`, so -p1 applies too, and
# -p1 is git's own default: a lead could land on the wrong file by habit. Two
# readings, one of them reachable by accident.
AMBIG="$TMP/ambig"
mkdir -p "$AMBIG/deep"
git -C "$AMBIG" init -q
printf 'one\n' >"$AMBIG/x.txt"
printf 'one\n' >"$AMBIG/deep/x.txt"
git -C "$AMBIG" add -A
git -C "$AMBIG" commit -q -m init
mkpatch "$TMP/ambiguous.patch" <<'EOF'
--- deep/x.txt
+++ deep/x.txt
@@ -1 +1 @@
-one
+two
EOF
set +e
"$CMD" check --patch "$TMP/ambiguous.patch" --workdir "$AMBIG" --json \
  >"$TMP/ambig.json" 2>"$TMP/ambig.err"
ambig_rc=$?
set -e
[ "$ambig_rc" -eq 65 ] || fail "an ambiguous strip level was not refused (exit $ambig_rc)"
jq -e '.verdict == "rejected" and .git_apply_check.result == "ambiguous" and
       .strip.required == 0 and .strip.chosen == null and
       .strip.header_style == "unprefixed" and
       .strip.alternate == 1 and .strip.alternate_applies == true and
       any(.violations[]; .rule == "ambiguous_strip_level") and
       any(.policy_decisions[];
           .rule == "alternate_strip_level_cannot_redirect" and .result == "fail")' \
  "$TMP/ambig.json" >/dev/null \
  || { jq -c '.violations' "$TMP/ambig.json" >&2; fail 'an ambiguous patch was not named as such'; }
pass=$((pass + 1))

# A patch whose context no longer matches is not applicable, and saying so is
# not the same as saying it is unsafe.
mkpatch "$TMP/stale.patch" <<'EOF'
--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ -1,2 +1,2 @@
 alpha zero
-alpha two
+alpha two changed
EOF
rejected_with "$TMP/stale.patch" patch_does_not_apply
jq -e '.git_apply_check.result == "not-applicable" and .git_apply_check.ran == true' \
  "$TMP/out.json" >/dev/null || fail 'a non-applying patch was not reported as such'
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# 3. Path confinement. Every escape shape gets its own rule.
# ---------------------------------------------------------------------------
escape_patch() { # $1=output, $2=path as it appears verbatim in both headers
  mkpatch "$1" <<EOF
--- $2
+++ $2
@@ -1 +1 @@
-old
+new
EOF
}

# The same escape in the conventional shape: `a/<path>` opposite `b/<path>`, so
# the headers fix -p1 and the path policy is applied to <path> once the prefix
# has been stripped. Confinement has to bite on the normalized path, not on the
# bytes the header happened to carry.
ab_escape_patch() { # $1=output, $2=path under the a/ and b/ prefixes
  mkpatch "$1" <<EOF
--- a/$2
+++ b/$2
@@ -1 +1 @@
-old
+new
EOF
}

escape_patch "$TMP/absolute.patch" /etc/passwd
rejected_with "$TMP/absolute.patch" absolute_path
escape_patch "$TMP/unc.patch" //server/share/payload.txt
rejected_with "$TMP/unc.patch" unc_path
escape_patch "$TMP/drive.patch" 'C:/Windows/System32/drivers/etc/hosts'
rejected_with "$TMP/drive.patch" drive_path
escape_patch "$TMP/backslash.patch" 'server\share\payload.txt'
rejected_with "$TMP/backslash.patch" backslash_path
ab_escape_patch "$TMP/traversal.patch" ../../../etc/passwd
rejected_with "$TMP/traversal.patch" parent_traversal
ab_escape_patch "$TMP/dotdir.patch" ./src/alpha.txt
rejected_with "$TMP/dotdir.patch" dot_component
ab_escape_patch "$TMP/emptycomp.patch" src//alpha.txt
rejected_with "$TMP/emptycomp.patch" empty_component
ab_escape_patch "$TMP/longpath.patch" \
  "$(printf 'x%.0s' $(seq 1 290))/deep.txt"
rejected_with "$TMP/longpath.patch" path_too_long
ab_escape_patch "$TMP/charset.patch" 'src/we|rd$(name).txt'
rejected_with "$TMP/charset.patch" path_charset

# Representable-but-hostile is classified; unrepresentable is refused without
# being echoed at all.
mkpatch "$TMP/spacey.patch" <<'EOF'
--- a/src/my file.txt
+++ b/src/my file.txt
@@ -1 +1 @@
-old
+new
EOF
rejected_with "$TMP/spacey.patch" path_not_representable
jq -e '[.violations[] | select(.detail != null) | .detail] | all(. | test("my file") | not)' \
  "$TMP/out.json" >/dev/null \
  || fail 'an unrepresentable path was echoed back into the receipt'
pass=$((pass + 1))

# The denied-path classes, one patch each.
denied_path() { # $1=label, $2=path, $3=rule id
  ab_escape_patch "$TMP/denied-$1.patch" "$2"
  rejected_with "$TMP/denied-$1.patch" "denied_path:$3"
}
denied_path gitconfig .git/config git-control
denied_path githooks .git/hooks/pre-commit git-control
denied_path gitattributes .gitattributes git-metadata
denied_path gitmodules .gitmodules git-metadata
denied_path husky .husky/pre-commit git-hooks
denied_path workflow .github/workflows/ci.yml ci-config
denied_path dotenv .env dotenv
denied_path dotenvlocal .env.local dotenv
denied_path envrc .envrc direnv
denied_path zshrc .zshrc shell-startup
denied_path sshdir .ssh/config ssh
denied_path authkeys src/authorized_keys ssh-material
denied_path pem certs/server.pem private-key
denied_path key certs/server.key private-key
denied_path crt certs/server.crt certificate
denied_path netrc .netrc credential-file
denied_path npmrc .npmrc credential-file
denied_path credname src/aws_credentials.json credential-name
denied_path awsdir .aws/config cloud-config
denied_path claudedir .claude/settings.json provider-auth
denied_path codexdir .codex/config.toml provider-auth

# Confinement is enforced on the normalized path, so the same escape hidden
# behind an unprefixed header is caught at strip level 0 too.
escape_patch "$TMP/unprefixed-git.patch" .git/config
rejected_with "$TMP/unprefixed-git.patch" "denied_path:git-control"

# ---------------------------------------------------------------------------
# 4. Capability smuggling: binary, symlink, submodule, mode.
# ---------------------------------------------------------------------------
mkpatch "$TMP/binary.patch" <<'EOF'
diff --git a/src/blob.bin b/src/blob.bin
new file mode 100644
index 0000000..1111111
GIT binary patch
literal 8
McmZQzU|<4b0000
EOF
rejected_with "$TMP/binary.patch" binary_patch

mkpatch "$TMP/binary-differ.patch" <<'EOF'
diff --git a/src/blob.bin b/src/blob.bin
index 1111111..2222222 100644
Binary files a/src/blob.bin and b/src/blob.bin differ
EOF
rejected_with "$TMP/binary-differ.patch" binary_patch

mkpatch "$TMP/symlink.patch" <<'EOF'
diff --git a/src/link b/src/link
new file mode 120000
index 0000000..1111111
--- /dev/null
+++ b/src/link
@@ -0,0 +1 @@
+/etc/passwd
EOF
rejected_with "$TMP/symlink.patch" symlink_mode

mkpatch "$TMP/submodule.patch" <<'EOF'
diff --git a/vendor/dep b/vendor/dep
new file mode 160000
index 0000000..1111111
--- /dev/null
+++ b/vendor/dep
@@ -0,0 +1 @@
+Subproject commit 1111111111111111111111111111111111111111
EOF
rejected_with "$TMP/submodule.patch" submodule

mkpatch "$TMP/mode-change.patch" <<'EOF'
diff --git a/src/alpha.txt b/src/alpha.txt
old mode 100644
new mode 100755
EOF
rejected_with "$TMP/mode-change.patch" mode_change

mkpatch "$TMP/new-executable.patch" <<'EOF'
diff --git a/src/deploy.sh b/src/deploy.sh
new file mode 100755
index 0000000..1111111
--- /dev/null
+++ b/src/deploy.sh
@@ -0,0 +1 @@
+echo deploying
EOF
rejected_with "$TMP/new-executable.patch" executable_new_file

# Editing a file the repository already carries as executable is not a mode
# change: the patch grants nothing the repository did not already have, so it is
# not refused on that ground. `index …  100755` must survive the mode screen.
printf '#!/bin/sh\necho two\n' >"$WT/src/exec.sh"
git -C "$WT" diff >"$TMP/existing-executable.patch"
git -C "$WT" checkout -q -- .
chmod 755 "$WT/src/exec.sh"
chmod 600 "$TMP/existing-executable.patch"
grep -q '^index .* 100755$' "$TMP/existing-executable.patch" \
  || fail 'the executable-file patch does not carry an executable index mode'
accepted "$TMP/existing-executable.patch"

# ---------------------------------------------------------------------------
# 5. Deletions and renames.
# ---------------------------------------------------------------------------
rm "$WT/src/beta.txt"
git -C "$WT" diff >"$TMP/delete.patch"
git -C "$WT" checkout -q -- .
chmod 600 "$TMP/delete.patch"
rejected_with "$TMP/delete.patch" delete_not_permitted
jq -e '.allow_flags.allow_delete == false' "$TMP/out.json" >/dev/null \
  || fail 'the default receipt did not record that deletions were not allowed'
pass=$((pass + 1))

# The explicit allowance is recorded, and confinement is unaffected by it.
accepted "$TMP/delete.patch" --allow-delete
jq -e '.allow_flags.allow_delete == true and .operations == ["delete"] and
       .files[0].path == "src/beta.txt"' "$TMP/out.json" >/dev/null \
  || fail 'the --allow-delete receipt did not record the flag or the operation'
pass=$((pass + 1))
ab_escape_patch "$TMP/delete-escape.patch" .git/config
rejected_with "$TMP/delete-escape.patch" "denied_path:git-control" --allow-delete

# Renames have no allowance at all: a rename is a delete plus an add wearing one
# name, and the lead should see both halves.
mkpatch "$TMP/rename.patch" <<'EOF'
diff --git a/src/beta.txt b/src/gamma.txt
similarity index 100%
rename from src/beta.txt
rename to src/gamma.txt
EOF
rejected_with "$TMP/rename.patch" rename_not_permitted
rejected_with "$TMP/rename.patch" rename_not_permitted --allow-delete

mkpatch "$TMP/copy.patch" <<'EOF'
diff --git a/src/beta.txt b/src/gamma.txt
similarity index 100%
copy from src/beta.txt
copy to src/gamma.txt
EOF
rejected_with "$TMP/copy.patch" copy_not_permitted

# The counts the receipt reports have to agree with the operation the headers
# declare. An add whose hunk takes lines away, or a delete whose hunk puts lines
# back, is describing itself as something it is not.
mkpatch "$TMP/add-with-removal.patch" <<'EOF'
--- /dev/null
+++ b/src/gamma.txt
@@ -1,1 +1,2 @@
-gamma zero
+gamma one
+gamma two
EOF
rejected_with "$TMP/add-with-removal.patch" removed_lines_in_new_file

mkpatch "$TMP/delete-with-addition.patch" <<'EOF'
--- a/src/beta.txt
+++ /dev/null
@@ -1,3 +1,1 @@
-beta one
-beta two
-beta three
+beta survives
EOF
rejected_with "$TMP/delete-with-addition.patch" added_lines_in_deleted_file --allow-delete
rejected_with "$TMP/delete-with-addition.patch" added_lines_in_deleted_file

# ---------------------------------------------------------------------------
# 6. Limits.
# ---------------------------------------------------------------------------
max_files="$(jq -r '.limits.max_files' "$POLICY")"
{
  i=0
  while [ "$i" -le "$max_files" ]; do
    printf -- 'diff --git a/src/f%s.txt b/src/f%s.txt\n' "$i" "$i"
    printf -- '--- a/src/f%s.txt\n+++ b/src/f%s.txt\n' "$i" "$i"
    printf -- '@@ -1 +1 @@\n-old\n+new\n'
    i=$((i + 1))
  done
} >"$TMP/too-many-files.patch"
chmod 600 "$TMP/too-many-files.patch"
rejected_with "$TMP/too-many-files.patch" too_many_files

max_added="$(jq -r '.limits.max_added_lines_per_file' "$POLICY")"
{
  printf -- '--- a/src/alpha.txt\n+++ b/src/alpha.txt\n'
  printf -- '@@ -1,0 +1,%s @@\n' "$((max_added + 1))"
  i=0
  while [ "$i" -le "$max_added" ]; do printf -- '+filler %s\n' "$i"; i=$((i + 1)); done
} >"$TMP/expansion.patch"
chmod 600 "$TMP/expansion.patch"
rejected_with "$TMP/expansion.patch" file_expansion_exceeded

# Over the byte ceiling, with lines long enough to stay under the line ceiling —
# the size rule has to bite on its own, before the patch is even parsed.
{
  printf -- '--- a/src/alpha.txt\n+++ b/src/alpha.txt\n@@ -1,0 +1,2000 @@\n'
  filler="$(printf 'x%.0s' $(seq 1 600))"
  i=0
  while [ "$i" -lt 2000 ]; do printf -- '+%s\n' "$filler"; i=$((i + 1)); done
} >"$TMP/too-big.patch"
chmod 600 "$TMP/too-big.patch"
rejected_with "$TMP/too-big.patch" patch_too_large
jq -e '.git_apply_check.ran == false and .file_count == 0' "$TMP/out.json" >/dev/null \
  || fail 'an oversized patch was parsed instead of being refused on sight'
pass=$((pass + 1))

: >"$TMP/empty.patch"
chmod 600 "$TMP/empty.patch"
rejected_with "$TMP/empty.patch" patch_file_empty

# ---------------------------------------------------------------------------
# 7. The patch file and the worktree themselves.
# ---------------------------------------------------------------------------
ln -sfn "$TMP/one-file.patch" "$TMP/patch-symlink.patch"
rejected_with "$TMP/patch-symlink.patch" patch_is_symlink

mkdir -p "$TMP/patch-dir.patch"
rejected_with "$TMP/patch-dir.patch" patch_not_a_regular_file

cp "$TMP/one-file.patch" "$TMP/world-writable.patch"
chmod 666 "$TMP/world-writable.patch"
rejected_with "$TMP/world-writable.patch" patch_file_group_or_world_writable

{ printf -- '--- a/src/alpha.txt\n'; head -c 8 /dev/zero; printf '\n'; } >"$TMP/nul.patch"
chmod 600 "$TMP/nul.patch"
rejected_with "$TMP/nul.patch" patch_contains_nul_bytes

printf -- '--- a/src/alpha.txt\r\n+++ b/src/alpha.txt\r\n' >"$TMP/crlf.patch"
chmod 600 "$TMP/crlf.patch"
rejected_with "$TMP/crlf.patch" patch_contains_carriage_returns

workdir_rejected() { # $1=workdir, $2=rule
  local rc=0
  set +e
  "$CMD" check --patch "$TMP/one-file.patch" --workdir "$1" --json >"$TMP/wd.json" 2>"$TMP/wd.err"
  rc=$?
  set -e
  [ "$rc" -eq 65 ] || { sed 's/^/    /' "$TMP/wd.err" >&2; fail "workdir $1: expected exit 65, got $rc"; }
  jq -e --arg r "$2" 'any(.violations[]; .rule == $r)' "$TMP/wd.json" >/dev/null \
    || { jq -c '.violations' "$TMP/wd.json" >&2; fail "workdir $1: expected violation $2"; }
  pass=$((pass + 1))
}

mkdir -p "$TMP/not-a-repo"
workdir_rejected "$TMP/not-a-repo" workdir_has_no_git_control
workdir_rejected "$WT/src" workdir_has_no_git_control
ln -sfn "$WT" "$TMP/wt-symlink"
workdir_rejected "$TMP/wt-symlink" workdir_is_symlink
mkdir -p "$TMP/wt-gitsym"
ln -sfn "$WT/.git" "$TMP/wt-gitsym/.git"
workdir_rejected "$TMP/wt-gitsym" git_control_is_a_symlink

exit_code 66 "$CMD" check --patch "$TMP/absent.patch" --workdir "$WT"
exit_code 66 "$CMD" check --patch "$TMP/one-file.patch" --workdir "$TMP/absent-dir"
exit_code 64 "$CMD" check --workdir "$WT"
exit_code 64 "$CMD" check --patch "$TMP/one-file.patch"
exit_code 64 "$CMD" check --patch "$TMP/one-file.patch" --workdir "$WT" --apply
exit_code 64 "$CMD" not-a-command
exit_code 64 "$CMD" policy --bogus
exit_code 0 "$CMD" policy
exit_code 0 "$CMD" policy --json
exit_code 0 "$CMD" --help
exit_code 66 env DELEGATION_EXTERNAL_PATCH_POLICY_FILE="$TMP/absent-policy.json" "$CMD" policy

# ---------------------------------------------------------------------------
# 8. Read-only, against a deliberately dirty worktree.
# ---------------------------------------------------------------------------
DIRTY="$TMP/dirty"
mkdir -p "$DIRTY/src"
git -C "$DIRTY" init -q
printf 'alpha one\nalpha two\nalpha three\nalpha four\n' >"$DIRTY/src/alpha.txt"
printf 'staged\n' >"$DIRTY/src/staged.txt"
git -C "$DIRTY" add -A
git -C "$DIRTY" commit -q -m init
printf 'alpha one\nalpha two edited by the lead\nalpha three\nalpha four\n' >"$DIRTY/src/alpha.txt"
printf 'staged change\n' >"$DIRTY/src/staged.txt"
git -C "$DIRTY" add src/staged.txt
printf 'untracked\n' >"$DIRTY/src/untracked.txt"

dirty_state() {
  git -C "$DIRTY" status --porcelain --untracked-files=all
  git -C "$DIRTY" diff
  git -C "$DIRTY" diff --cached
  find "$DIRTY" -type f ! -path '*/.git/*' -exec shasum -a 256 {} \; | sort
  shasum -a 256 "$DIRTY/.git/index" "$DIRTY/.git/HEAD" "$DIRTY/.git/config"
}
# One warm-up pass first: `git status` may legitimately refresh its own stat
# cache the first time, and that refresh must not be mistaken for a write the
# verifier made.
git -C "$DIRTY" status --porcelain >/dev/null
dirty_state >"$TMP/dirty.before"
patch_before="$(shasum -a 256 "$TMP/one-file.patch" | awk '{print $1}')"

# One patch that applies here and one that does not; neither may change a byte.
mkpatch "$TMP/dirty-applies.patch" <<'EOF'
--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ -1,4 +1,4 @@
 alpha one
-alpha two edited by the lead
+alpha two edited again
 alpha three
 alpha four
EOF
set +e
"$CMD" check --patch "$TMP/dirty-applies.patch" --workdir "$DIRTY" --json \
  >"$TMP/dirty1.json" 2>"$TMP/dirty1.err"
dirty_rc=$?
"$CMD" check --patch "$TMP/stale.patch" --workdir "$DIRTY" --json \
  >"$TMP/dirty2.json" 2>"$TMP/dirty2.err"
"$CMD" check --patch "$TMP/symlink.patch" --workdir "$DIRTY" --json \
  >"$TMP/dirty3.json" 2>"$TMP/dirty3.err"
set -e
[ "$dirty_rc" -eq 0 ] || { jq -c '.violations' "$TMP/dirty1.json" >&2; fail 'a valid patch against a dirty worktree was refused'; }
dirty_state >"$TMP/dirty.after"
cmp -s "$TMP/dirty.before" "$TMP/dirty.after" \
  || { diff "$TMP/dirty.before" "$TMP/dirty.after" >&2 || true; fail 'the verifier changed a dirty worktree'; }
[ "$patch_before" = "$(shasum -a 256 "$TMP/one-file.patch" | awk '{print $1}')" ] \
  || fail 'the verifier rewrote the patch file'
pass=$((pass + 1))

# The receipt attests the same thing from the inside, on every verdict.
for receipt in "$TMP/dirty1.json" "$TMP/dirty2.json" "$TMP/dirty3.json"; do
  jq -e '.read_only == true and .applies_patch == false and
         .attestation.unchanged == true and
         .attestation.patch_sha256_before == .attestation.patch_sha256_after and
         .attestation.worktree_state_sha256_before == .attestation.worktree_state_sha256_after and
         .attestation.index_sha256_before == .attestation.index_sha256_after and
         .attestation.git_control_sha256_before == .attestation.git_control_sha256_after and
         (.attestation.worktree_state_sha256_before | length) == 64' "$receipt" >/dev/null \
    || fail "$(basename "$receipt"): the read-only attestation is missing or incomplete"
done
pass=$((pass + 1))

# The command never writes into this checkout either.
before="$(git -C "$ROOT" status --porcelain)"
"$CMD" check --patch "$TMP/one-file.patch" --workdir "$WT" --json >/dev/null
"$CMD" policy >/dev/null
[ "$before" = "$(git -C "$ROOT" status --porcelain)" ] \
  || fail 'running the patch verifier changed the checkout'
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# 9. The receipt carries no patch content and no secret.
# ---------------------------------------------------------------------------
mkpatch "$TMP/sentinel.patch" <<'EOF'
--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ -1,4 +1,5 @@ SENTINELSECTIONHEADING
 alpha one
-alpha two
+alpha two changed
+SENTINELBODYLINE AKIAIOSFODNN7EXAMPLE Bearer sk-sentineltokenvalue0123456789
 alpha three
 alpha four
EOF
run_json "$TMP/sentinel.patch" || fail 'the sentinel patch did not verify'
for secret in SENTINELSECTIONHEADING SENTINELBODYLINE AKIAIOSFODNN7EXAMPLE \
              sk-sentineltokenvalue0123456789 'alpha two changed'; do
  if grep -Fq "$secret" "$TMP/out.json"; then
    fail "the receipt echoed patch content: $secret"
  fi
done
jq -e '.patch.sha256 != null and (.patch.sha256 | length) == 64 and .patch.bytes > 0 and
       .files[0].added_lines == 2' "$TMP/out.json" >/dev/null \
  || fail 'the receipt described the sentinel patch by digest and counts'
pass=$((pass + 1))

# The text receipt is held to the same rule.
"$CMD" check --patch "$TMP/sentinel.patch" --workdir "$WT" >"$TMP/sentinel.txt"
for secret in SENTINELSECTIONHEADING SENTINELBODYLINE AKIAIOSFODNN7EXAMPLE; do
  if grep -Fq "$secret" "$TMP/sentinel.txt"; then
    fail "the text receipt echoed patch content: $secret"
  fi
done
grep -Fq 'the lead applies it with -p1 and runs the tests' "$TMP/sentinel.txt" \
  || fail 'the text receipt did not restate that the lead applies the patch'
grep -Fq 'fixed by the git-prefixed header shape' "$TMP/sentinel.txt" \
  || fail 'the text receipt did not say which header shape fixed the strip level'
pass=$((pass + 1))

# The same, for the reading the verifier refuses: the add applies at -p0 too and
# the text receipt has to say so, in words, rather than leaving the lead to
# wonder why one level was picked.
"$CMD" check --patch "$TMP/add.patch" --workdir "$WT" >"$TMP/add.txt"
grep -Fq 'strip level: -p1' "$TMP/add.txt" \
  || fail 'the text receipt did not name the strip level for the add'
grep -Fq -- '-p0 also applies but would keep the a/ or b/ component, and is never chosen' \
  "$TMP/add.txt" || fail 'the text receipt did not describe the refused alternate reading'
pass=$((pass + 1))

# A rejected patch whose git-apply failure quotes context must not leak it
# either: git's stderr is captured and discarded.
"$CMD" check --patch "$TMP/stale.patch" --workdir "$WT" >"$TMP/stale.txt" 2>"$TMP/stale.err" || true
for secret in 'alpha zero' 'alpha two changed'; do
  if grep -Fq "$secret" "$TMP/stale.txt" || grep -Fq "$secret" "$TMP/stale.err"; then
    fail "a failing git apply leaked patch context: $secret"
  fi
done
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# 10. Policy, and the contract that requires it.
# ---------------------------------------------------------------------------
"$CMD" policy --json >"$TMP/policy.json"
jq -e '.schema_version == 1 and .verifier == "delegation-patch-verify" and
       .applies_to_permission_class == "text-patch" and
       .authority.applies_patch == false and .authority.applied_by == "lead"' \
  "$TMP/policy.json" >/dev/null || fail 'policy --json did not describe the shipped policy'
pass=$((pass + 1))

# The policy documents the strip rule the verifier implements, under the same
# names the receipt and the violations use, so the two cannot drift apart.
jq -e '.strip.candidates == [0, 1] and .strip.fixed_by == "header-grammar" and
       .strip.require_single_applicable_level == true and
       (.strip.header_styles | keys | sort) == ["git-prefixed", "unprefixed"] and
       .strip.header_styles["git-prefixed"] == 1 and
       .strip.header_styles["unprefixed"] == 0 and
       .strip.unrecognized_header_shape == "unpaired_path_prefixes" and
       .strip.mixed_header_shapes == "mixed_path_prefixes" and
       .strip.alternate_level == "recorded, never chosen"' \
  "$TMP/policy.json" >/dev/null || fail 'the policy does not document the strip rule the verifier applies'
pass=$((pass + 1))

# The receipt names the exact policy it enforced, by version and by digest.
run_json "$TMP/one-file.patch"
jq -e --slurpfile policy "$POLICY" '
  .policy_version == $policy[0].policy_version and
  .policy_schema_version == $policy[0].schema_version and
  (.policy_sha256 | length) == 64 and
  .enforcement_authority == "patch-verifier" and .grants_permissions == false' \
  "$TMP/out.json" >/dev/null || fail 'the receipt did not name the policy it enforced'
pass=$((pass + 1))

# Every rule the receipt reports resolves to a rule the policy declares, so a
# violation can never be a name invented at the point of failure.
"$CMD" check --patch "$TMP/denied-dotenv.patch" --workdir "$WT" --json \
  >"$TMP/denied.json" 2>/dev/null || true
jq -e --slurpfile policy "$POLICY" '
  [.violations[] | select(.rule | startswith("denied_path:")) |
    .rule | sub("^denied_path:"; "")] as $ids |
  ($ids | length) > 0 and
  (($ids - ($policy[0].paths.denied_patterns | map(.id))) | length) == 0' \
  "$TMP/denied.json" >/dev/null || fail 'a denied-path rule named an id the policy does not declare'
pass=$((pass + 1))

# The verifier is what the contract's text-patch lanes point at, and nothing in
# the kit routes through it: it is a tool the lead runs, not a dispatch layer.
CONTRACT="$ROOT/config/external-executor-contract.json"
jq -e --slurpfile policy "$POLICY" '
  .patch_policy.verifier == "delegation-patch-verify" and
  .patch_policy.policy_file == "external-patch-policy.json" and
  .patch_policy.policy_version == $policy[0].policy_version and
  ([.families[].lanes[] | select(.permission_class == "text-patch")] | length) == 4' \
  "$CONTRACT" >/dev/null || fail 'the contract does not point its text-patch lanes at this verifier'
pass=$((pass + 1))
for runner in glm kimi grok qwen deepseek gemini route; do
  ! grep -q 'delegation-patch-verify' "$ROOT/bin/delegation-$runner" \
    || fail "bin/delegation-$runner calls the patch verifier; it must stay a tool the lead runs"
done
! grep -qE 'git apply|apply --check' "$ROOT/bin/delegation-qwen" \
  || fail 'the Qwen runner grew a patch-applying code path'
! grep -qE 'git apply|apply --check' "$ROOT/bin/delegation-deepseek" \
  || fail 'the DeepSeek runner grew a patch-applying code path'
pass=$((pass + 1))

# The verifier has no apply path at all.
! grep -qE 'git[^|]*apply[^-]*(--index|--cached|--3way|--unsafe-paths)' "$CMD" \
  || fail 'the verifier passes an option that would write'
grep -q 'apply --check' "$CMD" || fail 'the verifier does not run git apply --check'
pass=$((pass + 1))

# The installer, uninstaller, and doctor all know about it.
grep -q 'bin/delegation-patch-verify' "$ROOT/install.sh" \
  || fail 'install.sh does not install the patch verifier'
grep -q 'config/external-patch-policy.json' "$ROOT/install.sh" \
  || fail 'install.sh does not install the patch policy'
grep -q 'delegation-patch-verify' "$ROOT/uninstall.sh" \
  || fail 'uninstall.sh does not remove the installed patch verifier'
grep -q 'external-patch-policy.json' "$ROOT/doctor.sh" \
  || fail 'doctor.sh does not check the installed patch policy'
pass=$((pass + 1))

printf 'external patch verifier tests: %s passed\n' "$pass"
