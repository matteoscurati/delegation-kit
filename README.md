# delegation-kit

You choose the decision model. It governs the models you already pay for.

Name a decider — one of your cheap models, Levanto Sage, TypeSafe Jev, your
own Dipylon, a local classifier — and the pool it governs: API keys, a Claude
or Codex subscription, a local endpoint. `delegation-router serve` is an
OpenAI-compatible endpoint on your own machine. Send it `"model": "auto"`:
the decider judges how much capability the request needs, the request goes
to the cheapest model in your pool that clears that bar, with that model's
own credential, and the response names the model and the reasons. Nothing
leaves your machine except the request to the model you chose. Your models.
Your call. Your rules.

## How the choice is made

The decider never picks a model by name. It judges the task; your
configuration judges the models.

1. **The request is measured**, not judged: tokens, turns, tools, images,
   JSON output.
2. **The decider answers one typed question**: how much capability does
   answering this correctly need (0 trivial … 4 frontier), and does it
   involve code, math or rare knowledge. It sees an excerpt, never your keys,
   never your model names; text inside the request cannot steer it.
3. **The answer sets the lowest rung** of a three-rung ladder — `small`,
   `mid`, `frontier` — on which every profile in the pool sits (`tier`, from
   your declaration or the shipped catalog). `code` keeps only code-capable
   profiles; `math`, `rare` and `tools` lift an easy request to `mid`; a very
   long request goes to the top.
4. **Inside the rung the cheapest eligible profile wins**, priced for this
   request. An empty rung escalates, never descends. Doubt — low confidence,
   a decider error, a timeout — lands on your default, and says so.
5. **Every response discloses the choice**: `X-Router-*` headers and a
   `router` object with the signals, the reasons, the candidates with their
   estimated cost, usage and what the provider reported.

With a pool of GLM 5.3 Flash (`small`, subscription) and Opus 5.5
(`frontier`, $4/$20 per million tokens):

| request | the decider says | lowest rung | answered by | because |
|---|---|---|---|---|
| rename `foo` to `bar` | difficulty 1, `code` | small | GLM 5.3 Flash | the low rung suffices; GLM is the small, code-capable profile |
| find the race condition in this scheduler | difficulty 3 | frontier | Opus 5.5 | from 3 up only the top rung; GLM is not there |
| summarise this contract | difficulty 2 | mid | Opus 5.5 | the mid rung is empty: escalate, never descend |
| what is 17 % of 2,340 € | difficulty 1, `math` | mid | Opus 5.5 | `math` lifts an easy request to `mid`; empty, so up |

Add GLM 5.2 (`mid`) to the pool and the last two rows go to it instead. The
levers are yours — `tier` and `price` per profile, the pool, the default, a
cost ceiling — and `delegation-router decide --json` prints the reasons for
any prompt without dispatching it. `delegation-router eval` measures a
decider against the rules-only baseline on a golden set of yours.

## Quick start

```sh
./install.sh                      # commands, runners, Claude/Codex profiles, the guard
delegation-config show            # the personal configuration the installer created
```

Add a `router` block to `~/.config/delegation-kit/config.json`: the decider
first, then the profiles it governs (names that already exist in the file):

```json
"router": {
  "decider": {"kind": "llm", "profile": "deepseek-flash"},
  "pool": ["deepseek-flash", "qwen3.8-max", "sonnet-clerk"],
  "default": "qwen3.8-max"
}
```

```sh
delegation-router check           # the decider, then the pool with tiers and prices; no network
delegation-router serve           # http://127.0.0.1:4141/v1, loopback only
curl -s 127.0.0.1:4141/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"auto","messages":[{"role":"user","content":"Rename foo to bar in utils.py"}]}'
```

Any OpenAI SDK works with `base_url="http://127.0.0.1:4141/v1"`. Naming a
pool profile as `model` skips the decider and still discloses. The
[router page](docs/router.md) has every field, the policy, the deciders,
the error codes and the evaluation harness.

## How it works inside

- **One description per model.** The personal configuration holds a
  profile for each model you can call: HTTP adapters (`openai-compatible`,
  `deepseek-api`, `token-plan-openai`) and native CLIs (`codex`,
  `claude-code`, `claude-zai`, `kimi-code-cli`, `grok-build-cli`, `agy`).
  Each native CLI has a runner that enforces its sandbox, identity check and
  limits; the router reaches those profiles through the kit's own
  dispatcher, which is how Claude models join a pool although Anthropic
  exposes no chat-completions endpoint. A shipped catalog supplies tier,
  price and context for known models; your declarations win.
- **The installer also puts the same profiles in front of Claude Code and
  Codex** — six Claude subagents, five Codex profiles, the skills for a lead
  — together with a guard that nothing dispatches, retries, falls back or
  reviews without the user asking. The router follows the same rule: starting
  `serve` and sending `auto` is the user's choice, and the router never
  leaves the pool.
- **The patch trust boundary.** Text adapters return patches and never write
  to a worktree; `delegation-patch-verify` checks a patch against the shipped
  policy before the lead applies and tests it.
- **`doctor.sh`** reports what is installed, which runtimes are reachable
  and, first in its router section, which decider governs which pool;
  `--ping` runs a live round-trip.

## Current release: 0.27.0

Version 0.27.0 adds `delegation-router`: a `router` block names the decider
and the profiles it governs; `check` and `decide` are read-only; `serve`
routes `"model": "auto"` through a deterministic prefilter, the decider and
the `tiered-v1` policy, forwards — HTTP profiles with their own key, native
profiles through the kit's dispatcher — streams through and discloses the
choice. Five deciders (`llm`, `sage`, `jev`, `dipylon`, `classifier`), a cost
ceiling, opt-in receipts without prompt content, a model catalog and an
offline `eval` come with it. One configuration schema (`init` writes
`schema_version: 2`, a file that says `1` is read identically); the pre-0.24
migration, the advisory routing page and the adapting guide are gone; the
compatibility page keeps only the current snapshot. Explicit per-dispatch
authorization, sandboxes, model identity checks and the patch trust boundary
are unchanged. See [`CHANGELOG.md`](./CHANGELOG.md) for the full history.

## Documentation

- [The router: decider, pool, policy, disclosure, eval](docs/router.md)
- [Personal configuration, adapters, adding a model, upgrading](docs/user-configuration.md)
- [External executors: adapters and their limits](docs/external-executors.md)
- [Compatibility and release verification](docs/compatibility.md)

## Testing

```sh
./run-tests.sh
npm test
```

The suites use isolated fixtures and fake providers. They do not authorize
or prove live provider behavior; live probes are recorded per release in
the compatibility page.

## npm package

`npx delegation-kit` runs the installer from a verified release checkout.
The npm package is an installer wrapper, not a second runtime.

## License

MIT. See [LICENSE](LICENSE).
