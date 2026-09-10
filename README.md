# delegation-kit

User-directed model delegation for Claude Code and Codex. Configure the models
you want through existing native adapters or any supported OpenAI-compatible
text endpoint. No kit qualification or benchmark is required to use a model.

Every dispatch requires an explicit user request. Authorization never silently
extends to retries, fallback, review or more workers. The lead verifies results
before integration. Review is optional by default, with `required` and
`cross-family` policies available.

## Quick start

```sh
./install.sh
# Inspect and edit the personal configuration, then validate it:
delegation-config show
delegation-config validate
delegation-config apply
delegation-route resolve --lane builder --json
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

Metrics distinguish requested model identity from provider-reported identity.
An absent identity is usable as `requested-only`; an incompatible response model
fails unless its alias was explicitly configured. Provider reports are not
independent certification.

`delegation-evidence`, the distributed routing records and `evaluation/` retain
historical benchmarks and qualification artifacts. Their old quality statuses
are information, not current execution permissions. Provider-specific commands
and manifest-bound scientific evaluation workflows remain available.

## Current release: 0.24.0

Version 0.24.0 makes the models a user choice. Profiles live in a personal
configuration (`delegation-config`), one dispatcher runs a selected profile
through its adapter (`delegation-run`, including any OpenAI-compatible text
endpoint), review is optional by default with `required` and `cross-family`
policies, and the historical routing gates and benchmark evidence become
advisory records instead of execution permissions. Explicit per-dispatch
authorization, sandboxes, and the patch trust boundary are unchanged. DeepSeek
is re-pinned to V4.1 Flash and the staged Gemini bridge to 3.8 Flash. See
[`CHANGELOG.md`](./CHANGELOG.md) for details and full history.

## Documentation

- [Personal configuration, adapters and migration](docs/user-configuration.md)
- [Routing policy](model-routing.md)
- [External executors and technical contracts](docs/external-executors.md)
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
