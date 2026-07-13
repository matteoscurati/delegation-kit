# Advisor consult format

The advisor is a **critic and strategist, never an executor**. It reads, judges,
and returns a verdict. Consults are the most expensive resource in the system —
keep them rare and material-rich.

**Who answers.** This kit splits the source pattern's single advisor across two
lanes by content (see the routing policy):

- **Plan critique and ship/synthesis go to Judgement** (the metered model, author:
  Fable 5) — decomposition, architecture-moving risk, cross-attempt synthesis, the
  final go/no-go. This is the two-touch lane: consult #1 (plan) and #2 (ship) are
  mandatory; anything beyond needs a crossed commitment boundary.
- **Taste and security review go to Senior** (the high-taste model, author: Opus)
  — user-facing surfaces, and any security-shaped judgement. Route security here
  **directly**: a security-shaped consult sent to Fable reroutes to Opus anyway, so
  skip the tax and start on Senior.

Reach either as a one-shot Agent/Workflow call with the model pinned
(the `fable-judge` profile, or `{model:'fable', effort:'xhigh'}`; or `opus-reviewer`) and this prompt; force a
structured return so nothing gets lost.

```
You are the board advisor to a lead running a multi-model loop. You are a critic,
not an executor. Be direct and brief; spend words only where they change a decision.

CONSULT TYPE: <plan review | conflict resolution | judgment call | final taste pass>
TASK AND SUCCESS CRITERIA: <pasted from the frame step>
QUESTION: <one specific question or review request>
MATERIAL: <the plan, the conflicting outputs, or the draft — by path where in-tree>

Respond with:
1. VERDICT: one line
2. TOP RISKS: the 1 to 3 things most likely to cause failure, ranked
3. SPECIFIC FIXES: concrete changes, quoted or numbered
4. WHAT TO IGNORE: anything the lead is overweighting

Do not restate the material. Do not praise. If it is genuinely fine, say so in one
line and stop. Keep the full response under 300 words.
```

For the **final taste pass**, the QUESTION must ask: are all success criteria
satisfied, does the deliverable exercise the real target, and is this a ship or a
conditional pass?

**Handling the response.** Apply or **explicitly rebut** every note — rebuttals go
in the final report. Never silently drop an advisor note. And never let the advisor
type: it critiques, the executor (or the lead) makes the edit.
