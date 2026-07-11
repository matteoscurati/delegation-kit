# Delegation lane discipline (installed by delegation-kit)

Usage-aware routing for driving coding work across models from Claude Code. A
resident **lead** owns the work and enters the expensive **judgement** model only
in short bursts; a cheap **executor** does the volume; a **senior** lane handles
taste, security, and escalation. This file is the always-loaded policy; the
`model-routing` skill carries the decision procedure and `model-routing.md` carries
the scored table.

> **Adapt this to your setup.** The model names below (`opus`/`sonnet`/`fable` on
> Claude; the reference numbers) are the author's. Swap them for your own tiers —
> see `ADAPTING.md`. The *structure* (lead / executor / senior / judgement,
> escalation, verification) is the transferable part.

## Lanes (reference mapping — author's models)

- **Lead = the capable-but-not-metered model** (author: **Opus 4.8 @ xhigh**).
  Owns requirements, decisions, integration, verification, the final response.
  Resident. Drop to medium effort for routine coordination.
- **Judgement = the most expensive model** (author: **Fable 5**). **Two touches per
  feature, max — a plan up front, a verdict/synthesis at the end.** Terse
  structured output. Never typing, never babysitting workers, never resident;
  reserve for architecture-moving decisions and the high-value calls where its
  gradient pays.
- **Executor + routine reviewer = the cheap-and-capable model** (author:
  **Sonnet 5**, via the `sonnet-*` profiles). Bulk implementation, migrations,
  tests, extraction, repo mapping, and the **default** diff/bug-review lane.
- **Senior review / taste / security = the high-taste model** (author: **Opus 4.8**,
  via `opus-reviewer`). Security-adjacent work routed here **directly**; user-facing
  taste (UI, copy, API design); escalation target for the executor.

## Named profiles (installed to `~/.claude/agents/`)

| profile | model / effort | use for |
|---|---|---|
| `sonnet-clerk` | sonnet / low | extraction, inventories, log/test summaries, transforms |
| `sonnet-scout` | sonnet / low | read-only repo mapping / exploration |
| `sonnet-builder` | sonnet / medium | bounded implementation with acceptance checks |
| `sonnet-reviewer` | sonnet / medium | routine correctness/bug review (the default) |
| `opus-reviewer` | opus / high | security / taste / material review + escalation |

## Rules

- **Effort:** executor low for well-specified mechanical work, medium when
  ambiguous or for routine review; senior medium by default, high for
  security/hard design, low for triage. Scale to ambiguity and blast radius, never
  to prestige.
- **Route review by content, not habit** — security/auth/payments/migrations/
  user-facing → senior; routine bug-hunting stays on the executor (often cheaper
  *and* higher-recall there). Size the reviewer to the work, not to the top of the
  table.
- **Escalation ladder:** executor miss/ambiguity → senior → judgement. Never retry
  the same failure on the executor twice — escalate. Security never delegates
  downward: it starts on the senior lane. (Standing rule: judge the output, not the
  price tag.)
- **Verification:** no executor diff ships unread. User-facing/security → senior
  reads it; pure mechanical → executor self-checks at low effort, senior
  spot-checks. The judgement model only re-checks what it produced or a
  multi-attempt synthesis — don't spend it verifying the executor.
- **No double fan-out:** in an orchestration/ultra mode, let the orchestrator fan
  out; don't add a second manual delegation layer. Workers return distilled
  evidence (changed paths, checks run, unresolved risks), not raw logs or essays.
- **Delegated output is unverified until you check it.** **Tie-breakers:**
  intelligence > taste > cost; and `cost` is per *task*, not per token.

## Reaching Codex from Claude (cross-provider bridge)

If a GPT/Codex model earns a lane, drive it from Claude. Two paths — pick by whether
you need it interactive/context-preserving or programmatic:

**Preferred for interactive work — the `codex@openai-codex` plugin** (install:
`/plugin marketplace add openai/codex-plugin-cc` then `/plugin install codex@openai-codex`):
- the `codex:codex-rescue` **agent** — agent-invokable; a bounded fire-and-forward to Codex.
- `/codex:review` · `/codex:adversarial-review` — read-only Codex review of the diff.
  **User-run slash commands** (you can't invoke them) — surface them to the user.
- **`/codex:transfer`** — hands the current Claude session off as a *resumable Codex
  thread*, the one path that actually **preserves conversation context** across the
  boundary. Also **user-run — suggest it, don't invoke it**; recommend it when the
  handoff needs the discussion so far, not just files.

**Programmatic / parallel / Workflow — raw `codex exec`.** Always pin **model +
effort**, don't inherit the Codex default:
- Ephemeral profile (pins both): `codex exec --ephemeral -p <profile> "<prompt>" </dev/null`.
- Inline override: `codex exec -m gpt-5.6-luna -c model_reasoning_effort=low -s read-only "<prompt>" </dev/null`
  (`-s workspace-write` to let it edit; always redirect stdin from `/dev/null`).
- Machine-readable return: add `--json` (JSONL events) or `-o <file>` (final message
  only) — **raw stdout is polluted with hook chatter**, so don't parse it directly.
- Inside Workflow scripts, wrap it in a thin `{model:'sonnet', effort:'low'}` agent
  that shells out and returns the cleaned output.

**Context (each `codex exec` starts fresh):** it shares your working tree but not
your conversation. Run it from the repo root (it auto-loads that repo's `AGENTS.md`)
and reference files **by path** rather than pasting; put the rest into a
self-contained prompt. If you need the discussion carried over, suggest the user run
`/codex:transfer` (it's user-run — you can't invoke it). Use the bridge for a cheap
high-volume lane or an independent second opinion from a different model family; treat
its output as **unverified until checked**.

---

## Reference numbers (author's, point-in-time — re-derive yours)

Not law — a worked example, measured on the author's work and plans as of
**2026-07**. Your models, plans, and numbers differ; see `ADAPTING.md`.

- **Efficiency (cost per finished task, measured/published):** the cheap lane is
  cheapest *per task* even when more verbose (author's cheapest reviewer ~$0.13–0.21/
  task vs the judgement model ~$3.12/task). Price spans ~10× across the table;
  tokens-per-task only ~1.5× — so verbosity doesn't reorder the ranking.
- **Routine review:** the cheap reviewer measured *cheaper and higher-recall* than
  the senior model on routine bug-hunting — hence "route review by content."
- **Judgement model billing:** the author's most expensive model bills as metered
  usage credits (real money per call) — the reason it is two-touches-only.
- **Subscription buckets:** on the author's Claude plan the executor drains a
  *separate* weekly bucket from the lead/judgement models — so pushing volume to
  the executor spares the shared pool. Check whether your plan meters the same way.
