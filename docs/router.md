# Model router

You choose a decision model — one of your cheap profiles, Levanto Sage,
TypeSafe Jev, your own Dipylon, a local classifier — and `delegation-router`
lets it govern the models you already pay for: for each request, the decider
judges how much capability the task needs, and the request goes to the
cheapest profile in your pool that clears that bar, with that profile's own
credential. It runs on your machine, listens on loopback only, and tells you
which model answered and why. Nothing leaves your machine except the request
to the model you chose.

Your models. Your call. Your rules: you name the decider, the pool and the
default; the router selects only inside that pool, discloses the chosen model
in every response, and never retries, falls back, or widens the pool.

## Three commands

```sh
delegation-router check [--json]                  # the router block, resolved; no network
delegation-router decide --prompt-file F [--json] # one recommendation; never dispatches it
delegation-router serve [--listen 127.0.0.1:4141] # OpenAI-compatible endpoint on loopback
```

`check` and `decide` are read-only discovery in the sense of the
[user-directed guard](../claude/CLAUDE.delegation.md): `decide` recommends a
profile and stops. If the decider is an LLM, `decide` makes that one call to
it, with its own key, and no other. Dispatching the recommended profile is a
separate `delegation-run` that the user has to ask for.

`serve` is the user's choice: starting it, and sending a request with
`"model": "auto"` to it, is the user directing the router to choose inside
the pool. Every response names the profile and the model that answered.

## Configuration

The router is a `router` block in the personal configuration: the decider
first, then the profiles it governs. Without a block the router is off and
`check` says so.

```json
{
  "schema_version": 2,
  "review_policy": "optional",
  "profiles": {
    "flash":   {"adapter": "deepseek-api", "model": "deepseek-flash", "roles": ["clerk"],
                "credential_env": "DEEPSEEK_API_KEY"},
    "qwen":    {"adapter": "token-plan-openai", "model": "qwen3.8-max", "roles": ["builder"],
                "credential_env": "QWEN_TOKEN_PLAN_API_KEY",
                "tier": "mid", "price": {"in": 1.6, "out": 6.4}},
    "sol":     {"adapter": "openai-compatible", "model": "gpt-6.1-sol", "roles": ["judgement"],
                "base_url": "https://api.openai.com/v1", "credential_env": "OPENAI_API_KEY"}
  },
  "router": {
    "decider": {"kind": "llm", "profile": "flash", "input": "excerpt", "timeout": 3},
    "pool": ["flash", "qwen", "sol"],
    "default": "qwen",
    "listen": "127.0.0.1:4141",
    "max_cost_usd": 1.0,
    "receipts": false,
    "allow_origins": [],
    "mode": "route"
  }
}
```

| field | meaning |
|---|---|
| `listen` | loopback `host:port` only (`127.0.0.1`, `localhost`, `[::1]`); default `127.0.0.1:4141` |
| `pool` | profile ids the router may choose from: any adapter. HTTP profiles (`openai-compatible`, `deepseek-api`, `token-plan-openai`) are called directly; native profiles (`codex`, `claude-code`, `claude-zai`, `kimi-code-cli`, `grok-build-cli`, `agy`) are bridged through `delegation-run`, see below |
| `default` | the pool profile used when the decision is undecidable; must be in the pool |
| `decider` | **required** — the decision model. `kind`: `llm`, `sage`, `jev`, `dipylon`, `classifier` or `none`. For `llm`, `profile` is an HTTP profile called with its own key (default: the pool default). For the service deciders, `url` (HTTPS, or loopback HTTP; required for `dipylon` and `classifier`), `credential_env` (the variable holding that service's key), `model` (Jev only) and `price` (`{in, out}` per million tokens, to price the decision) override the defaults listed under *Deciders*. `input` is `excerpt` (default) or `full`; `timeout` seconds 1–600 |
| `max_cost_usd` | pre-dispatch ceiling on the estimated cost of one request; a request whose chosen profile exceeds it is refused, never downgraded |
| `receipts` | when true, one JSONL line per request in `$DELEGATION_DATA_HOME/router/receipts.jsonl` (mode 600); decision, profile, usage, cost, latency — never prompt content. `uninstall.sh` keeps the file as `$DELEGATION_DATA_HOME.router-receipts.jsonl.bak` and `install.sh` restores it, like the key files |
| `allow_origins` | exact browser origins allowed to call the server (`https://app.example`, or `http://localhost:5173`); empty by default, so a web page cannot spend your keys. A listed origin gets the CORS preflight answered and `Access-Control-Allow-Origin` plus the exposed `X-Router-*` headers on every response; any other `Origin` is refused |
| `mode` | `route` (default) or `shadow`: decide and disclose, but dispatch the default |

Profiles may declare routing metadata — `tier` (`small`, `mid`, `frontier`),
`code` (bool), `price` (`{"in", "out"}` in USD per million tokens), `context`
(tokens), `json_mode` (bool). Anything not declared is read from the shipped
[`config/catalog.json`](../config/catalog.json), by model name; `check`
reports where each value came from (`metadata_source`). A profile with no
tier from either source can only be the default; a profile with no price is
ranked last within its tier. The catalog's numbers are a dated snapshot
(`catalog_version`), not a price list you should trust blindly: declare the
price on the profile when it matters.

### Native profiles in the pool

A profile on a native adapter has no chat-completions endpoint, so the
router answers through the kit's own dispatcher: the conversation is written
to a prompt file (a single user turn verbatim; otherwise a `[system]` /
`[user]` / `[assistant]` transcript), `delegation-run --profile <id> --lane
<role>` runs it in an empty temporary workdir, and the answer file comes back
as one chat completion. The role is the first read-only one the profile
declares and its adapter supports (`clerk`, `scout`, `reviewer`, `judgement`,
`senior`, `policy-annotation`, the review roles), a build role only when
nothing else is declared; `check` and the `router.delegation_run.lane` field
say which. Everything the dispatcher enforces stays in force: the profile's
`timeout`, the identity check (a mismatch is exit 70 there, so here it is
`502 provider-identity-mismatch` rather than a disclosed delivery), OAuth
locks (a second concurrent Kimi or Grok request is `429
provider-rate-limited`), sandboxes. The dispatcher's receipt (`review_policy`,
`review_status`, `status`) is relayed under `router.delegation_run`.

