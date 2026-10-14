# delegation-kit

User-directed model delegation for Claude Code and Codex. Configure the models
you want through existing native adapters or any supported OpenAI-compatible
text endpoint. No kit qualification or benchmark is required to use a model.

Your models. Your call. Your rules. Every dispatch requires an explicit user
request. Authorization never silently extends to retries, fallback, review or
more workers. The lead verifies results before integration. Review is optional
by default, with `required` and `cross-family` policies available.

## Quick start

```sh
./install.sh
# Inspect and edit the personal configuration, then validate it:
delegation-config show
delegation-config validate
delegation-config apply
delegation-route resolve --lane builder --json
delegation-router check
```

The installer initializes the personal configuration only if absent and backs
up a legacy installation before migration. Profiles live outside projects at
`${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/config.json`, with an explicit
`DELEGATION_CONFIG_FILE` override. Never put credential values in profiles.

[Configuration examples and migration](docs/user-configuration.md) include an
existing provider and a local endpoint, parameter support, model identity,
review policies and output schemas. Selection is read-only and grants no
permission. Run a selected profile only when the user explicitly requests it:

```sh
delegation-run --profile PROFILE --lane builder \
  --prompt-file /tmp/task.txt --output /tmp/result.txt --workdir /path/to/repo
```

## Capabilities and evidence

Native adapters retain sandbox and file-access controls. Text adapters only
send the supplied prompt and return text or a patch; assigning a builder role
cannot grant worktree access. No automatic provider substitution or retry.

[`delegation-router`](docs/router.md) is a local model router: declare a pool
of profiles, a default and a decider in the personal configuration, run
`delegation-router serve` on loopback, and send `"model": "auto"` to it from
any OpenAI-compatible client. The router picks one profile inside that pool
per request — HTTP profiles with their own key, native profiles through
`delegation-run` — and names the profile and model in every response. The
decider is one of your cheap profiles, Levanto Sage, TypeSafe Jev, a Dipylon
or a local classifier; `delegation-router eval` measures it against the
rules-only baseline on a golden set of yours. The router never retries,
falls back, or widens the pool; `delegation-router decide` recommends without
dispatching.

Metrics distinguish requested model identity from provider-reported identity.
An absent identity is usable as `requested-only`; an incompatible response model
fails unless its alias was explicitly configured. Provider reports are not
independent certification.

The kit ships no routing gates, benchmark evidence, or qualification
machinery. `config/presets.json` holds the starting profiles, adapters own their
roles and efforts, and `evaluation/` is a frozen archive of earlier
qualification runs that no command reads.

## Current release: 0.27.0

Version 0.27.0 adds `delegation-router`, a local model router: a `router`
block in a schema 2 personal configuration declares a pool of HTTP profiles,
a default and a decider; `check` and `decide` are read-only; `serve` is an
OpenAI-compatible endpoint on loopback that, for `"model": "auto"`, runs a
deterministic prefilter, a decider (one of your cheap profiles, Sage, Jev,
Dipylon or a local classifier: difficulty 0–4 plus tags) and the `tiered-v1`
policy, forwards — HTTP profiles with their own key, native profiles through
`delegation-run` — streams through, and discloses the choice in headers and
a `router` object. A cost ceiling, opt-in receipts without prompt content, a
browser-origin refusal, a shipped model catalog and an offline `eval` of the
decider against the rules-only baseline come with it. Version 0.26.x removed every dispatch
timeout the kit imposed on its own and the `--allow-provisional` no-op;
0.25.x removed the qualification machinery (gates, contract, evidence) in
favour of `config/presets.json` and read-only `delegation-route` discovery.
Explicit per-dispatch authorization, sandboxes, model identity checks, and
the patch trust boundary are unchanged. See [`CHANGELOG.md`](./CHANGELOG.md)
for details and full history.

## Documentation

- [Personal configuration, adapters and migration](docs/user-configuration.md)
- [Model router: pool, decider, policy, disclosure](docs/router.md)
- [Routing policy (advisory)](model-routing.md)
- [External executors: adapters and their limits](docs/external-executors.md)
- [Compatibility and release verification](docs/compatibility.md)
- [Adapting the kit](ADAPTING.md)

## Testing

```sh
./run-tests.sh
npm test
```

The suites use isolated fixtures and simulated providers. Tests do not authorize
or prove live provider behavior. Releases and live paid tests are separate work.

## npm package

`npx delegation-kit` runs the installer from a verified release checkout.
The npm package is an installer wrapper, not a second runtime implementation.

## License

MIT. See [LICENSE](LICENSE).
