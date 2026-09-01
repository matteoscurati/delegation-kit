// Tests for the delegation-kit npm installer wrapper.
// Run: node --test tests/npm-installer.test.mjs
// The wrapper is exercised end-to-end against a LOCAL file:// clone so no
// network access and no real Claude/Codex homes are touched.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const INSTALLER = join(ROOT, "bin", "npm-installer.mjs");

function makeLocalRepo() {
  // A minimal stand-in for the delegation-kit checkout: the wrapper's
  // integrity check only requires the installer files and the guard phrase.
  const dir = mkdtempSync(join(tmpdir(), "delegation-kit-npm-test-"));
  const sh = (name, body) => {
    writeFileSync(join(dir, name), `#!/usr/bin/env bash\n${body}\n`);
    spawnSync("chmod", ["+x", join(dir, name)]);
  };
  sh("install.sh", 'echo "install ran with: $*"; exit 0');
  sh("uninstall.sh", 'echo "uninstall ran with: $*"; exit 0');
  sh("doctor.sh", "echo doctor-ok; exit 0");
  mkdirSync(join(dir, "config"), { recursive: true });
  writeFileSync(join(dir, "config", "routing-gates.json"), "{}\n");
  mkdirSync(join(dir, "claude"), { recursive: true });
  copyFileSync(
    join(ROOT, "claude", "CLAUDE.delegation.md"),
    join(dir, "claude", "CLAUDE.delegation.md"),
  );
  spawnSync("git", ["init", "-q"], { cwd: dir });
  spawnSync("git", ["-C", dir, "add", "-A"]);
  spawnSync("git", ["-C", dir, "commit", "-qm", "fixture"]);
  return dir;
}

function runInstaller(args, env = {}) {
  return spawnSync(process.execPath, [INSTALLER, ...args], {
    encoding: "utf8",
    env: { ...process.env, ...env },
  });
}

test("wrapper refuses to run without git/jq prerequisites", () => {
  const result = runInstaller([], { PATH: "/nonexistent" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /git is required|jq is required/);
});

test("integrity check fails when the guard is missing", () => {
  const repo = mkdtempSync(join(tmpdir(), "dk-noguard-"));
  try {
    // Clone the good fixture first, then strip the guard from a fresh copy.
    const good = makeLocalRepo();
    const dest = join(repo, "checkout");
    rmSync(dest, { recursive: true, force: true });
    spawnSync("git", ["clone", "-q", good, dest]);
    writeFileSync(join(dest, "claude", "CLAUDE.delegation.md"), "# no guard here\n");
    spawnSync("git", ["-C", dest, "add", "-A"]);
    spawnSync("git", ["-C", dest, "commit", "-qm", "strip guard"]);

    const result = runInstaller(["--repo", dest, "--skip-doctor"]);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /user-direction guard is missing/);
    rmSync(good, { recursive: true, force: true });
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("happy path: clones, verifies integrity, runs install then doctor", () => {
  const repo = makeLocalRepo();
  try {
    const result = runInstaller(["--repo", repo, "--claude-only"]);
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);
    assert.match(result.stdout, /install ran with: --claude-only/);
    assert.match(result.stdout, /doctor-ok/);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("--skip-doctor runs the installer only", () => {
  const repo = makeLocalRepo();
  try {
    const result = runInstaller(["--repo", repo, "--skip-doctor"]);
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);
    assert.match(result.stdout, /install ran with: --skip-doctor/);
    assert.doesNotMatch(result.stdout, /doctor-ok/);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("unknown flags are forwarded verbatim to install.sh", () => {
  const repo = makeLocalRepo();
  try {
    const result = runInstaller(["--repo", repo, "--skip-doctor", "--some-future-flag", "value"]);
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);
    assert.match(result.stdout, /--some-future-flag value/);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("--uninstall invokes uninstall.sh from the current directory", () => {
  // --uninstall must NOT clone; it runs ./uninstall.sh from the caller's cwd,
  // matching the manual workflow. Verify with a cwd that holds the script.
  const cwd = mkdtempSync(join(tmpdir(), "dk-uninstall-cwd-"));
  try {
    writeFileSync(join(cwd, "uninstall.sh"), "#!/usr/bin/env bash\necho 'uninstall ran'; exit 0\n");
    spawnSync("chmod", ["+x", join(cwd, "uninstall.sh")]);
    const result = spawnSync(process.execPath, [INSTALLER, "--uninstall"], {
      encoding: "utf8",
      cwd,
    });
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);
    assert.match(result.stdout, /uninstall ran/);
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
});

test("a failing install.sh propagates its exit code and skips doctor", () => {
  const repo = makeLocalRepo();
  try {
    writeFileSync(join(repo, "install.sh"), "#!/usr/bin/env bash\nexit 3\n");
    spawnSync("chmod", ["+x", join(repo, "install.sh")]);
    spawnSync("git", ["-C", repo, "add", "-A"]);
    spawnSync("git", ["-C", repo, "commit", "-qm", "failing installer"]);
    const result = runInstaller(["--repo", repo, "--skip-doctor"]);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /exited with 3/);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("the cloned temp checkout is cleaned up", () => {
  const repo = makeLocalRepo();
  try {
    const before = new Set(
      spawnSync("bash", ["-c", `ls -1d ${tmpdir()}/delegation-kit-* 2>/dev/null || true`], {
        encoding: "utf8",
      }).stdout.trim().split("\n").filter(Boolean),
    );
    const result = runInstaller(["--repo", repo, "--skip-doctor"]);
    assert.equal(result.status, 0);
    const after = spawnSync("bash", ["-c", `ls -1d ${tmpdir()}/delegation-kit-* 2>/dev/null || true`], {
      encoding: "utf8",
    }).stdout.trim().split("\n").filter(Boolean);
    for (const dir of after) {
      assert.ok(before.has(dir), `temp checkout leaked: ${dir}`);
    }
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});
