# Model router

`delegation-router` picks one profile out of a pool you declared, for each
request you send it, and tells you which one it picked. It runs on your
machine, listens on loopback only, and uses the keys the kit already holds.
Nothing leaves your machine except the request to the provider you chose.

Your models. Your call. Your rules: you declare the pool, the default and the
decider; the router selects only inside that pool, discloses the chosen model
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

The router is a `router` block in the personal configuration, which must
declare `"schema_version": 2`. Schema 1 files stay valid; without a block the
router is off and `check` says so.

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
    "listen": "127.0.0.1:4141",
    "pool": ["flash", "qwen", "sol"],
    "default": "qwen",
    "decider": {"kind": "llm", "profile": "flash", "input": "excerpt", "timeout": 3},
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
| `pool` | profile ids the router may choose from; HTTP adapters only (`openai-compatible`, `deepseek-api`, `token-plan-openai`) |
| `default` | the pool profile used when the decision is undecidable; must be in the pool |
| `decider` | `kind` `llm` (default) or `none`; for `llm`, `profile` is an HTTP profile called with its own key (default: the pool default), `input` is `excerpt` (default) or `full`, `timeout` seconds 1–600 (default 3) |
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

Claude models are not in the pool in this release: Anthropic has no
chat-completions endpoint, and the native `claude-code` adapter is not an
HTTP adapter. The same holds for the other native adapters (`codex`,
`claude-zai`, `kimi-code-cli`, `grok-build-cli`, `agy`). Gemini and OpenAI
expose chat-completions endpoints and enter the pool as `openai-compatible`
profiles.

## How a request is routed

1. **Features**, deterministic: estimated tokens, turns, tools, images,
   `max_tokens`, JSON output requested.
2. **Prefilter**, deterministic: a pool profile is blocked when its adapter is
   not routable, it declares no tier (unless it is the default), its context
   is too small for the request, or its estimated cost is above the ceiling.
   A request that asks for JSON output (`response_format`) blocks profiles
   declared without JSON mode. The decider is skipped when one profile or
   fewer is eligible, or when a decision could change nothing: the default is
   already the cheapest eligible profile *and* no eligible profile sits in a
   higher tier.
3. **Decider**: the `llm` decider sends an excerpt of the request — the head
   of the system prompt and the last user turn, trimmed, never images — to the
   decider profile inside a `DATA` block with the prompt in
   [`config/router-prompt.v1.md`](../config/router-prompt.v1.md), and reads
   one JSON object back: `difficulty` 0–4 and tags `code`, `math`, `rare`.
   `long` (≥ 20k tokens) and `tools` are set deterministically. Anything
   outside that schema, an HTTP error, a timeout, or a missing key makes the
   decision *undecidable*: the default is used, the warning is disclosed, no
   retry happens. Text inside the request cannot steer the route: the decider
   never sees it as instructions and cannot name a model.
4. **Policy `tiered-v1`**: no usable signal or confidence below 0.55 →
   default. Difficulty ≥ 3 (0.75 of the scale), `long`, or a `p_needs_strong`
   ≥ 0.7 → frontier tier; difficulty < 1.5 without `math`, `rare` or `tools`
   → small; otherwise mid. `math`, `rare` and `tools` raise the floor to mid;
   `code` never raises the tier — it narrows the choice to code-capable
   profiles. Inside the tier the cheapest eligible profile wins
   (`price.in × est_tokens + price.out × max_tokens`, 1024 when unset). An
   empty tier escalates upward, never downward; an empty frontier falls to the
   default. Reasoning effort is `high` for difficulty ≥ 0.9 of the scale,
   `low` for an easy request on the small tier, else the profile's own.
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
network and always lands on the default: that is the baseline the evaluation
harness of a later release will measure deciders against.

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
retry or fallback. No decision cache. Native profiles in the pool, the
`sage`, `jev`, `dipylon` and classifier deciders, and the offline evaluation
harness with a deferral curve are planned for later releases; `mode:
"shadow"` exists now so a decider can be observed before it is trusted.
