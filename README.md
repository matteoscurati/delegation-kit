# delegation-kit

Easy requests go to your cheap models, hard ones to your strong ones.

You choose a decider — one of your cheap models, Levanto Sage, TypeSafe Jev,
your own Dipylon, a local classifier — and the models it may pick from: API
keys, a Claude or Codex subscription, a local endpoint. `delegation-router
serve` is an OpenAI-compatible endpoint on your own machine. Send it
`"model": "auto"`: the decider rates how much capability the request needs,
the request goes to the cheapest of your models on the tier that rating
allows, with that model's own credential, and the response names the model
and the reasons. For each request the decider gets an excerpt (the whole
request with `input: full`) unless it runs on your machine, and the chosen
model gets the request.

## How the choice is made

The decider never picks a model by name. It judges the task; your
configuration judges the models.

1. **The request is measured**, not judged: tokens, turns, tools, images,
   JSON output.
2. **The decider answers one typed question**: how much capability does
   answering this correctly need (0 trivial … 4 frontier, half points
   allowed), and does it involve code, math or rare knowledge. It sees an
   excerpt, never your keys, never your model names; text inside the request
   cannot steer it.
3. **The rating becomes a minimum score** on the same public index that
   places the models: up to 1, none; at 2, the bottom of the mid band
   (37.6 today); from 3, the bottom of the frontier band (49.6); in between,
   in proportion (2.5 → 43.6). `math`, `rare` and `tools` raise it to the
   mid band, a very long request to the frontier band; `code` keeps only
   code-capable profiles.
4. **The cheapest profile that reaches it wins**, whatever its tier, priced
   for this request. When none does, the strongest eligible one answers and
   the response says so. Doubt — low confidence, a decider error, a timeout —
   lands on your default, and says so.
5. **Every response discloses the choice**: `X-Router-*` headers and a
   `router` object with the signals, the reasons, the candidates with their
   estimated cost, usage and what the provider reported.

With three models from the default install — GPT-5.6 Luna as `luna-clerk`
(`small`: Intelligence Index 37.3), DeepSeek Flash as `deepseek-flash`
(`mid`: 39.5) and Claude Opus 5.5 as `opus-reviewer` (`frontier`: 57.6, the
best model on the board):

| request | the decider says | minimum | answered by | because |
|---|---|---|---|---|
| rename `foo` to `bar` | 1, `code` | none | GPT-5.6 Luna | every model reaches it; Luna is the cheapest |
| summarise this contract | 2 | 37.6 | DeepSeek Flash | 39.5 reaches it, Luna's 37.3 does not; cheaper than Opus |
| what is 17 % of 2,340 € | 1, `math` | 37.6 | DeepSeek Flash | `math` raises an easy request to the mid band |
| why this Go worker pool deadlocks | 2.5, `code` | 43.6 | Claude Opus 5.5 | DeepSeek's 39.5 falls short; Opus is the only one above |
| find the race condition in this scheduler | 3, `code` | 49.6 | Claude Opus 5.5 | from 3 up only the frontier band |

Add GLM 5.3 Flash (41.8, $0.15/$0.50 per million) and the first three go to
GLM: it reaches both minimums and costs less than Luna and DeepSeek. Add
Kimi K3 (43.6) as well and the 2.5 request goes to Kimi instead of Opus.

Where the tiers come from: a third party, not the kit. The shipped catalog
places every model it knows from the Artificial Analysis Intelligence Index
through one published rule — frontier within 8 points of the best model of
the day, mid within 20, small below — and records the evidence and the date
beside each row; `delegation-router catalog show` prints it. That is how
the kit knows that GPT-5.6 Sol (47.0) is `mid`, not `frontier`, whatever
its name suggests, and that Mistral Large 3 (9.3) is `small`. With your own
Artificial Analysis key (`AA_API_KEY`, or
`~/.local/share/delegation-kit/config/artificial-analysis.env`),
`delegation-router catalog refresh` writes a current catalog on your machine
that takes precedence over the shipped one; without a key you get the catalog
the package shipped with, refreshed at every release. The levers are yours — `tier` and `price` per profile, the pool, the default, a
cost ceiling — and `delegation-router decide --json` prints the reasons for
any prompt without dispatching it. `delegation-router eval` measures a
decider against the rules-only baseline on a golden set of yours.

## Quick start

```sh
./install.sh                      # commands, runners, Claude/Codex profiles, the guard
delegation-config show            # the personal configuration the installer created
```

Add a `router` block to `~/.config/delegation-kit/config.json`: the decider
first, then the profiles it may pick from (names that already exist in the file):

```json
"router": {
  "decider": {"kind": "llm", "profile": "deepseek-flash"},
  "pool": ["luna-clerk", "deepseek-flash", "opus-reviewer"],
  "default": "deepseek-flash"
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
  and, first in its router section, which decider rates for which pool;
  `--ping` runs a live round-trip.

## Current release: 0.28.0

Version 0.28.0 changes how the router chooses. The rating becomes a minimum
score on the Artificial Analysis index, and the cheapest of your models that
reaches it answers, whatever its tier (`floor-v1`); before, the cheapest on
the rated tier answered, so a pricier small model beat a cheaper, stronger
mid one. The LLM decider rates in half points, and `decide --lane ROLE`
recommends only profiles that take the role of a task you are about to
delegate.

Version 0.27.2 moved the shipped Opus profiles and Claude Code agents to
Claude Opus 5.5, rewrites the README and router page in the words the
responses use (tier, decider), corrects what they said leaves your machine
and the routing example, and has the installer warn when its bin directory
is not on your PATH. 0.27.1 made `npx delegation-kit@X.Y.Z` install the
`delegation-kit--vX.Y.Z` tag.

Version 0.27.0 added `delegation-router`: a `router` block names the decider
and the profiles it may pick from; `check` and `decide` are read-only; `serve`
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
- [Personal configuration, keys and environment, adding a model, upgrading](docs/user-configuration.md)
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

`npx delegation-kit` clones the release tag of the package's own version,
verifies the checkout and runs its `./install.sh`; `--ref <tag-or-branch>`
installs another ref. The npm package is an installer wrapper, not a second
runtime.

## License

MIT. See [LICENSE](LICENSE).
