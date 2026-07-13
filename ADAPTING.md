# Adapting the kit to your models and plans

The kit ships the author's concrete setup as a **worked reference**. The lane
*structure* transfers; the model names and numbers are point-in-time and personal.
Here's what to change and how.

## The roles (this is the transferable part)

| role | what it does | author's pick |
|---|---|---|
| **lead** | owns the work, integrates, verifies; enters judgement only in bursts | Opus 4.8 @ xhigh |
| **judgement** | plan + final verdict/synthesis; expensive; two touches/feature | Fable 5 (via the `fable-judge` profile) |
| **executor** | bulk implementation, migrations, tests, extraction, repo mapping, **default review** | Sonnet 5 |
| **senior** | security (direct), user-facing taste, escalation target, material review | Opus 4.8 |
| **clerk / scout / builder** | cheap sub-lanes of the executor (extract / map / build) | Sonnet (Claude) · Luna+Terra (Codex) |

Pick one model per role from *your* table. A role can share a model with another
(the author uses Opus for both lead and senior). Fill empty roles with the nearest
tier you have.

## Where to change the model / effort

Four places — keep them in sync:

1. **Claude subagent profiles** — `agents/*.md` frontmatter:
   ```yaml
   model: sonnet      # -> your executor tier: sonnet | opus | fable
   effort: low        # low | medium | high | xhigh | max (per model; see model-routing.md)
   ```
2. **Codex profiles** — both files per profile must match:
   - `codex/agents/<name>.toml`: `model = "..."`, `model_reasoning_effort = "..."`
   - `codex/profiles/<name>.config.toml`: same `model` + `model_reasoning_effort`
3. **The prose** — `claude/CLAUDE.delegation.md`, `codex/AGENTS.md`,
   `model-routing.md`: update the "reference mapping" lines and the scored table.
4. **Other sync surfaces** — keep these in step too: `codex/config.snippet.toml`,
   `README.md`, `.claude-plugin/marketplace.json`, and `skills/orchestrate/*`.

Then re-run `./install.sh` (it refreshes copied files; run `./uninstall.sh` first
if you changed the prose blocks, since those are append-once).

## Re-deriving the numbers (`cost` / `intelligence` / `taste`)

Don't inherit the author's scores — they're "my numbers, not benchmarks." Use the
method in `model-routing.md`:

- **cost = efficiency (cost per finished task)**, not sticker $/token. Measure it:
  run the *same* task on each candidate, record tokens spent, multiply by its
  price-per-token (or plan-burn weight). A verbose-but-cheap model often still wins.
- **intelligence** = how hard a task you can hand it unsupervised. **taste** =
  UI/UX, code quality, API design, copy.
- **Before a model earns a lane**, apply the 3-gate test in `model-routing.md`
  ("Before a new model earns a row"): harness compatibility, unsupervised
  completion ≥ the cheapest incumbent, and uncorrelated value in review.

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
3. Re-score `model-routing.md` for your plans (or delete rows you don't use).
4. `./uninstall.sh && ./install.sh`.
