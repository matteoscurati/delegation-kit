# Model router

You choose a decider — one of your cheap profiles, Levanto Sage, TypeSafe
Jev, your own Dipylon, a local classifier — and `delegation-router` uses it
to pick, per request, which of your models answers. The decider rates how
much capability the task needs; the request goes to the cheapest profile in
your pool on the tier that rating allows, with that profile's own
credential; the response names the model and the reasons. It runs on your
machine and listens on loopback only. For each request the decider gets an
excerpt (the whole request with `input: full`) unless it runs on your
machine, and the chosen profile gets the request.

You name the decider, the pool and the default; the router selects only
inside that pool, discloses the chosen model in every response, and never
retries, falls back or widens the pool.

## Commands

```sh
delegation-router check [--json]                        # the decider and the pool, resolved, and what this machine can reach; no model call
delegation-router decide --prompt-file F [--lane ROLE] [--raw] [--json] # one recommendation; never dispatches it
delegation-router serve [--listen 127.0.0.1:4141]       # OpenAI-compatible endpoint on loopback
delegation-router catalog show|refresh [--shipped]      # where the tiers come from; refresh them
delegation-router eval --items F [--decider K] [--output DIR]  # measure a decider offline
```

`check`, `decide`, `catalog show` and `eval` never dispatch a pool profile.
`decide` makes exactly one call, to the decider, with the decider's own key;
`eval` makes one per prompt in the golden set; `catalog refresh` makes one
request to Artificial Analysis with your key. Dispatching the recommended
profile is a separate `delegation-run` the user has to ask for. `serve` is
the user's choice: starting it, and sending `"model": "auto"` to it, is the
user directing the router to choose inside the pool.

`decide --lane ROLE` is the same decision for a task you are about to
delegate: only the pool profiles that take that role — the check
`delegation-run` makes before it dispatches — are candidates, the others are
listed under `blocked`, and the recommendation carries the profile's
`capabilities` on that role (`text-patch`, `sandboxed-worktree`, …). A role
can lift the choice: if only a frontier profile judges, a judgement task goes
to it whatever the rating. When the decision would land on a default that
does not take the role, `decide` recommends nothing and says so; a role no
pool profile takes is an error.

## Configuration

A `router` block in the personal configuration: the decider first, then the
profiles it may pick from. Without the block the router is off and `check` says
so.

```json
{
  "schema_version": 2,
  "review_policy": "optional",
  "profiles": {
    "flash": {"adapter": "deepseek-api", "model": "deepseek-flash", "roles": ["clerk"],
              "credential_env": "DEEPSEEK_API_KEY"},
    "qwen":  {"adapter": "token-plan-openai", "model": "qwen3.8-max", "roles": ["builder"],
              "credential_env": "QWEN_TOKEN_PLAN_API_KEY"},
    "sol":   {"adapter": "openai-compatible", "model": "gpt-6.1-sol", "roles": ["judgement"],
              "base_url": "https://api.openai.com/v1", "credential_env": "OPENAI_API_KEY"}
  },
  "router": {
    "decider": {"kind": "llm", "profile": "flash"},
    "pool": ["flash", "qwen", "sol"],
    "default": "qwen"
  }
}
```

| field | meaning |
|---|---|
| `decider` | **required** — the model or service that rates each request. `kind`: `llm`, `sage`, `jev`, `dipylon`, `classifier` or `none`. For `llm`, `profile` is an HTTP profile called with its own key (default: the pool default). For a service, `url` (HTTPS, or loopback HTTP; required for `dipylon` and `classifier`), `credential_env`, `model` (Jev) and `price` (`{in, out}` per million tokens) override the defaults under *Deciders*. `input`: `excerpt` (default) or `full`. `timeout`: seconds 1–600 |
| `pool` | profile ids the router may choose from, on any adapter: HTTP profiles (`openai-compatible`, `deepseek-api`, `token-plan-openai`) are called directly, native profiles (`codex`, `claude-code`, `claude-zai`, `kimi-code-cli`, `grok-build-cli`, `agy`) through `delegation-run` |
| `default` | the pool profile used when the decision is undecidable |
| `listen` | loopback `host:port` only (`127.0.0.1`, `localhost`, `[::1]`); default `127.0.0.1:4141` |
| `max_cost_usd` | ceiling on the estimated cost of one request: every profile whose estimate is above it is set aside (listed under `blocked`); if that leaves nothing on the needed tier or above, the default answers and says so; if the profile the request lands on is over the ceiling too, the request is refused with the estimate and the ceiling |
| `receipts` | one JSONL line per request in `$DELEGATION_DATA_HOME/router/receipts.jsonl` (mode 600) — decision, profile, usage, cost, latency, never prompt content. Kept by `uninstall.sh` and restored by `install.sh`, like the key files |
| `allow_origins` | exact browser origins allowed to call the server (`https://app.example`, `http://localhost:5173`); empty by default. A listed origin gets the CORS preflight and the `X-Router-*` headers exposed; any other `Origin` is refused |
| `mode` | `route` (default) or `shadow`: decide and disclose, but dispatch the default |

