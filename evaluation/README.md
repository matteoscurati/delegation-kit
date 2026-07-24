# Evidence-backed model routing

The kit separates three facts that are easy to blur together:

1. **External capability evidence** — recent, broad benchmarks and live arenas.
2. **Local compatibility** — the exact runtime, harness, permissions, model, and
   effort work on this machine.
3. **Routing qualification** — an explicit owner decision stored in a versioned
   `config/*-routing.json` gate.

External evidence informs a decision but never edits a gate or qualifies a lane
automatically. A strong public score cannot prove that a local runner respects
scope, permissions, output contracts, or the pinned effort.

Operational decisions live in `config/routing-gates.json`. Inspect them with
`delegation-route`; `status` records confidence and `selection` records whether a
profile is default, fallback, explicit-only, or blocked. Judgement is manual-only,
and the Fable+Sol super-judgement pair never dispatches automatically.
The central file is authoritative: all external runners validate the complete
decision graph and read their dispatch status from it before checking runtime or
authentication. Their backend-specific JSON files retain transport and legacy
measurement details but cannot widen the central gate.

Qwen3.8 Max Preview is intentionally represented with empty exact/context
evidence arrays. Its Token Plan runtime is available for controlled local
evaluation, but availability, preview marketing, and a smoke response are not
capability evidence and cannot promote a lane.

## Versioned snapshot

[`config/model-evidence.json`](../config/model-evidence.json) records raw metrics,
not subjective 1–10 scores. Every row is an exact combination of model, harness,
and effort. Results from different variants are never silently merged.

The snapshot includes exact rows for the installed Codex profiles where the
source publishes them: Luna `low`, Terra `low`/`medium`, and Sol `high`. Missing
exact Claude-profile variants remain explicit evidence gaps; nearby `max` or
`xhigh` results are context, not substitutes.

Routing decisions therefore separate `exact_evidence_ids` from
`context_evidence_ids`. Exact means the same model, harness, and effort; it must
also be relevant to the lane. Nearby variants, different harnesses, and general
coding evidence for review/judgement are context and are shown separately in the
generated table.

The snapshot through 2026-07-24 is intentionally mixed-version: existing model
rows retain the dated source that produced them, while Grok 4.5 uses newly
observed sources. A newer source never silently rewrites an older row.

