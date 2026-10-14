# delegation-kit

A decision model picks which of your models answers each request — and
tells you why.

You declare a pool of models you already pay for (API keys, a Claude or
Codex subscription, a local endpoint), a default, and a decider.
`delegation-router serve` is an OpenAI-compatible endpoint on your own
machine: send it `"model": "auto"` and it sends the request to the cheapest
model in your pool that will get it right, with that model's own credential,
and names the choice in every response. Nothing leaves your machine except
the request to the model you chose. Your models. Your call. Your rules.

## How the choice is made

1. **The request is measured**, not judged: tokens, turns, tools, images,
   JSON output.
2. **The decider answers one typed question**: how much capability does
   answering this correctly need (a 0–4 scale: trivial … frontier), and does
   it involve code, math or rare knowledge. The decider is one of your cheap
   profiles by default; it can also be Levanto Sage, TypeSafe Jev, your own
   Dipylon or a local classifier. It sees an excerpt, never your keys, and
   text inside the request cannot steer it.
3. **The answer sets the lowest rung** of a three-rung ladder — `small`,
   `mid`, `frontier` — and the specialties narrow it: `code` keeps only
   code-capable profiles, `math`/`rare`/`tools` lift an easy request to
   `mid`, a very long request goes to the top.
4. **Inside the rung the cheapest eligible profile wins**, priced for this
   request. An empty rung escalates, never descends. Doubt — low confidence,
   a decider error, a timeout — lands on your default, and says so.
5. **Every response discloses the choice**: `X-Router-*` headers and a
   `router` object with the signals, the reasons, the candidates with their
   estimated cost, usage and what the provider reported.

So why Opus 5.5 rather than GPT-6 Astra? Because you declared both
`frontier` and Opus is the cheaper frontier model; Astra is chosen when Opus
is blocked or when you put Astra alone on the top rung. The levers are
yours — `tier` and `price` per profile, the pool, the default, a cost
ceiling — and `delegation-router decide --json` prints the reasons for any
prompt without dispatching it. `delegation-router eval` measures a decider
against the rules-only baseline on a golden set of yours.

## Quick start

```sh
./install.sh                      # commands, runners, Claude/Codex profiles, the guard
delegation-config show            # the personal configuration the installer created
```

Add a `router` block to `~/.config/delegation-kit/config.json` (and set
`"schema_version": 2`) naming profiles that already exist there:

```json
"router": {
  "pool": ["deepseek-flash", "qwen3.8-max", "sonnet-clerk"],
  "default": "qwen3.8-max",
  "decider": {"kind": "llm", "profile": "deepseek-flash"}
}
```

```sh
delegation-router check           # the pool resolved, tiers and prices, no network
delegation-router serve           # http://127.0.0.1:4141/v1, loopback only
curl -s 127.0.0.1:4141/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"auto","messages":[{"role":"user","content":"Rename foo to bar in utils.py"}]}'
```

Any OpenAI SDK works with `base_url="http://127.0.0.1:4141/v1"`. Naming a
pool profile as `model` skips the decider and still discloses. The
[router page](docs/router.md) has every field, the policy, the deciders,
the error codes and the evaluation harness.

## What is in the box

- **Profiles and adapters** — the personal configuration describes each
  model once: HTTP adapters (`openai-compatible`, `deepseek-api`,
  `token-plan-openai`) and native CLIs (`codex`, `claude-code`,
  `claude-zai`, `kimi-code-cli`, `grok-build-cli`, `agy`), each with its
  sandbox, identity check and limits enforced by its own runner. Native
  profiles join the router pool through `delegation-run`; that is how
  Claude models get there, since Anthropic has no chat-completions endpoint.
  A shipped catalog supplies tier, price and context for known models;
  your declarations win.
- **Explicit delegation for Claude Code and Codex** — the same profiles,
  dispatched one at a time on request: `delegation-route` lists and validates
  choices without dispatching, `delegation-run` runs one profile once and
  writes a receipt with the model identity the provider reported and the
  review state. Six Claude subagents and five Codex profiles ship as presets,
  with skills for the lead and a guard that no dispatch, retry, fallback or
  review happens without the user asking for it. The router is the same
  rule: starting `serve` and sending `auto` is the user's choice, and the
  router never leaves the pool.
- **The patch trust boundary** — text adapters return patches, never
  write to a worktree; `delegation-patch-verify` checks a patch against the
  shipped policy before the lead applies and tests it.
- **`doctor.sh`** — what is installed, which runtimes are reachable, whether
  the router is configured; `--ping` runs a live round-trip.

## Current release: 0.27.0

Version 0.27.0 adds `delegation-router`: a schema 2 `router` block declares
the pool, the default and the decider; `check` and `decide` are read-only;
`serve` routes `"model": "auto"` through a deterministic prefilter, the
decider and the `tiered-v1` policy, forwards — HTTP profiles with their own
key, native profiles through `delegation-run` — streams through and
discloses the choice. Five deciders (`llm`, `sage`, `jev`, `dipylon`,
`classifier`), a cost ceiling, opt-in receipts without prompt content, a
model catalog and an offline `eval` come with it. The pre-0.24 migration,
the advisory routing page and the adapting guide are gone; the
compatibility page keeps only the current snapshot. Explicit per-dispatch
authorization, sandboxes, model identity checks and the patch trust boundary
are unchanged. See [`CHANGELOG.md`](./CHANGELOG.md) for the full history.

## Documentation

- [The router: pool, deciders, policy, disclosure, eval](docs/router.md)
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
