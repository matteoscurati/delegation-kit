# Model routing for orchestrated coding

Delegation policy for driving coding work across several models — a strong one
plans and judges, cheaper ones execute. It answers one question: **which model
does which job.**

> ⚠️ **These are my numbers, not benchmarks.** The scores below are subjective
> and *point-in-time*: they reflect the cost **per finished task** on **my** work
> — measured on my own runs, cross-checked against published figures — and how
> each performs on it. Treat the *method* as transferable; re-derive the
> *numbers* for your own setup.
>
> **Using this in the [delegation kit](./README.md)?** The table below is a
> *worked reference* — the author's models and scores. See
> [`ADAPTING.md`](./ADAPTING.md) to remap the lanes to your own models, plans,
> and re-derived numbers.

## The table

Higher = better in every column. `cost` = **efficiency**: what one *finished
task* costs — the tokens a model burns to complete it × its price-per-token, not
the sticker $/token. A cheap-per-token model that rambles or retries can lose to
a pricier one that nails it in a single pass; pricing per task captures that.
`intelligence` = how hard a task I can hand it unsupervised. `taste` = UI/UX,
code quality, API design, copy.

| model         | cost | intelligence | taste |
|---------------|------|--------------|-------|
| gpt-5.5       | 4    | 8            | 5     |
| gpt-5.6-sol   | 4    | 9            | 8     |
| gpt-5.6-terra | 8    | 7            | 7     |
| gpt-5.6-luna  | 10   | 8            | 7     |
| glm-5.2†      | 10   | 6            | 6     |
| kimi-k3‡      | 8    | 8            | 8     |
| sonnet-5      | 7    | 5            | 7     |
| opus-4.8      | 5    | 7            | 8     |
| fable-5       | 1    | 9            | 9     |

† `glm-5.2` is not a general replacement despite its strong cost score. The
versioned 2026-07 worker evaluation qualifies only `clerk/high` and `scout/high`
(scout was measured at `max`, then pinned to `high` by owner decision after a
probe showed `max` bought no extra reasoning);
builder failed the blind taste floor and reviewer failed repeatability. Its
efficiency score reflects $0.026–$0.074 API-equivalent cost per qualified task,
not a promise about Coding Plan subscription economics. The public repository
ships the resulting gate, not the GLM evaluation harness or raw test artifacts.

‡ `kimi-k3` is provisional. Published coding data places it in the top two on
five of six supplied coding benchmarks; the valid subset of the local extended
run scored 97.1–99.4 mean with 91–95% full-pass rates. The versioned gate enables
`clerk`, `scout`, `builder`, and `senior` through the native Kimi Code CLI at
effort `max`. `reviewer` and `judgement` remain disabled. Quota exhaustion is a
temporary runtime failure (exit 75), not a quality downgrade.