- [Artificial Analysis Coding Agent Index v1.2](https://artificialanalysis.ai/agents/coding-agents/)
  with its [July 2026 methodology](https://artificialanalysis.ai/methodology/coding-agents-benchmarking):
  retained for the existing non-Grok rows: DeepSWE, Terminal-Bench v2,
  SWE-Atlas-QnA, three repeats, cost/time/token data.
- [Arena Agent Arena](https://arena.ai/leaderboard/agent), dated 2026-07-19,
  with [causal-evaluation methodology](https://arena.ai/blog/agent-arena-methodology/):
  real-world confirmed success, feedback, steerability, bash recovery, and tool
  hallucination.
- [Arena Code Arena WebDev](https://arena.ai/leaderboard/code/webdev?rankBy=labs),
  dated 2026-07-19: human-preference evidence for frontend/product output only.
- [SWE-PRBench](https://arxiv.org/abs/2603.26130) and the continuously refreshed
  [Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark)
  as the required evidence family for reviewer lanes.
- The dated [Terminal-Bench 2.0](https://www.tbench.ai/leaderboard/terminal-bench/2.0?verified=true)
  snapshot and [SWE-bench-Live](https://swe-bench-live.github.io/) remain
  secondary context. Current Grok comparisons use Terminal-Bench 2.1 through
  their explicitly named source/harness rather than overwriting those rows.
- [OpenBench](https://github.com/minghinmatthewlam/openbench), observed
  2026-07-22, as a reproducible local framework for measuring the combined
  model+harness system on coding tasks. It is tracked for future evaluations,
  but its published results currently contain no Qwen3.8 Max Preview row and
  therefore add no exact model evidence to this snapshot.
- [Artificial Analysis Grok Build comparison](https://artificialanalysis.ai/agents/coding-agents/comparisons/codex-vs-grok-build),
  Coding Agent Index v1.3 observed 2026-07-24, for the exact Grok 4.5 + Grok
  Build + high builder row.
- [OpenBench's Grok 4.5 release](https://github.com/minghinmatthewlam/openbench/blob/main/docs/releases/2026-07-20-grok45/index.html)
  and the current [Code Arena WebDev leaderboard](https://arena.ai/leaderboard/code/webdev?rankBy=labs)
  as contextual support for Grok's builder and frontend-builder promotion.

### Local harness evaluation with OpenBench

OpenBench belongs to the local-evaluation layer, not to the broad external
leaderboard layer. Its useful controls include disposable workspaces,
checker-polarity validation against untouched and golden workspaces, a null
adapter, partial credit, repeated trials, confidence intervals, and
time/token/cost telemetry.

An OpenBench result is exact evidence only when the evaluated model, harness,
effort, permissions, and tool surface match the production route. Running a
model through `pi`, OpenCode, or another agentic wrapper measures that combined
system and must not qualify a different local runner. The current Qwen Token
Plan runner is read-only, while OpenBench coding tasks require workspace edits;
OpenBench can therefore inform a future agentic Qwen builder evaluation but
cannot promote any current Qwen lane.

For Grok 4.5, the July 20 OpenBench GrokBuild row is retained as contextual
builder evidence because its reported effort and full runner policy are not an
exact attestation of `delegation-grok`. The exact builder row comes from
Artificial Analysis; WebDev remains frontend-only context. Neither result
qualifies review, senior, judgement, or security work.

OpenBench results remain coding evidence. They do not substitute for
review-precision/recall evaluation and never qualify `reviewer`, `senior`,
`judgement`, or security-sensitive work. Before recording a future run, retain
the task pack and version, exact model and harness, effort and permissions,
trial count, checker scores, confidence, failures/timeouts, token accounting,
and raw-result provenance.

### Epoch AI ZIP advisory intake

[`bin/delegation-epoch`](../bin/delegation-epoch) reads only Epoch AI's public
[`benchmark_data.zip`](https://epoch.ai/data/benchmark_data.zip). It does not use
Airtable or the `epochai` package. The archive is downloaded into memory,
size/path/encoding/CSV structure is validated, and the raw ZIP and extracted
corpus are never persisted by the tool.

```sh
bin/delegation-epoch check
bin/delegation-epoch normalize --model gpt-5.6-sol --benchmark deepswe
bin/delegation-epoch evidence --model gpt-5.6-sol --benchmark deepswe
```

`normalize` preserves every non-empty benchmark-specific metric. `evidence`
maps only reviewed fields into this repository's lane metric names:
DeepSWE `Pass@1`, Terminal-Bench `Accuracy mean`, and WebDev Arena score plus
their available cost/error bounds. The output includes a stable archive hash,
dataset and row provenance, attribution, and license metadata.

An Epoch row is labeled `exact` only when that row names model, harness, and
effort. This is exact source identity, not automatic production-route evidence:
a `mini-swe-agent` result remains contextual for a `codex` profile. Missing or
unknown harness/effort is always labeled `contextual`. Review the generated JSON
before manually adding selected source/evidence objects to
`config/model-evidence.json`; the importer has no gate or snapshot mutation
path.

The 2026-07-24 ZIP contains twelve Grok 4.5 rows, all contextual: Blueprint
Bench 2, Chess Puzzles, two Epoch Capabilities Index entries, GPQA Diamond, OTIS
Mock AIME, ProofBench, SciCode, SimpleBench, SimpleQA Verified, Surface Evolver
Bench, and Vending-Bench 2. It contains no Grok 4.5 row for DeepSWE,
Terminal-Bench, WebDev Arena, or code review, so Epoch does not qualify either
promoted lane; it remains broad capability context only.

Epoch's own data is attributed under CC BY 4.0. External-project rows preserve
their source links and original licensing; the documented Apache-2.0 overrides
for Aider Polyglot and Terminal-Bench are recorded explicitly. Do not commit the
downloaded ZIP, extracted CSVs, or one-off normalized outputs.

Run:

```sh
bin/delegation-evidence check
bin/delegation-evidence sources
bin/delegation-evidence models
bin/delegation-evidence lane builder
bin/delegation-route check
bin/delegation-route table
tests/routing-gates.sh
tests/epoch-zip.sh
tests/glm-runner-diagnostics.sh
tests/gemini-runner-diagnostics.sh
tests/qwen-runner.sh
tests/grok-runner.sh
bin/delegation-evidence lane reviewer --json
```

`check` fails with exit 78 when the snapshot is older than the configured
freshness window. Refreshing means verifying the live source pages, recording a
new dated snapshot, and reviewing any routing decision affected by the change.

## Lane mapping

The mapping is evidence coverage, not an automatic score:

| lane | primary evidence | supporting evidence |
|---|---|---|
| clerk | SWE-Atlas-QnA | cost, tool reliability |
| scout | SWE-Atlas-QnA | steerability, time/task |
| builder | DeepSWE + Terminal-Bench | cost, token use |
| frontend-builder | Code Arena WebDev | DeepSWE, confirmed success |
| reviewer | review precision + recall | false-positive rate |
| senior | steerability + user outcomes | review evidence, WebDev taste |
| judgement | manual decision only | Agent Arena is supporting context |

WebDev Elo never promotes a general builder. Coding-agent scores never promote a
reviewer. No public benchmark auto-promotes judgement or security-sensitive work.

## Qualification workflow

1. Select the exact production variant: model, harness, effort, and permissions.
2. Inspect relevant coverage with `delegation-evidence lane <lane>`.
3. Pre-commit the incumbent, lane-specific threshold, and fallback.
4. Run only a small local compatibility smoke: runtime/auth, tool use, scoped
   writes, output contract, concurrency where relevant.
5. Record the owner decision in the routing gate, distinguishing `candidate`,
   `provisional`, `qualified`, `manual-qualified`, and `disabled`; record routing
   selection separately as default, fallback, explicit-only, or blocked.
6. Never preserve an aggregate local score without its task count, repetitions,
   and confidence. Old incomplete runs are labeled `legacy_local_result`; unknown
   sample metadata stays `null` and cannot be compared across lanes.
6. Keep the runner fail-closed on the exact lane/backend/effort tuple.

For a reviewer, missing SWE-PRBench/Martian precision and recall means missing
evidence, even when the same model is strong on DeepSWE or WebDev. For a local
bridge, missing runtime/auth means unavailable, even when external evidence is
strong.
