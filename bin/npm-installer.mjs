#!/usr/bin/env node
// delegation-kit npm installer — a thin wrapper over the repository's own
// ./install.sh. `npx delegation-kit` clones the checked-out release, verifies
// its integrity, and runs the installer with your flags. Nothing is copied
// into node_modules; the installed artifacts are exactly the files, links,
// and guarded blocks the universal installer writes.
//
// Usage:
//   npx delegation-kit [--claude-only | --codex-only] [--ref <git-ref>]
//                      [--repo <git-url>] [--uninstall] [--skip-doctor]
//                      [-- yes, more args are forwarded verbatim]
//
// The wrapper never edits config files itself and never handles credentials.

import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";

const DEFAULT_REPO = "https://github.com/matteoscurati/delegation-kit";
const KNOWN_FLAGS = new Set([
  "--claude-only",
  "--codex-only",
  "--uninstall",
  "--skip-doctor",
  "--ref",
  "--repo",
]);

function die(message, code = 1) {
  console.error(`delegation-kit: ${message}`);
  process.exit(code);
}

function have(command) {
  return spawnSync(command, { stdio: "ignore" }).error === undefined
    || spawnSync(command, ["--version"], { stdio: "ignore" }).status !== null;
}

function run(command, args, opts = {}) {
  const result = spawnSync(command, args, { stdio: "inherit", ...opts });
  if (result.error) {
    die(`failed to run ${command}: ${result.error.message}`);
  }
  return result.status ?? 1;
}

function parseArgs(argv) {
  const options = {
    forward: [],
    ref: null,
    repo: null,
    uninstall: false,
    skipDoctor: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!KNOWN_FLAGS.has(arg)) {
      // Unknown flags are forwarded verbatim so the npm wrapper never becomes
      // a second CLI surface that drifts from ./install.sh.
      options.forward.push(arg);
      continue;
    }
    switch (arg) {
      case "--claude-only":
      case "--codex-only":
        options.forward.push(arg);
        break;
      case "--uninstall":
        options.uninstall = true;
        break;
      case "--skip-doctor":
        options.skipDoctor = true;
        options.forward.push("--skip-doctor");
        break;
      case "--ref":
        options.ref = argv[i + 1];
        i += 1;
        break;
      case "--repo":
        options.repo = argv[i + 1];
        i += 1;
        break;
      default:
        break;
    }
  }
  return options;
}

function assertPrerequisites() {
  for (const command of ["git", "jq"]) {
    if (!have(command)) {
      die(`${command} is required (see README "Quick start")`);
    }
  }
}

function cloneToTemp(repo, ref) {
  if (!have("git")) {
    die("git is required");
  }
  const dir = mkdtempSync(join(tmpdir(), "delegation-kit-"));
  const args = ["clone", "--depth", "1"];
  if (ref) {
    args.push("--branch", ref);
  }
  args.push(repo, dir);
  const status = run("git", args, { stdio: "pipe" });
  if (status !== 0) {
    rmSync(dir, { recursive: true, force: true });
    die(`could not clone ${repo}${ref ? ` (ref ${ref})` : ""} — check the URL and your network`, status);
  }
  return dir;
}

function integrityCheck(checkout) {
  // The npm wrapper is a delivery channel only: refuse to run an installer
  // that does not match the repository's own integrity rules.
  const required = [
    "install.sh",
    "uninstall.sh",
    "doctor.sh",
    "config/routing-gates.json",
  ];
  for (const file of required) {
    try {
      if (!statSync(join(checkout, file)).isFile()) {
        die(`integrity check failed: ${file} is missing in the cloned checkout`);
      }
    } catch {
      die(`integrity check failed: ${file} is missing in the cloned checkout`);
    }
  }
  const guard = run(
    "grep",
    ["-q", "No standing permission to delegate", join(checkout, "claude/CLAUDE.delegation.md")],
    { stdio: "ignore" },
  );
  if (guard !== 0) {
    die("integrity check failed: the user-direction guard is missing from this checkout");
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  assertPrerequisites();

  if (options.uninstall) {
    // Uninstalling needs the original checkout (or data-home overrides), so
    // this path does not clone: it runs ./uninstall.sh from the current
    // directory, exactly like the manual workflow.
    const status = run("./uninstall.sh", options.forward);
    process.exit(status);
  }

  const checkout = cloneToTemp(options.repo ?? DEFAULT_REPO, options.ref);
  let exitCode = 0;
  try {
    integrityCheck(checkout);
    exitCode = run("./install.sh", options.forward, { cwd: checkout });
    if (exitCode !== 0) {
      console.error(`delegation-kit: install.sh exited with ${exitCode}`);
    }
    if (exitCode === 0 && !options.skipDoctor) {
      exitCode = run("./doctor.sh", [], { cwd: checkout });
    }
  } finally {
    rmSync(checkout, { recursive: true, force: true });
  }
  process.exit(exitCode);
}

main();
