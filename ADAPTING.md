# Adapting the kit to your models and plans

The kit ships the author's concrete setup as a **worked reference**. The lane
*structure* transfers; the model names and numbers are point-in-time and personal.
Here's what to change and how.

## The roles (this is the transferable part)

| role | what it does | author's pick |
|---|---|---|
| **lead** | owns the work, integrates, verifies; enters judgement only in bursts | Opus 5 @ xhigh |
| **judgement** | plan + final verdict/synthesis; explicit, manual gate | Fable 5 or Sol high |
| **super-judgement** | independent dual verdict + cross-review for exceptional decisions | Fable 5 + Sol high |
| **executor** | bulk implementation, migrations, tests, extraction, repo mapping, **default review** | Sonnet 5 |
| **senior** | security (direct), user-facing taste, escalation target, material review | Opus 5 |
| **clerk / scout / builder** | cheap sub-lanes of the executor (extract / map / build) | Sonnet (Claude) · Luna+Terra (Codex) |

Pick one model per role from *your* table. A role can share a model with another
(the author uses Opus for both lead and senior). Fill empty roles with the nearest
tier you have.

## Where to change the model / effort

Five places — keep them in sync:

1. **Claude subagent profiles** — `agents/*.md` frontmatter:
   ```yaml
   model: sonnet      # -> your executor tier: sonnet | opus | fable
   effort: low        # low | medium | high | xhigh | max (per model; see model-routing.md)
   ```
2. **Codex profiles** — both files per profile must match:
   - `codex/agents/<name>.toml`: `model = "..."`, `model_reasoning_effort = "..."`
   - `codex/profiles/<name>.config.toml`: same `model` + `model_reasoning_effort`
3. **The central gate** — `config/routing-gates.json`: update exact profile,
   status, selection, evidence references, fallback, and any compound lane.
4. **The prose** — `claude/CLAUDE.delegation.md`, `codex/AGENTS.md`,
   `model-routing.md`: update the reference mapping and lane-evidence notes.
5. **Executable bridges and sync surfaces** — for an external model, keep its
   `bin/delegation-*`, `config/*-routing.json`, `skills/*-executor/SKILL.md`,
   installer, uninstaller, doctor, routing-gate drift test, README, plugin
   manifests, and `skills/orchestrate/*` in step. Grok 4.5 is the current worked
   example: only `builder` and `frontend-builder`, Grok Build CLI, effort `high`.

Then re-run `./install.sh`; it refreshes copied files and replaces the guarded
policy blocks while retaining backups. Uninstalling first is unnecessary.

## Refreshing evidence and qualifying lanes

Do not inherit a global 1–10 score. Start from
`config/model-evidence.json` and keep every model+harness+effort row exact:

- `delegation-evidence check` verifies schema and freshness;
- `delegation-evidence lane <lane>` shows relevant coverage without qualifying it;
- `delegation-route check` validates the operational decision graph;
- `delegation-route table` generates the internal table from the central gate;
- API cost per task is not subscription-bucket cost;
- WebDev preference applies only to frontend work;
- coding-agent results never substitute for reviewer precision/recall.
- put same-variant, lane-relevant rows in `exact_evidence_ids`; put neighboring
  efforts, different harnesses, or supporting domains in `context_evidence_ids`;
- never copy a legacy aggregate score without task count, repetitions, confidence,
  and limitations. Unknown sample metadata remains `null`.

To add a model, refresh current sources, add the exact variant, pre-commit a
lane-specific threshold against its incumbent, run a small local runtime/scope
smoke, then record the owner decision in the relevant fail-closed routing gate.
See `evaluation/README.md` for the complete workflow.

## Author-specific choices to reconsider

These are baked into the reference, not universal — decide for yourself:

- **"Never use Haiku"** and **Fable-as-metered-credits** are the author's plan
  realities. Yours differ.
- **Separate Sonnet-only weekly bucket** (Claude Max): the author exploits it by
  pushing volume to Sonnet. Check whether your plan meters the same way before
  relying on it.
- **Lead = Opus, not the top model**: because the author's top model (Fable) bills
  as real money per call. If your top model is plan-included, your lead choice may
  differ.
- **Fan-out caps** (`[agents] max_threads=3 / max_depth=1`) and the ephemeral
  `multi_agent=false` guard are conservative defaults — tune to your appetite.

## Minimal adaptation checklist

1. Map each role to one of your models (table above).
2. Edit `agents/*.md` + `codex/agents/*.toml` + `codex/profiles/*.config.toml`.
3. Refresh `config/model-evidence.json` and define lane-specific thresholds.
4. Update `config/routing-gates.json`; keep manual judgement explicit-only.
5. Run the local compatibility smoke and update only the relevant routing gate.
6. Run the gate and runner tests, then `./install.sh` and `./doctor.sh`.
