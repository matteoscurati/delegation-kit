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

Qwen3.8-Max carries an empty `exact_evidence_ids` array on every lane, including
the provisional `builder`. Its only recorded row is the contextual
`qwen-3.8-max-ga-launch` availability record, whose metrics live under
`launch.*` precisely so they can never satisfy a lane's `required_metrics`.
Builder was promoted by an explicit owner decision, not by evidence: leaving
preview, Token Plan availability, and a smoke response are runtime facts, not
capability measurements. Promotion to `qualified` still requires exact DeepSWE
and Terminal-Bench v2 rows at the production tuple.

The candidate/blocked `policy-annotation` lane may be invoked only with an
explicit manifest-bound `--evaluation` mode for a pre-registered qualification
run. It remains absent from every operational route group; evaluation neither
promotes nor mutates a gate and does not qualify broad architecture/trade-off
judgement. Dedicated runners pin the exact configured model, harness, and
highest supported effort before provider dispatch: Kimi K3/native at `max`,
Qwen Token Plan at `xhigh`, GLM-5.3/Claude-to-Z.AI at `max`, and Grok
4.5/Grok Build at `high`. The central gate also records blocked Fable, Opus, and
Sol policy-annotation candidates; those profiles still require their own frozen
transport harness and an allowlisted manifest before they may supply evidence.

Only qualification assets owned by delegation-kit belong in this directory.
Evaluation contracts, packets, results, or jury packs for a downstream project
must remain in that project's repository or a dedicated artifact registry.
`evaluation/dipylon-ai-jury-*/` is ignored deliberately; external packs must not
be installed, diagnosed, or allowlisted by this kit.

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

Normal GLM clerk, scout, and builder qualification is defined separately by the
[`glm-lane-qualification-v1`](./glm-lane-qualification-v1/README.md) contract.
Only its protocol is public here: downstream prompts, fixture repositories, raw
provider streams, and aggregates remain under ignored `eval/` until an owner
chooses to publish a minimal, reviewed result. The runner binds every attempt to
the exact model/backend/effort, source commit, worktree commit, and artifact
hashes without mutating the operational gates.

The snapshot observed through 2026-07-31 keeps historical rows only when no
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
- [Arena Agent Arena](https://arena.ai/leaderboard/agent), dated 2026-07-28,
  with [causal-evaluation methodology](https://arena.ai/blog/agent-arena-methodology/):
  1,412,751 real-world sessions across 44 models covering confirmed success,
  user feedback, steerability, bash recovery, and tool hallucination. The new
  source is contextual: it refreshes GLM-5.2 Max at 43,277 sessions, but neither
  that row nor a same-named Arena variant is a match for the Claude-to-Z.AI
  runtime. Estimates move between snapshots and do not update a gate.
- [Arena Code Arena WebDev](https://arena.ai/leaderboard/code/webdev?rankBy=labs),
  dated 2026-07-28 and observed 2026-07-31: 492,170 human-preference votes
  across 106 models for frontend/product output only. GLM-5.2 Max is recorded
  as contextual WebDev evidence (1588, interval 1579–1597, 5,865 votes); it cannot qualify
  general builder, reviewer, or judgement work.
- [SWE-PRBench](https://arxiv.org/abs/2603.26130) and the continuously refreshed
  [Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark)
  as the required evidence family for reviewer lanes. As of 2026-07-28 neither
  yields a qualifying row: Martian's online tracker refreshed through July 28
  (3,990 scored PRs) but ranks review products — Greptile 60.8 F1, ChatGPT Codex
  Connector 59.3, Claude 55.3 (66.2% precision / 47.4% recall) — not a model at a
  named effort, and its offline repository has not published new results since
  2026-07-13. The `reviewer` lane therefore still shows zero rows.
- [Terminal-Bench 2.1](https://www.tbench.ai/leaderboard/terminal-bench/2.1)
  is a distinct source from the retained 2.0 snapshot: it repaired 28 of 89
  tasks, and the contextual Grok 4.5/Cursor CLI `high` row records the final
  anti-cheat-adjusted 79.3% ±1.5%, not its 88.3% pre-judgement value. Forty
  of 445 trials were disqualified (−9.0 percentage points); the source's
  Cursor CLI harness and `high` effort remain explicit rather than being silently
  mapped to Grok Build. [SWE-bench-Live](https://swe-bench-live.github.io/) was
  also refreshed on 2026-07-31; its live report feed contained submissions
  through 2026-07-30. It remains provenance for an automatically updated
  multi-language and multi-OS task family, not an exact local result.
- [CursorBench 3.2](https://cursor.com/cursorbench), observed 2026-07-30, for ambiguous multi-file understanding,
  planning, implementation, bugfinding, and review tasks. Every row uses Cursor's
  harness; its Grok 4.5 row also carries the publisher's possible
  training-contamination warning. It supplies the first coding-context rows for
  Gemini 3.6 Flash `medium` and `high`, but not for the production `agy` harness.
  The pricing provenance now explicitly uses the publisher's per-task tokens and
  published input, cache-read, cache-write, and output rates; it changes no
  recorded CursorBench score.
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
- The 2026-07-31 OpenBench refresh records current reproducibility provenance,
  not a re-score: wrappers, effort, permissions, checker controls, raw results,
  and token/cost telemetry remain part of the result identity.
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
- [Z.ai's GLM-5.2 launch](https://z.ai/blog/glm-5.2), observed 2026-07-31, is
  first-party contextual release provenance for the pinned model identity,
  long-horizon coding positioning, and one-million-token context. It is not an
  independent benchmark, local compatibility proof, or lane qualification.
- [Z.ai's GLM-5.3 launch](https://z.ai/blog/glm-5.3), observed 2026-08-14, is
  first-party contextual provenance for Coding Plan availability, effort
mapping, and coding/agent/security claims. The exact local high/max comparison
selected high by its preregistered efficiency rule; no independent tracked
source had a GLM-5.3 row on that date.

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

Grok 4.6 replaces 4.5 only in the operational route. The 2026-08-12 snapshot
adds separate high-effort rows from CursorBench 3.2 (69.9%), FrontierCode 1.1
(48.0%), APEX-SWE (56.4% plus or minus 6.2), APEX Agents (57.5% plus or minus
3.5), and the preliminary WebDev board (1617.94 on 1,005 votes). Every row is
contextual because none uses the hardened `delegation-grok` tuple. xAI's launch
figures are recorded separately as first-party claims and never treated as an
independent qualification.

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

The 2026-07-31 ZIP snapshot has SHA-256
`fa42ce8e17bacd56885032891dfd1073894ba09c424bf540ab51d0469e9c2850`
and contains 75 benchmark CSVs, 5,984 rows, and 5,930 normalized advisory
records. Epoch re-published the archive since the 2026-07-28 record
(`c8d42856b661b8d839b636c48766febc9bf56c9c0f1db68ad9bdf2b71e009164`). The
recorded hash is descriptive provenance —
`delegation-epoch` prints the hash of whatever it downloads and no check
compares it against the snapshot, so a mismatch is a signal to re-read, not a
failure. New relevant families include FrontierCode, FrontierSWE, APEX Agents,
Blueprint-Bench 2, and Epoch Capabilities Index. Exact model-name records exist
for Fable 5, Opus 5, Sonnet 5, GLM-5.2, all three GPT-5.6 tiers, Grok 4.5, and
Kimi K3; GLM-5.3, Gemini 3.6 Flash, and Qwen3.8-Max have no exact model-name ZIP
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