Limits that follow from the transport: no tools, images or JSON output mode
(the prefilter keeps native profiles out of such requests); a stream request
gets the whole answer as one event followed by the router chunk; a native
CLI reports no usage, so `cost_usd` is `null` unless its runner metrics carry
a provider cost. This is how Claude models enter the pool — through the
`claude-code` or `claude-zai` adapter — since Anthropic exposes no
chat-completions endpoint. Gemini and OpenAI do, and enter as
`openai-compatible` profiles.

## How a request is routed

1. **Features**, deterministic: estimated tokens, turns, tools, images,
   `max_tokens`, JSON output requested.
2. **Prefilter**, deterministic: a pool profile is blocked when its adapter is
   not routable, it declares no tier (unless it is the default), its context
   is too small for the request, or its estimated cost is above the ceiling.
   A request that asks for JSON output (`response_format`) blocks profiles
   declared without JSON mode. The decider is skipped when no profile other
   than the default is eligible, or when a decision could change nothing:
   the default is already the cheapest eligible profile *and* no eligible
   profile sits in a higher tier.
3. **Decider**: the `llm` decider sends an excerpt of the request — the head
   of the system prompt and the last user turn, trimmed, never images — to the
   decider profile inside a `DATA` block with the prompt in
   [`config/router-prompt.v1.md`](../config/router-prompt.v1.md), and reads
   one JSON object back: `difficulty` 0–4 and tags `code`, `math`, `rare`.
   The service deciders ask the same question in their own vocabulary (see
   *Deciders*). `long` (≥ 20k tokens) and `tools` are set deterministically.
   Anything outside the schema, an HTTP error, a timeout, or a missing key
   makes the decision *undecidable*: the default is used, the warning is
   disclosed, no retry happens. Text inside the request cannot steer the
   route: the decider never sees it as instructions and cannot name a model.
4. **Policy `tiered-v1`**: no usable signal or confidence below 0.55 →
   default. Difficulty ≥ 3 (0.75 of the scale), `long`, or a `p_needs_strong`
   ≥ 0.7 → frontier tier; difficulty < 1.5 without `math`, `rare` or `tools`
   → small; otherwise mid. `math`, `rare` and `tools` raise the floor to mid;
   `code` never raises the tier — it narrows the choice to code-capable
   profiles. Inside the tier the cheapest eligible profile wins
   (`price.in × est_tokens + price.out × max_tokens`, 1024 when unset). An
   empty tier escalates upward, never downward; an empty frontier falls to the
   default. Reasoning effort is `high` for difficulty ≥ 0.9 of the scale
   (a floor: a profile declared `xhigh` or `max` keeps it), `low` for an
   easy request on the small tier, else the profile's own — on the adapters
   that take a per-request setting (`deepseek-api`, `token-plan-openai`);
   elsewhere no effort is disclosed and the profile's own applies.