Profiles may declare their own routing metadata — `tier` (`small`, `mid`,
`frontier`), `code`, `price` (`{"in", "out"}` USD per million tokens),
`context` (tokens), `json_mode` — and the declaration wins. Anything not
declared comes from the catalog (below); `check` reports the source of each
profile's tier (`tier_source`). A profile with no tier from either source can
only be the default; a profile with no price is ranked last within its tier.

## How a request is routed

1. **Features**, deterministic: estimated tokens, turns, tools, images,
   `max_tokens`, JSON output requested, arithmetic-looking numbers.
2. **Prefilter**, deterministic. A pool profile this machine cannot
   dispatch is set aside first — an HTTP profile without its key (the named
   variable or the kit's key file), a native profile whose runner's `check
   --json` selects no backend, `codex` or `claude` missing from PATH — and
   listed under `blocked` as `unreachable: <why>`; `serve` checks once when it
   starts, `decide` and `check` every time, with no model call (a login that
   lapses later still fails at dispatch, with its own error). Then a profile
   is blocked when it declares
   no tier (unless it is the default), its context is too small for the
   request, its estimated cost is above the ceiling, or the request wants
   JSON output and the profile is declared without JSON mode; a native
   profile is blocked when the request carries tools, images or JSON mode.
   The decider is skipped when no profile other than the default is
   eligible, or when a decision could change nothing — the default is
   already the cheapest eligible profile and no eligible profile sits on a
   higher score.
3. **Decider**. It sees an excerpt — the head of the system prompt and the
   last user turn, trimmed, never images — and answers one question: how
   much capability does this need (0 trivial … 4 frontier), and does it
   involve code, math or rare knowledge. `long` (≥ 20k tokens) and `tools`
   are set deterministically. Anything outside the schema, an HTTP error, a
   timeout or a missing key is *undecidable*: the default is used, the
   warning is disclosed, nothing is retried. Text inside the request cannot
   steer the route: the decider never sees it as instructions and cannot
   name a model.
4. **Policy `floor-v1`**. No usable signal or confidence below 0.55 →
   default. Otherwise the rating becomes a **minimum score** on the
   Artificial Analysis index: up to 1, none; at 2, the bottom of the mid
   band; from 3, the bottom of the frontier band; in between, in proportion
   (with today's bands, 1.5 → 18.8, 2 → 37.6, 2.5 → 43.6, 3 → 49.6). A
   yes/no "needs a strong model" maps to the frontier band from 0.7, to the
   mid band from 0.3. `math`, `rare` and `tools` raise the minimum to the mid
   band, `long` to the frontier band; `code` never raises it, it narrows the
   choice to code-capable profiles (any profile when no code-capable one
   reaches it). Every eligible profile whose score reaches the minimum is a
   candidate, whatever its tier, and the cheapest wins
   (`price.in × est_tokens + price.out × max_tokens`, 1024 when unset). When
   none reaches it, the strongest eligible profile answers and the reasons
   say so. A profile's score is the index measured at the reasoning setting
   it runs at; a model placed by hand, or a profile that declares `tier`,
   counts as the bottom of its band. Reasoning effort is `high` for
   difficulty ≥ 3.6 (a floor: a profile declared `xhigh` or `max` keeps it)
   and `low` for an easy request on a small-tier profile, only on the
   adapters that take a per-request setting (`deepseek-api`,
   `token-plan-openai`). Until 0.28.0 the policy was `tiered-v1`: the rating
   picked one tier and the cheapest profile *on that tier* won, so a pricier
   small model beat a cheaper, stronger mid one.
5. **Forward**: one request to the chosen profile's endpoint with that
   profile's key — never a key or a header from the caller. The `router`
   object in the request body is dropped, `model` is rewritten,
   `stream_options.include_usage` is set when streaming. The profile's
   `timeout` bounds the whole exchange (504 `timeout`); without it a
   non-stream answer is waited for however long it takes and a stream is cut
   only after 30 s without an event. Connecting is bounded at 20 s. No retry.
6. **Disclosure**, below.

### Why this model and not that one

The rule is Sage's: *the cheapest model that will get it right*. The decider
judges the task, never a model; your configuration judges the models. With
Opus 5.5 (57.6) and GPT-6 Astra (52.7) both above a hard request's minimum
(49.6), the request goes to Opus while Opus is eligible, because Opus is the
cheaper of the two; Astra answers when Opus is blocked (context, ceiling,
JSON mode) or when you leave Opus out. With GLM 5.3 Flash (41.8), Kimi K3
(43.6) and Qwen3.8 Max (45.4), a 2 goes to GLM (cheapest above 37.6), a 2.5
to Kimi (cheapest above 43.6), and Qwen answers only between 43.6 and 45.4
— it costs four times Kimi for 1.8 more points. The levers are yours —
`tier` and `price` per profile, the pool, the default, the ceiling — and
every decision carries its `reasons`, including the minimum, the chosen
profile's score and the candidates with their estimated cost, so `decide
--json` and the `router` object answer the question per request. `decide --raw` adds the decider's own answer under
`decider.raw`; a served response never carries it.

Three deliberate departures from the Sage recipe: the recipe names one
model per tier, the kit turns the rating into a minimum score and ranks
every model above it by price, so a pool can hold several per tier; the kit
adds the confidence floor; and `math`, `rare` and `tools` raise an easy
request to the mid band, where the recipe only sends `code` to a code model
and `long` to the frontier.

## Where the tiers come from

A third party places the models. [Artificial Analysis](https://artificialanalysis.ai/)
publishes an Intelligence Index (0–100, a composite of public evaluations)
with coding and math sub-indexes and list prices for a few hundred models
and their reasoning settings. The kit turns the index into the three tiers
with one published rule, `index-bands-v1`: **frontier** within 8 points of
the best model of the day, **mid** within 20, **small** below. The bands are
a choice, recorded in the catalog with the date; `delegation-router catalog
show` prints the rule, the board's best, and every model's tier with its
source. Every row carries its evidence — measured name, index per reasoning
setting, date — or `null` when the board does not list the model and it was
placed by hand. A profile that declares `effort` is placed at the index of
that setting when it was measured.

Two ways to current tiers, neither automatic:

- **The shipped catalog**, `config/catalog.json`, refreshed from the API
  before each release.
- **Your own refresh**: `delegation-router catalog refresh` makes one request
  to the Artificial Analysis API with your key and writes
  `$DELEGATION_DATA_HOME/config/catalog.local.json`, which takes precedence
  while it is at least as recent as the shipped file. The key goes in
  `AA_API_KEY` or in `$DELEGATION_DATA_HOME/config/artificial-analysis.env`
  as `AA_API_KEY=<key>` with mode 600; a free account at
  artificialanalysis.ai issues one. The uninstaller keeps the key and the
  local catalog beside the data home and the installer restores them. The
  data is Artificial Analysis's.

`refresh` matches a catalog model to the board by the board's own slug
(`claude-opus-5-5`, `-xhigh`, …), else by the measured name through the
row's `aa_name` alias, never by a partial match, and names the models it
could not place. A profile whose model id differs from the catalog's only in
case or punctuation is matched by the measured name. The index measures
general capability on public benchmarks, not your tasks: `eval` on your own
golden set is the local proof.

## Native profiles in the pool

A profile on a native adapter has no chat-completions endpoint, so the
router answers through the kit's dispatcher: the conversation becomes a
prompt file (a single user turn verbatim; otherwise a `[system]` / `[user]` /
`[assistant]` transcript), `delegation-run --profile <id> --lane <role>` runs
it in an empty temporary workdir, and the answer file comes back as one chat
completion. The role is the first read-only one the profile declares and its
adapter supports, a build role only when nothing else is declared; `check`
and `router.delegation_run.lane` say which. Everything the dispatcher
enforces stays in force — the profile's `timeout`, the identity check (a
mismatch is `502 provider-identity-mismatch`), OAuth locks (a second
concurrent Kimi or Grok request is `429 provider-rate-limited`), sandboxes —
and its receipt (`review_policy`, `review_status`, `status`) is relayed under
`router.delegation_run`. A stream request gets the whole answer as one event
followed by the router chunk; a native CLI that reports no usage leaves
`cost_usd` null. This is how Claude models join a pool, through
`claude-code` or `claude-zai`.

## Deciders

Every decider answers the same question and reports the same signals: a 0–4
difficulty (expectation, distribution, confidence), a "needs a strong model"
probability, tag probabilities. The excerpt is all any of them sees. Each is
called with its own credential, never a profile's, and prices its decision
from `price`; the per-decision cost is disclosed.

| kind | service | default `url` | default `credential_env` | asks |
|---|---|---|---|---|
| `llm` | one of your HTTP profiles | — | the profile's | one chat completion at `temperature 0` with [`config/router-prompt.v1.md`](../config/router-prompt.v1.md), the excerpt in a `DATA` block, one JSON object back (`difficulty`, `tags`, `reason`) in at most 120 tokens; DeepSeek with thinking disabled, Qwen at `minimal` effort. A cheap, fast profile is the one to pick |
| `sage` | Levanto Sage, `POST /decide/batch` | `https://sage.levanto.ai` | `SAGE_API_KEY` | a `scale` 0–4 and a `tags` question in one batch. The policy's confidence is the mass of the distribution in the tier's band; Sage's own `confidence` is disclosed beside it; a `null` answer is undecidable. Its fanout mode bills output tokens on long excerpts even with reasoning off, so watch the disclosed cost |
| `jev` | TypeSafe Jev, System One API | `https://api.typesafe.ai/v1/systemone` | `TYPESAFE_API_KEY` | a 5-level `score`, a `noul` for "needs a frontier model", `noul`s for code and rare; `model` default `jev-latest`. Jev is weak on numbers, so a request with arithmetic-looking numbers is never routed below `mid` |
| `dipylon` | your own Dipylon, `POST /decide` | required | none | one `yesno`, "does this need a strong model?"; `probability` is P(yes); a selective-use verdict other than `retain` halves the confidence; a 503 is undecidable |
| `classifier` | any local classifier behind `POST {"text"}` | required | none | reads `difficulty` (0..1) or NVIDIA's `prompt_complexity_score`, `p_needs_strong`, `tags`, `confidence`, and `task_type_1` naming code |
| `none` | — | — | — | nothing: always the default; the baseline `eval` measures against |

Default prices: Sage $0.05 in / $10 out per million tokens, Jev $0.042 in.
The Sage and Jev URLs can point at a proxy of your own; Jev through
OpenRouter is not wired (its shape was not verified). What each service
answered on real prompts, with latencies and costs, is in the
[compatibility page](compatibility.md).

## What a response carries

Headers on every response where a choice was made: `X-Router-Profile`,
`X-Router-Model`, `X-Router-Tier`, `X-Router-Effort`, `X-Router-Decider`
(`id/version`), `X-Router-Policy`, `X-Router-Difficulty`,
`X-Router-Confidence`, `X-Router-Undecidable`, `X-Router-Latency-Ms`,
`X-Router-Mode`, and `X-Router-Model-Mismatch: 1` when the provider named a
model other than the profile's or a configured alias.

A `router` object next to `choices`:

```json
"router": {
  "version": "1", "mode": "route",
  "decider": {"id": "llm", "version": "deepseek-flash+46002df5", "input": "excerpt", "reason": "routine rename"},
  "policy": {"id": "floor-v1", "version": "2026-10-19"},
  "signals": {"difficulty": 1, "scale": [0, 4], "tags": {"code": 1.0, "math": 0.0, "long": 0.0, "rare": 0.0, "tools": 0.0},
              "p_needs_strong": null, "confidence": 0.8},
  "chosen": {"profile": "flash", "model": "deepseek-flash", "tier": "mid", "tier_source": "artificialanalysis:2026-10-17", "score": 39.5, "reasoning_effort": null},
  "minimum_score": 0.0,
  "default": "qwen", "undecidable": false,
  "reasons": ["difficulty 0.25", "tag code 1.00", "minimum score 0.0 (mid from 37.6, frontier from 49.6)",
              "code → cheapest code-capable profile scoring ≥ 0.0", "flash scores 39.5, mid (artificialanalysis:2026-10-17)",
              "candidates: flash $0.0013, qwen $0.0068, sol $0.0109 → flash"],
  "blocked": [], "warnings": [],
  "features": {"est_tokens": 310, "turns": 1, "tools": false, "images": false},
  "decision_latency_ms": 1171, "decision_cost_usd": 0.00012, "catalog_version": "2026-10-17",
  "usage": {"prompt_tokens": 300, "completion_tokens": 20}, "cost_usd": 0.000114,
  "provider_reported_model": "deepseek-flash", "mismatch": false,
  "latency_ms": 1830, "upstream_status": 200
}
```

When streaming, the headers come first, the provider's events pass through
unchanged, and one last chunk with `"choices": []` carries `router` before
`data: [DONE]`; if the stream was cut, closed before `[DONE]`, idle over 30 s
or sent an event over 64 KiB, that chunk also carries `"error": {"code":
"stream-interrupted" | "stream-idle" | "stream-limit" | "timeout"}` and
`upstream_status` is 502. A mismatch is disclosed, not fatal — in a gateway
the caller is there to judge it — unlike a single `delegation-run`, which
exits 70.

## Refusals and provider errors

Errors are `{"error": {"code", "retryable", "profile"?, …}}` with
`X-Router-Error`. These never reach a provider:

| status | code | when |
|---|---|---|
| 404 | `unknown-model` | `model` is neither `auto` nor a pool profile id |
| 403 | `browser-denied` | an `Origin` header not in `allow_origins` |
| 400 | `cost-ceiling` | the chosen profile's estimate is above `max_cost_usd` or `X-Router-Max-Cost-USD` (with `estimated_usd`, `ceiling_usd`) |
| 400 | `invalid-cost-ceiling` | the header is not a number in (0, 1000] |
| 400 | `no-usable-candidate` | the named profile is blocked (context, JSON mode, no routable role) |
| 400 | `invalid-json`, `invalid-request` | not a JSON object with a `messages` list |
| 411 / 413 | `length-required`, `size-limit` | no `Content-Length`, or above 4 MiB |
| 401 | `provider-key-missing` | the chosen profile declares a credential nothing holds |
| 429 | `busy` | more than 16 requests in flight |

Provider failures keep their meaning and lose their payload: 401/403 → `401
provider-key-rejected`; 429 → `429 provider-rate-limited` (retryable,
`Retry-After` passed through); 5xx → `502 provider-unavailable` (retryable);
other 4xx → `provider-rejected-request` with the message truncated to 500
characters and key-shaped tokens redacted; a non-stream response over 4 MiB
is `502 upstream-too-large`. A refusal issued before the body was read closes
the connection. The server prints one line when it starts and nothing
afterwards: no request log, no error log, no header, no key. Receipts are the
only record and are opt-in.

## Measuring a decider

```sh
delegation-router eval --items ~/work/evals/router/items.jsonl --decider sage --output ~/work/evals/router/sage
```

The golden set lives outside the repository. Each JSONL line is one item:

```json
{"id": "easy-rename", "prompt": "Rename …", "paraphrases": ["Please rename …"],
 "outcomes": {"flash": {"correct": true, "cost_usd": 0.0011}, "qwen": {"correct": true, "cost_usd": 0.0093},
              "sol": {"correct": true, "cost_usd": 0.041}},
 "oracle": {"cheapest_correct": "flash"}}
```

`outcomes` is what each pool profile did on that prompt when *you* ran it.
The harness never dispatches a pool profile: it asks the decider once per
prompt and paraphrase and looks the chosen profile up. It reports accuracy,
cost (outcomes plus decisions), optimal-selection ratio, robustness (same
tier on prompt and paraphrases), undecidable rate, decision latency p50/p95,
the same for the rules-only baseline, and a deferral curve (the frontier cut
swept 0.1–0.9 without new decider calls). `gate.json` says whether the
decider clears an advisory bar — accuracy ≥ baseline − 2 pp, cost ≤ 0.8×
baseline, optimal selection ≥ 0.40, robustness ≥ 0.85, p95 ≤ 300 ms (1.2 s
Dipylon, 1.5 s `llm`), undecidable ≤ 15 %, decision cost ≤ 10 % of the
saving. Nothing in `serve` reads it.

## Using it

```sh
delegation-router check
delegation-router serve
# another shell:
curl -si 127.0.0.1:4141/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"auto","messages":[{"role":"user","content":"Rename foo to bar in utils.py"}]}'
curl -s 127.0.0.1:4141/v1/models        # the pool, plus "auto"
curl -s 127.0.0.1:4141/v1/health
```

Any OpenAI SDK works with `base_url="http://127.0.0.1:4141/v1"` and any API
key (the router ignores it; each profile uses its own). Naming a pool profile
as `model` forwards to it without a decider and still discloses; the context
and cost rules apply to it too. `doctor.sh` has a "Model router" section that
opens with the decider, names the catalog in effect and lists `check`'s
warnings.

## Out of scope, on purpose

No public instance, no access tokens, no multi-tenant limits. No automatic
retry or fallback. No decision cache. No importer for a particular
evaluation corpus: the golden-set format is the contract. `mode: "shadow"`
exists so a decider can be observed before it is trusted.