`cost` above is **cost per completed task**, measured on my own review / impl / UI
runs (2026-07) and cross-checked against published cost-per-task figures
([Artificial Analysis](https://artificialanalysis.ai/articles/gpt-5-6-has-landed)).
Two things fall out of the numbers:

- **Verbosity doesn't reorder the column.** Price spans ~10× across this table;
  tokens-per-task only ~1.5×, so a chatty cheap model still wins. `gpt-5.6-luna`
  burns *more* tokens than Sol on a review yet costs ~⅕ as much per task
  (~$0.21 vs ~$1.04) and finds as many bugs — the cheap lane is genuinely cheapest
  *per task*, not just per token.
- **The pricey-per-token models earn their keep through judgement, not volume.**
  In the efficiency test `fable-5` (~$3.12/task) was the only model to catch every
  planted bug — including one both cheap incumbents missed — but at ~15× Luna's
  cost-per-task it is for verifying / synthesising, never bulk work. `opus-4.8` was
  *worse value than `sonnet-5`* on routine review (more cost, fewer bugs): reserve
  it for where its gradient is actually needed.

`gpt-5.5` is now Pareto-dominated by `gpt-5.6-sol` (equal cost-efficiency, lower
intelligence and taste) — kept as the battle-tested Codex default, but the
orchestrator rarely has reason to pick it over Sol. Across the `gpt-5.6-*` trio the
choice is per task: **Luna** for cheap high-volume execution/review, **Sol** for
the hardest work plus design/taste, **Terra** in between. All three cleared the row
bar below; **Terra is kept as a live option even though Luna Pareto-dominates it** —
let routing prune it, not the table.

`fable-5`'s `1` is the least-efficient-*and*-metered corner: since **2026-07-13** it
bills as usage credits at API rates ($10 / $50 per Mtok) on Pro/Max/Team, so every
call is real money on top of being the priciest per task — which is exactly why it's
reserved for high-value, low-volume judgement work below.
([Anthropic redeploy note](https://www.anthropic.com/news/redeploying-fable-5).)

## Reasoning effort per model

Effort levels each model exposes (Claude `effort:` / Codex `model_reasoning_effort`). Author's mapping — verify for your models; the deeper tiers live only on the frontier reasoners.

| model | supported effort |
|---|---|
| fable-5 | low · medium · high · xhigh · max |
| opus-4.8 | low · medium · high · xhigh |
| gpt-5.6-sol | low · medium · high |
| gpt-5.6-terra | low · medium · high |
| gpt-5.6-luna | low · medium · high |
| sonnet-5 | low · medium · high |
| gpt-5.5 | low · medium · high |
| glm-5.2 | high · max |
| kimi-k3 | max |

Kimi K3 is provisional: the 2026-07-16 run was truncated by provider quota, but
its valid subset and the supplied coding benchmarks support controlled use in
`clerk`, `scout`, `builder`, and `senior`. The installed
`delegation-kimi check --json` gate remains authoritative for the exact
backend/effort/lane combination.

## How to apply

- **These are defaults, not limits.** Judge the output, not the price tag: if a
  cheaper model's result doesn't meet the bar, redo it on a smarter one. Escalating
  costs less than shipping mediocre work.
- **When to delegate at all.** Default to handling work inline. Delegate the
  clear-spec, mechanical, or high-volume stuff (bulk implementation, migrations,
  data crunching) to the cheap-and-capable lane; reach for a multi-agent
  orchestration only on an explicit decision, never on autopilot.
- **A long or open-ended run is bottlenecked by unknowns, not intelligence.** The
  burn is the un-tuned prompt that drifts into a second and third attempt. Spend
  cheap tokens up front to surface the unknowns — a *blindspot pass* on unfamiliar
  ground, an interview one question at a time (prioritize answers that would change
  the architecture), a plan that leads with the decisions most likely to move
  (data models, interfaces, UX) before any code. Point at reference source instead
  of describing in prose. Keep an implementation-notes log of deviations during the
  run, and quiz yourself on the diff before merge. Each is cheaper than the re-run
  it prevents.
- **Delegated output is unverified until you check it.** Never ship or build on a
  delegated diff or finding without reading it or reproducing the claim — polished
  output is not correct output.
- **Cost is a tie-breaker only.** When axes conflict for anything that ships:
  intelligence > taste > cost.
- **`cost` is per *task*, not per token.** A model that burns more tokens at a
  lower price can still finish the job cheapest — measured, `gpt-5.6-luna` is the
  cheapest per completed task, verbosity included. Don't up-tier to "save tokens";
  price the task, not the token.
- **Size the reviewer to the work, not to the top of the table.** The reviewer
  only needs to be *at least as capable* as what it reviews. A diff the cheap lane
  wrote against a plan the strong model authored is reviewed by the *mid* model
  that already has the context — you don't spend your most expensive model on a
  review it isn't uniquely needed for. Reserve the top model as reviewer for when
  its gradient is actually required: high-level design/taste judgement, synthesis
  across multiple attempts, or independently checking something it produced.
- **The most expensive model does thinking, not typing.** `fable-5` is for two
  things only — planning, and orchestration/evaluation (judging attempts,
  reviewing, verifying, synthesizing). Never route code-writing to it unless you
  explicitly want to; the cost is excessive. It designs the plan and judges the
  result; it does not produce the diff.
- **Route security-adjacent work to the reasoning model directly.** Anthropic's
  classifier reroutes blocked prompts to Opus 4.8 anyway, so a security-shaped
  Fable call either reroutes or comes back thinner — start on Opus and skip the
  tax. (The broader "benign defensive work gets caught too" claim is unconfirmed
  by Anthropic; don't over-route on it.)
- **Anything user-facing** (UI, copy, API design) needs a high-taste model.
- **The cheap mid model has no first-class lane of its own** in this table — use
  it as the driver/wrapper (the thin agents that shell out to the cheap execution
  lane), not the model you hand a hard task to.

## The orchestrator pattern

The concrete shape most of this reduces to:

1. The strong model reads the codebase, writes the plan, breaks it into tasks.
2. Sub-agents on cheaper models execute each task.
3. The strong model reviews the merged result.

You pay premium prices for *judgement*, twice (plan + review), and plan-included
prices for the keystrokes in between.

## Before a new model earns a row

Prove it as an *orchestrated worker*, not a chat model: driven exactly as this
policy would route it in production. The bar — decide it before looking at any
output, so the result can't be rationalized after the fact:

1. **Harness compatibility** — reliable tool use, scoped edits without collateral
   changes, honored output contracts, several tasks in parallel. Any hard failure
   closes the gate regardless of chat-level intelligence.
2. **Unsupervised completion + judged quality ≥ the cheapest incumbent it would
   replace** — it finishes real tasks without hand-holding and is judged at least
   on par.
3. **Uncorrelated value** — in a review lane it catches ≥1 real bug that *both*
   incumbents miss. That's a candidate's only plausible edge: as a primary work
   lane the cheap incumbent already dominates on cost×intelligence.

Miss any one → no row. Measure it; don't inherit it.

The GLM-5.2 evaluation applied this rule per lane: it earned a constrained row
through clerk/scout, while builder and reviewer stayed explicitly unroutable.

Kimi K3 follows the same fail-closed method across operational and advisor lanes.
The provisional gate enables `clerk`, `scout`, `builder`, and `senior`; routing
stays with the incumbent for `reviewer` and `judgement`.
