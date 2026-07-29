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

The candidate/blocked `policy-annotation` lane may be invoked only with the
runner's explicit manifest-bound `--evaluation` mode for a pre-registered
qualification run. It remains absent from every operational route group;
evaluation neither promotes nor mutates a gate and does not qualify broad
architecture/trade-off judgement. The runner pins the exact configured model,
harness, and effort before provider dispatch (Kimi K3/native at `max`; Qwen
Token Plan at `xhigh`).

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

The snapshot observed through 2026-07-28 keeps historical rows only when no
current equivalent exists. Current exact variants use the latest verified source;
nearby variants, different harnesses, preliminary rows, and general-capability
benchmarks remain separately labeled context.

- [Artificial Analysis Coding Agent Index v1.2](https://artificialanalysis.ai/agents/coding-agents/)
  with its [July 2026 methodology](https://artificialanalysis.ai/methodology/coding-agents-benchmarking):
  retained only for historical variants that do not have a directly comparable
  current replacement.
- [Artificial Analysis Coding Agent Index v1.3](https://artificialanalysis.ai/agents/coding-agents/),
  observed 2026-07-28: 113 DeepSWE, 84 Terminal-Bench v2, and 124
  SWE-Atlas-QnA tasks with three attempts, now across 52 variants. It supplies
  current exact rows for Luna `low`, Terra `low`/`medium`, Sol `high`, Opus 5
  `xhigh`/`high`, Kimi K3 through Kimi Code CLI `max`, and Grok 4.5 through Grok
  Build `high`. The 2026-07-28 observation adds Claude Code Opus 5 at `xhigh`
  (index 67, joint first) and `max` (66), plus an Opus 4.8 `max` row re-scored
  under v1.3 (55 → 61, driven by repo Q&A 30% → 47%); the older v1.2 row is kept
  beside it rather than overwritten. Component scores come from the published
  per-benchmark chart because the tabular export is paywalled, and per-task
  token totals were left unrecorded for the new rows because the chart's token
  metric could not be reconciled with the previously recorded figures.
- [Arena Agent Arena](https://arena.ai/leaderboard/agent), dated 2026-07-27,
  with [causal-evaluation methodology](https://arena.ai/blog/agent-arena-methodology/):
  1,385,187 real-world sessions across 42 models covering confirmed success,
  user feedback, steerability, bash recovery, and tool hallucination. It still
  has no Opus 5 or Qwen3.8 row. Gemini 3.6 Flash now appears but on only 2,194
  sessions, so it is recorded as provisional. Estimates move between refreshes:
  Kimi K3's praise-vs-complaint effect fell 20.30% → 16.22% while its
  steerability rose 6.52% → 9.17% over six days, which is why the lane gate
  reads the current row rather than a remembered number.
- [Arena Code Arena WebDev](https://arena.ai/leaderboard/code/webdev?rankBy=labs),
  dated 2026-07-27: 489,150 human-preference votes across 19 labs for
  frontend/product output only. `claude-opus-5-max` enters first at 1725 but is
  preliminary on 686 votes; `claude-opus-5-high` (1670) and `claude-sonnet-5-high`
  (1545) are new and not preliminary. Kimi K3 and Gemini 3.6 Flash remain
  preliminary.
- [SWE-PRBench](https://arxiv.org/abs/2603.26130) and the continuously refreshed
  [Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark)
  as the required evidence family for reviewer lanes. As of 2026-07-28 neither
  yields a qualifying row: Martian's online tracker refreshed through July 28
  (3,990 scored PRs) but ranks review products — Greptile 60.8 F1, ChatGPT Codex
  Connector 59.3, Claude 55.3 (66.2% precision / 47.4% recall) — not a model at a
  named effort, and its offline repository has not published new results since
  2026-07-13. The `reviewer` lane therefore still shows zero rows.
- The dated [Terminal-Bench 2.0](https://www.tbench.ai/leaderboard/terminal-bench/2.0?verified=true)
  snapshot and [SWE-bench-Live](https://swe-bench-live.github.io/) remain
  secondary context. Current Grok comparisons use Terminal-Bench 2.1 through
  their explicitly named source/harness rather than overwriting those rows.
- [CursorBench 3.2](https://cursor.com/cursorbench), observed 2026-07-25 and
  re-verified unchanged on 2026-07-28, for ambiguous multi-file understanding,
  planning, implementation, bugfinding, and review tasks. Every row uses Cursor's
  harness; its Grok 4.5 row also carries the publisher's possible
  training-contamination warning. It supplies the first coding-context rows for
  Gemini 3.6 Flash `medium` and `high`, but not for the production `agy` harness.
  The 2026-07-28 pass filled previously uncaptured rows rather than changing any
  recorded value: Fable 5 `max` (70.5), Opus 5 `max` (70.0), and Opus 5 `xhigh`
  (69.3).
- [FrontierCode 1.1](https://cognition.com/frontiercode), with its
  [revision notes](https://cognition.com/blog/frontier-code-1.1), for
  maintainer-defined mergeability across correctness, tests, scope, style, and
  codebase conventions.
- [FrontierSWE](https://www.frontierswe.com/) and
  [Mercor APEX-SWE](https://www.mercor.com/apex/) as additional builder-quality
  context. Their published runners are not silently treated as production
  Claude→Z.AI, Grok Build, or Codex variants. FrontierSWE was re-verified
  unchanged on 2026-07-28; APEX-SWE gained an Opus 5 `max` row (54.7% ±5.5),
  statistically indistinguishable from Fable 5 `max` (54.8% ±6.0).
- [OpenBench](https://github.com/minghinmatthewlam/openbench), plus its
  [Kimi K3](https://github.com/minghinmatthewlam/openbench/blob/main/docs/releases/2026-07-20-kimi-k3/index.html)
  and [GPT-5.6](https://github.com/minghinmatthewlam/openbench/blob/main/docs/releases/2026-07-21-gpt56/index.html)
  releases, as reproducible local-harness context. Kimi was not run through Kimi
  Code CLI, and the Codex GPT-5.6 Sol row used `medium`, not the production
  reviewer/judge `high` effort.
- [OpenBench's Grok 4.5 release](https://github.com/minghinmatthewlam/openbench/blob/main/docs/releases/2026-07-20-grok45/index.html)
  and the current [Code Arena WebDev leaderboard](https://arena.ai/leaderboard/code/webdev?rankBy=labs)
  as contextual support for Grok's builder and frontend-builder promotion.
- Epoch's [Capabilities Index](https://epoch.ai/data/eci-documentation) and
  [Blueprint-Bench 2](https://andonlabs.com/evals/blueprint-bench-2) are retained
  as broad general/multimodal context, never as coding-lane qualification.
- Anthropic's [Claude Opus 5 launch](https://www.anthropic.com/news/claude-opus-5)
  and [migration documentation](https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5),
  observed 2026-07-25, for the pinned `claude-opus-5` identity, supported effort
  range, limits, pricing, and first-party qualitative review claims. These are
  contextual release evidence, not an independent reviewer benchmark. Anthropic
  also documents that flagged cyber requests may fall back to Opus 4.8; the
  security gate exposes that provider-controlled exception explicitly.

### Local harness evaluation with OpenBench

OpenBench belongs to the local-evaluation layer, not to the broad external
leaderboard layer. The registered July releases add contextual Kimi K3,
GPT-5.6 Sol, and Grok 4.5 rows. Its useful controls include disposable workspaces,
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

The 2026-07-28 ZIP snapshot has SHA-256
`c8d42856b661b8d839b636c48766febc9bf56c9c0f1db68ad9bdf2b71e009164`
and contains 74 benchmark CSVs, 5,671 rows, and 5,617 normalized advisory
records. Epoch re-published the archive between July 25 and July 28: the hash
changed from `72a03e2fb8f7e24aba2fafdb08558100e6131b70d67370246dd1bf22daf36cff`
while the shape stayed identical. The recorded hash is descriptive provenance —
`delegation-epoch` prints the hash of whatever it downloads and no check
compares it against the snapshot, so a mismatch is a signal to re-read, not a
failure. New relevant families include FrontierCode, FrontierSWE, APEX Agents,
Blueprint-Bench 2, and Epoch Capabilities Index. Exact model-name records exist
for Fable 5, Opus 5, Sonnet 5, GLM-5.2, all three GPT-5.6 tiers, Grok 4.5, and
Kimi K3; Gemini 3.6 Flash and Qwen3.8 Max Preview have no exact model-name ZIP
record. Unknown harness or effort remains contextual, so the archive does not
qualify a production lane by itself.

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
