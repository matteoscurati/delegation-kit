# delegation-kit — repository conventions

## Release tagging

**Tag format — `delegation-kit--v<MAJOR>.<MINOR>.<PATCH>`.** Package name, two
hyphens, `v`, semver. Example: `delegation-kit--v0.10.0`.

> The generic `release` skill defaults to a bare `v<VERSION>` tag. That is wrong
> for this repository. Override it — every one of the eight existing tags uses
> the prefixed form, and a bare `v0.x.0` would fork the history into two naming
> schemes.

Rules, all of which the existing tags already follow:

- **Always annotated**, never lightweight: `git tag -a`. A lightweight tag
  carries no message, author, or date of its own.
- **Message** = subject `delegation-kit <VERSION>`, blank line, then a short
  prose summary of what shipped. Write it to a file and pass `-F`; release prose
  contains backticks and newlines that get mangled inline.
- **Tag the merge commit on `main`**, never a commit on the feature branch.
  Tag after the PR merges, not before.
- **Push the commit before the tag**, so the tag never points at something the
  remote does not have.
- **A tag that exists is final.** If a run dies after tagging, re-push — never
  delete and recreate a pushed tag.

### Every tag gets a GitHub Release

A tag alone is invisible on the repository landing page: the "Latest" badge
tracks Releases, not tags. Create the Release in the same pass as the tag:

```sh
gh release create "delegation-kit--v<VERSION>" \
  --title "delegation-kit <VERSION>" --notes-file "$notes"
```

Reuse the CHANGELOG section for that version as the notes body.

### Version surfaces

A bump must touch **all five**, or the installed plugin reports a version the
repository does not claim:

| file | occurrences |
|---|---|
| `.claude-plugin/plugin.json` | 1 |
| `.claude-plugin/marketplace.json` | 2 (`metadata.version` and the plugin entry) |
| `README.md` | the `## Current release: X.Y.Z` heading and its paragraph |
| `CHANGELOG.md` | a new `## [X.Y.Z] — YYYY-MM-DD` section |

Confirm with `grep -rn "<OLD VERSION>"` before committing that nothing stale
remains. There is no `package.json`; this is not an npm package, so nothing
publishes automatically.

### Semver for this repo

- **patch** — a bounded fix or a limit change that alters no routing decision.
- **minor** — a new lane, runner, or command; a routing gate promotion; a config
  file rename. Everything pre-1.0 that would otherwise be breaking.
- **major** — reserved for 1.0.

### Before tagging

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:
shellcheck at `-S warning`, the version-surface check, and the regression suites
on macOS. A tag push additionally re-runs `tests/version-consistency.sh --tag`,
which fails a tag that does not match `delegation-kit--v<the manifest version>`.

CI is not the whole gate. It cannot run `./doctor.sh --ping`, which needs
authenticated Claude and Codex CLIs, and it does not exercise any real external
model. Before tagging, run the gates in
[`docs/compatibility.md`](./docs/compatibility.md) locally and refresh that
page's verified snapshot with the real numbers you observed. Do not carry the
previous release's numbers forward.

You can run either gate by hand:

```sh
tests/version-consistency.sh
tests/version-consistency.sh --tag delegation-kit--v<VERSION>
```

### Is this machine running the current kit?

`install.sh` records what it installed in
`$DELEGATION_DATA_HOME/installed-version.json`, and `doctor.sh` compares it
against the checkout. Ask it rather than diffing files by hand:

```sh
./doctor.sh          # the "Installed version" section answers this
```

A version mismatch is a FAIL. A matching version with a different commit is a
warning — normal while unreleased work sits on `main`, and the fix is the same:
re-run `./install.sh`. The marker is written last, so it exists only if the
install reached the end.

## Routing gates

Never promote a lane, widen a selection, or edit `config/routing-gates.json` and
the executable `config/*-routing.json` gates as a side effect of other work. A
promotion is an explicit owner decision and must say in the gate whether it rests
on measured evidence or on an owner override. `bin/delegation-route` validates
that the central and executable gates agree; run `delegation-route check` after
touching either.

Frozen evaluation artifacts under `evaluation/*-qualification-v*/` are historical
records. Do not rewrite them when a model, pin, or runner changes — supersede
them instead.