5. **Forward**: one request to the chosen profile's endpoint with that
   profile's key — never a key from the caller, never a header copied from
   the caller. The `router` object in the request body is dropped; `model` is
   rewritten to the profile's model; `stream_options.include_usage` is set
   when streaming. The profile's `timeout` bounds the whole exchange, as in
   `delegation-run` (504 `timeout`, retryable); without it a non-stream
   answer is waited for however long it takes, and a stream is cut only after
   30 seconds without an event. Connecting is bounded at 20 seconds either
   way. No retry.
6. **Disclosure**: see below.

`delegation-router decide --decider none` runs steps 1, 2 and 4 with no
network and always lands on the default: that is the baseline `eval`
measures deciders against.

### Where the rungs come from

A third party places the models. [Artificial Analysis](https://artificialanalysis.ai/)
publishes an Intelligence Index (0–100, a composite of public evaluations)
with coding and math sub-indexes and list prices for a few hundred models and
their reasoning settings; Epoch AI's Capabilities Index is the cross-check
where it covers a model. The kit turns the index into the three rungs with
one published rule, `index-bands-v1`: **frontier** within 8 points of the
best model of the day, **mid** within 20, **small** below. On the board of
2026-10-15 the best is Opus 5.5 at 57.6, so frontier is ≥ 49.6 (Opus 5.5,
Sonnet 5.5 56.0, Fable 5.1 53.4, GPT-6 Astra 52.7, GPT-6.1 Sol 51.8, Opus 5
50.8, Fable 5 49.6), mid ≥ 37.6 (GPT-5.6 Sol 47.0, Grok 4.7 46.4, Qwen3.8
Max 45.4, Grok 4.6 44.2, Kimi K3 43.6, Haiku 5.5 43.4, GPT-5.6 Terra 42.1,
GLM 5.3 Flash 41.8, Gemini 3.8 Flash 40.9, DeepSeek V4.1 Flash 39.5, GPT-5.5
38.4, Sonnet 5 38.2) and small below (GPT-5.6 Luna 37.3, GLM 5.2 33.7,
Gemini 3.1 Pro Preview 29.7, MiniMax M3 29.2, Mistral Large 3 9.3). The
bands are a choice, recorded in the catalog with the date; the decision's
`reasons` and `tier_source` say which placement was used.

Every catalog row carries its evidence — source, measured name, index per
reasoning setting, date — or `null` when a model was placed by hand because
the board does not list it. A profile that declares `effort` is placed at
the index of that setting when it was measured (Opus 5.5 at `medium` is 51,
still frontier); a profile's own `tier` wins over everything.

Two ways to a current ladder, neither automatic:

- **The shipped catalog**, `config/catalog.json`, refreshed before each
  release with the data of that day.
- **Your own refresh**: `delegation-router catalog refresh` makes one request
  to the Artificial Analysis API with your key and writes
  `$DELEGATION_DATA_HOME/config/catalog.local.json`, which takes precedence
  while it is at least as recent as the shipped file (`catalog show` says
  which is in effect). The key goes in the variable `AA_API_KEY` or in
  `$DELEGATION_DATA_HOME/config/artificial-analysis.env` as
  `AA_API_KEY=<key>` with mode 600, beside the other key files; a free
  account at artificialanalysis.ai issues one. The uninstaller keeps both
  the key and the local catalog beside the data home and the installer
  restores them. Attribution: the data is Artificial Analysis's.

`refresh` matches a catalog model to the board by the board's own slug
(`claude-opus-5-5`, `-xhigh`, `-medium`, …), else by the measured name
through the row's `aa_name` alias (`deepseek-flash` → "DeepSeek V4.1 Flash"),
and never by a partial match. Models the board does not list keep their hand
placement and are named by `refresh` (today: Haiku 4.5); a profile for a model outside the catalog has no rung and can
only be the default, unless you declare one. A model id that differs from
the catalog's only in case or punctuation (`GLM-5.3-Flash`, `claude.opus.5.5`)
is matched by the measured name. The index measures general capability on
public benchmarks, not your tasks: `eval` on your golden set is the local
proof, and the catalog is where the ladder starts, not where it ends.

### Why this model and not that one

The rule is Sage's: *the cheapest model that will get it right*. The decider
answers how much capability the request needs; the policy turns that into
the lowest rung of a three-rung ladder (`small`, `mid`, `frontier`) and the
specialties that narrow it; inside the rung the cheapest eligible profile
wins, for this request's estimated tokens. So with Opus 5.5 and GPT-6 Astra
both declared `frontier`, a hard request goes to Opus while Opus is eligible,
because Opus is the cheaper frontier model — Astra is chosen only when Opus
is blocked (context, cost ceiling, JSON mode) or when you put Astra alone on
the top rung and Opus on `mid`. The levers are the ones you declare: `tier`
and `price` on each profile, the pool, the default, the ceiling. Every
decision carries its `reasons`, including the candidates of the chosen rung
with their estimated cost, so `decide --json` and the `router` object answer
the question for each request.

Three deliberate departures from the Sage recipe: the recipe names one
model per rung, the kit ranks the rung by price so a pool can hold several;
the kit adds a confidence floor (below 0.55 the default is used); and
`math`, `rare` and `tools` raise an easy request to `mid`, where the recipe
only sends `code` to a code model and `long` to the frontier.

## Deciders

Every decider answers the same question — how much capability does this
request need, and does it involve code, math or rare knowledge — and reports
it as signals the policy reads: a 0–4 difficulty (expectation, distribution,
confidence), a "needs a strong model" probability, tag probabilities. The
excerpt is all any of them sees. Each is called with its own credential,
never a profile's, and prices its decision from `price`.

| kind | service | default `url` | default `credential_env` | asks | default `price` |
|---|---|---|---|---|---|
| `llm` | one of your HTTP profiles | — | the profile's | difficulty 0–4 + tags, one JSON object | the profile's |
| `sage` | Levanto Sage, `POST /decide/batch` | `https://sage.levanto.ai` | `SAGE_API_KEY` | a `scale` 0–4 and a `tags` question in one batch; the policy's confidence is the mass of the distribution in the tier band the expectation lands in, Sage's own `confidence` is disclosed beside it. Observed 2026-10-15: `levanto-sage-v1.4`, 0.8–2.0 s, ~$0.00003 per decision, ~$0.0012 when its reasoning fires on a hard prompt | $0.05 in / $10 out per M |
| `jev` | TypeSafe Jev (System One API) | `https://api.typesafe.ai/v1/systemone` | `TYPESAFE_API_KEY` | a 5-level `score`, a `noul` for "needs a frontier model", `noul`s for code and rare; `model` default `jev-latest`. Jev is weak on numbers, so a request with arithmetic-looking numbers (an operator, a percent, a currency, a decimal — not a line number or `LIMIT 1`) is never routed below mid. Observed 2026-10-15: `jev-1.13.0`, ~250 ms, ~$0.00002 per decision | $0.042 in per M |
| `dipylon` | your own Dipylon service, `POST /decide` | required | none | one `yesno`, "does this need a strong model?"; a selective-use verdict other than `retain` halves the confidence; a 503 (model loading) is undecidable | none |
| `classifier` | any local classifier behind `POST {"text"}` | required | none | reads `difficulty` (0..1) or NVIDIA's `prompt_complexity_score`, `p_needs_strong`, `tags`, `confidence`, and `task_type_1` naming code | none |
| `none` | — | — | — | nothing: always the default; the baseline `eval` measures against | — |

The Sage and Jev URLs can point at a proxy of your own; the request shape is
the service's. Jev through OpenRouter is not wired in this release: its
`/api/alpha/decisions` shape was not verified. Reaching any of these is the
user's choice, made in the configuration; `check` shows which service and
which variable without touching either.

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

`outcomes` is what each pool profile did on that prompt when *you* ran it:
whether the answer was right and what it cost. The harness never dispatches
a pool profile; it asks the decider once per prompt and paraphrase and looks
the chosen profile up. It reports accuracy, cost (outcomes plus decisions),
optimal-selection ratio, robustness (same tier on prompt and paraphrases),
undecidable rate, decision latency p50/p95, the same for the rules-only
baseline, and a deferral curve (the frontier cut swept 0.1–0.9 without new
decider calls). `gate.json` says whether the decider clears the bar —
accuracy ≥ baseline − 2 pp, cost ≤ 0.8× baseline, optimal selection ≥ 0.40,
robustness ≥ 0.85, p95 ≤ 300 ms (1.2 s for Dipylon, 1.5 s for `llm`),
undecidable ≤ 15 %, decision cost ≤ 10 % of the saving. The bar is advisory:
nothing in `serve` reads it.

## What a response carries

Headers on every response, success or failure where a choice was made:
`X-Router-Profile`, `X-Router-Model`, `X-Router-Tier`, `X-Router-Effort`,
`X-Router-Decider` (`id/version`), `X-Router-Policy`, `X-Router-Difficulty`,
`X-Router-Confidence`, `X-Router-Undecidable`, `X-Router-Latency-Ms`,
`X-Router-Mode`, and `X-Router-Model-Mismatch: 1` when the provider named a
model other than the profile's (or a configured alias).

A `router` object next to `choices`:

```json
"router": {
  "version": "1", "mode": "route",
  "decider": {"id": "llm", "version": "deepseek-flash+3f2a9c1d", "input": "excerpt", "reason": "routine rename"},
  "policy": {"id": "tiered-v1", "version": "2026-10-13"},
  "signals": {"difficulty": 1, "scale": [0, 4], "tags": {"code": 1.0, "math": 0.0, "long": 0.0, "rare": 0.0, "tools": 0.0},
              "p_needs_strong": null, "confidence": 0.8},
  "chosen": {"profile": "flash", "model": "deepseek-flash", "tier": "small", "reasoning_effort": "low"},
  "default": "qwen", "undecidable": false,
  "reasons": ["difficulty 0.25", "tag code 1.00", "code → cheapest code-capable profile at tier ≥ small"],
  "blocked": [], "warnings": [],
  "features": {"est_tokens": 310, "turns": 1, "tools": false, "images": false},
  "decision_latency_ms": 412, "decision_cost_usd": 0.00009, "catalog_version": "2026-10-13",
  "usage": {"prompt_tokens": 300, "completion_tokens": 20}, "cost_usd": 0.000114,
  "provider_reported_model": "deepseek-flash", "mismatch": false,
  "latency_ms": 1830, "upstream_status": 200
}
```

When streaming, the headers come first, the provider's events pass through
unchanged, and one last chunk with `"choices": []` carries `router` before
`data: [DONE]`. If the provider's stream was cut, closed before `[DONE]`, or
sent an event over 64 KiB, that chunk also carries
`"error": {"code": "stream-interrupted" | "stream-limit" | "stream-idle" | "timeout"}`
and `upstream_status` is 502.

A mismatch is disclosed, not fatal: in a gateway the caller sees it in the
response, unlike a single `delegation-run`, which exits 70. The profile's
`aliases` accept the reported name in both.

## Refusals and provider errors

Errors are `{"error": {"code", "retryable", "profile"?, ...}}` with
`X-Router-Error`. These never reach a provider:

| status | code | when |
|---|---|---|
| 404 | `unknown-model` | `model` is neither `auto` nor a pool profile id |
| 403 | `browser-denied` | an `Origin` header not in `allow_origins` |
| 400 | `cost-ceiling` | the chosen profile's estimate is above `max_cost_usd` or `X-Router-Max-Cost-USD` (`estimated_usd`, `ceiling_usd` included) |
| 400 | `invalid-cost-ceiling` | the header is not a number in (0, 1000] |
| 400 | `invalid-json`, `invalid-request` | not a JSON object with a `messages` list |
| 411 / 413 | `length-required`, `size-limit` | no `Content-Length`, or above 4 MiB |
| 401 | `provider-key-missing` | the chosen profile declares a credential the environment and the key files do not hold |
| 429 | `busy` | more than 16 requests in flight |

Provider failures keep their meaning and lose their payload: 401/403 →
`401 provider-key-rejected`; 429 → `429 provider-rate-limited` (retryable,
`Retry-After` passed through); 5xx → `502 provider-unavailable` (retryable);
any other 4xx → `provider-rejected-request` with the provider's message
truncated to 500 characters and key-shaped tokens redacted. A non-stream
response over 4 MiB is `502 upstream-too-large`.

The server prints one line when it starts and nothing afterwards: no request
log, no error log, no header, no key. Receipts are the only record and are
opt-in.

## Using it

```sh
delegation-router check
delegation-router serve
# another shell:
curl -si 127.0.0.1:4141/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"auto","messages":[{"role":"user","content":"Rename `foo` to `bar` in this function: ..."}]}'
curl -s 127.0.0.1:4141/v1/models        # the pool, plus "auto"
curl -s 127.0.0.1:4141/v1/health
```

Any OpenAI SDK works with `base_url="http://127.0.0.1:4141/v1"` and any API
key (the router ignores it; each profile uses its own). Naming a pool profile
as `model` forwards to it without a decider and still discloses; the context
and cost-ceiling rules apply to it too, only the tier rule does not.

`doctor.sh` has a "Model router" section: absent is optional, configured is
reported with its pool, default and decider, and `check` warnings are listed.

## Out of scope, on purpose

No public instance, no access tokens, no multi-tenant limits. No automatic
retry or fallback. No decision cache. No importer for a particular
evaluation corpus: the golden-set format is the contract. `mode: "shadow"`
exists so a decider can be observed before it is trusted.
