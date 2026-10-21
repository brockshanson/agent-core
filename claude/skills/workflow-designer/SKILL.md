---
name: workflow-designer
description: >
  Design a token-conscious multi-agent Workflow script from a task description, baking in
  our house best-practices: scout-first, pipeline-by-default, model-tiering, cascade
  verification, and durable harvest. Use when the user wants to build/draft a new workflow,
  scale a task across agents, or asks "should this be a workflow?" Triggers: "design a
  workflow", "draft a workflow for", "make a workflow that", "orchestrate this", "fan this out".
---

# Workflow Designer

Turn a task into a **right-sized, cost-tiered** Workflow script. The goal is not "more agents" —
it's the cheapest structure that achieves the needed comprehensiveness/confidence/scale.

The cost model and gotchas below are **measured** — controlled probes, reading `agent-*.jsonl`
transcripts — not folklore. They hold on any repo using the same Claude Code Workflow harness. Dated
notes (`2026-06-13`) are provenance; the full write-up lives in the home repo at
`docs/mixed-model-orchestration-research.md`, but **this skill is self-contained — you do not need
that file to apply any of it.**

> **Picking this up in a fresh repo?** Everything here is portable. Two of the cost levers
> (`agentType: 'lean-worker'` / `'web-worker'`) lean on custom helper agents that a new repo won't
> have yet — **Appendix A** has their complete definitions; create them once (they register at the
> next session start). Until then, omit `agentType:` and rely on model-tiering alone — the
> tools-allowlist floor-trim is an *optimization*, not required for correctness. The repo-specific
> deployment dance (chezmoi symlinks) is called out where it appears; the portable path is always
> `Workflow({ scriptPath })`.

## Step 0 — Should this even be a workflow?

A workflow is justified ONLY by one of three needs:
- **Comprehensiveness** — decompose a big surface, cover in parallel.
- **Confidence** — independent perspectives + adversarial verification.
- **Scale** — work that won't fit one context (repo-wide sweeps, migrations, audits).

If none apply → use a single `Agent` call or just do it inline. Say so and stop.

## Step 1 — Scout inline FIRST

The single biggest token saver. Discover the work-list in the **main loop** (cheap: `rg`, `fd`,
`bd list`, `git diff --name-only`) and pass it to the workflow as `args`. Do NOT spend a
workflow to find what a grep would. (If discovery genuinely needs an agent — e.g. semantic
search — make it one cheap Haiku scout in phase 0.)

> **⚠ `args` arrives as a JSON STRING, not an object (measured 2026-06-13).** Even when you pass a
> proper object/array in the Workflow tool call, the script's global `args` is delivered as a string.
> A guard like `typeof args === 'object'` is silently false → your explicit scope is dropped and the
> script falls through to its default (a 2-file `hook-audit` smoke test became a 47-file audit,
> 122 agents, before it was killed). **Always coerce at the top:**
> `let A = args; if (typeof A === 'string') { try { A = JSON.parse(A) } catch { A = {} } }` — then read
> `A.x`, never raw `args`. Belt-and-suspenders: give fan-out workflows a hard file/agent ceiling so a
> scope-drop can't balloon (trust an explicit list; truncate+`log()` an unscoped discovery that overshoots).

## Step 2 — Pick the shape (pipeline by default)

- **`pipeline(items, stageA, stageB, …)`** — DEFAULT. No barrier; item A reaches stage 3 while
  B is still in stage 1. Use for find→verify, read→audit, search→fetch.
- **`parallel(thunks)`** — a BARRIER. Use ONLY when stage N needs ALL of stage N-1 at once
  (dedup across the full set, early-exit on zero, ranking-then-top-K).
- **Loop-until-dry** — unknown-size discovery; stop after K empty rounds.
- **Cascade** — cheap screen → escalate only uncertain/high-stakes items (see Step 4).

If you write `parallel → transform → parallel` and the middle transform has no cross-item
dependency, it should have been one `pipeline`. Rewrite it.

## Step 3 — Tier the models (WORKS — but use FULL model IDs, not short aliases)

> **✅ Measured 2026-06-13 (`model-probe`, 4 no-tool agents, ground-truth from `message.model`):**
> overrides ARE honored. `model: 'opus'` → `claude-opus-4-8` (then-current Opus); `model: 'claude-haiku-4-5'` →
> Haiku 4.5; no-override → inherits the session model. **The one trap:** the short alias
> `model: 'haiku'` silently resolved to **`claude-sonnet-4-6`** — the `ANTHROPIC_DEFAULT_HAIKU_MODEL` remap in settings.json.template, removed 2026-09-06 (the `'opus'` short alias worked;
> `'haiku'` did not). **So always pass the FULL model ID** — `claude-haiku-4-5`, `claude-sonnet-5`,
> `claude-opus-5` — never the bare `'haiku'` string. (One early workflow run used
> `'haiku'` everywhere and silently ran all-Sonnet because of this — a tiering *bug in the script*,
> not in the harness.) Always confirm by reading `agent-*.jsonl` `message.model` after a test run.
>
> **Cost model (also measured).** A no-op agent (zero tools) still carries **~20k inherited context
> per turn** — the CLAUDE.md/skills/AGENTS stack + framing (Opus-1M baselined ~64k). On top of that,
> **tool-results dominate** when agents read files / run `rg`/`fd` (the maiden run hit 80k–526k/agent,
> mostly file reads). Output (schema returns) is trivial. So total ≈ `agents × (≈20k/turn inheritance
> + tool-result tokens)`, and the **tier multiplies the per-token price**. Levers, in order of impact:
> (a) fewer agents, (b) less tool-result bloat — don't have every agent re-discover the same data;
> scout once and pass results as `args`, (c) fewer turns per agent, (d) cheaper tier per the table below.
>
> **✅ Second per-agent lever — a `tools:` allowlist trims the floor (measured 2026-06-13,
> `scoped-agent-floor-probe`, 3 no-tool agents all on Sonnet, ground-truth from `agent-*.jsonl`).**
> A custom agentType with a restricted `tools:` allowlist (`lean-worker`: `Read, Grep, Glob` —
> no Skill, no MCP, no Task, no shell) ran at **13.8k input tok** vs the default workflow-subagent's **19.0k**
> and Explore's **25.3k** — a **~5.2k tok/agent (~27%) cut**. Cause: with the Skill tool absent the
> `skill_listing` attachment (full ~30-skill catalog) **vanishes entirely**, and with MCP tools absent
> the `deferred_tools_delta` block (~100 MCP tool names) **vanishes entirely** — both were *absent*,
> not merely smaller, in the lean transcript. So the floor is NOT fixed per-agent: **scoping tools
> drops the skill+MCP injection wholesale.** Built-in agentTypes (Explore/general-purpose) do NOT get
> this — they carry the full catalog; the win requires an explicit allowlist. **Use `agentType:
> 'lean-worker'` for cheap mechanical fan-out (finders/classifiers/extractors)** — it stacks with
> `model:` tiering (price/token × floor size). Note custom agents only register at session start, so a
> newly-added `claude/agents/*.md` needs a restart before a workflow can reference it.

Verified findings (provenance: the home-repo research doc): strong-lead + cheap-workers
beats single-strong; worker model matters more than token budget; the verifier need NOT be
stronger than the generator (diversity suffices for correctness).

| Role | Model | Why |
|------|-------|-----|
| Scope / decompose / plan | **Opus** | genuine judgment |
| Search / discover / grep | **Haiku** | mechanical |
| Read / fetch / extract | **Sonnet** | light reasoning; don't over-downgrade workers |
| Verify (skeptic / judge) | **Sonnet** | diversity > raw strength for correctness checks |
| Synthesize / final report | **Opus** | the payoff step |

Set per-agent via `agent(prompt, { model: 'claude-haiku-4-5' })` or per-phase in `meta.phases`
(use full IDs — `claude-haiku-4-5` / `claude-sonnet-5` / `claude-opus-5`, never bare `'haiku'`).
Omitting `model` inherits the session model (often Opus) — fine for small fan-outs, costly at scale.

For the **mechanical read-only roles** (search/discover, read/extract, verify) add
`agentType: 'lean-worker'` on top of the model tier — it strips the ~5.2k skill+MCP floor per agent
(see the second-lever note above). The lean-worker is pinned to Sonnet but the `model:` override
still composes if you want Haiku for pure grep work. For roles that need the web (search/fetch),
use `'web-worker'` (allowlist `WebSearch, WebFetch`) — same floor-trim, with web access.
**If this repo has neither agent yet, create them from Appendix A (they activate next session), or
just omit `agentType:` — model-tiering alone still works, you only forgo the ~5k/agent floor-trim.**
A custom `agentType:` the registry doesn't know **fails the agent** (`agent type 'x' not found` →
that agent returns `null`); so don't reference one you haven't created and restarted into.

> **1M-context gotcha (cost trap, not a logic bug).** Workflow subagents inherit the session's
> *context-length variant*, not just its model tier. On a `…[1m]` (1M-context) session, **every**
> spawned agent trips the gate `API Error: Usage credits required for 1M context` when extra-spend
> headroom is low — even agents you pinned to `model: 'haiku'` (the per-agent `model:` override
> does **not** strip the inherited 1M flag before the credit check). The gate is a *reservation*
> check; 1M search/spawn never actually draws the credit down. Symptom: agents die at spawn with
> `0` tokens and the phase short-circuits on empty results — reads like a discovery bug, isn't one.
> Fix: `/model` → standard-context variant before running a fan-out, or bump the spend limit.

## Step 4 — Cascade verification, don't flat-panel everything

NOT every finding needs a 3-vote Opus panel — that's how an audit balloons to 100+ agents.
Empirically (Trust-or-Escalate, ICLR 2025): a cheap→strong judge cascade hits ≥80% human
agreement with ~88% of cases handled by the cheap model.

Pattern: **1 cheap screening vote on every item → escalate to the full 3-vote panel ONLY for
items that are high-importance OR low-confidence OR weak-sourced.** Frame verifiers to *refute*
(default to refuted=true if uncertain). Use *diverse lenses* (correctness/security/repro), not
N identical skeptics.

## Step 5 — Structure & durability

- **`schema` on every agent** — forces tight JSON returns, cheaper than prose, no parsing.
- **Synthesize in the main loop when small** — merging a handful of structured returns yourself
  saves a final agent.
- **Graceful partial returns** — `.filter(Boolean)`; guard empty stages; return what you have.
- **Return only JSON-plain data from `parallel`/`pipeline` thunks** — the runtime journals stage
  results for durability/resume, which JSON-round-trips them and **silently strips `Map`/`Set`/class
  instances to plain `{}`** (measured 2026-06-13: a `Map` built inside a thunk came back with no
  `.get`, crashing the combine). Return arrays/objects; build `Map`s and rich structures in the main
  loop *after* the barrier. (Corollary: this is also why `agent()` schema returns are plain objects.)
- **Batch the cheap stages** — when each unit of work is smaller than the ~14k floor (judging one
  finding, classifying one item), one agent over N items beats N agents over one each: the floor is
  paid once, not N×. Batch a cascade's screen (one agent, array in/out) and its panel *by lens*
  (3 agents judge all escalated items, preserving cross-lens diversity) — `hook-audit` dropped a
  12-hook sweep from ~70 agents/~1M tok to ~6/~250k this way.
- **Durability & cheap recovery:** completed `agent()` calls persist to `agent-*.jsonl` in the
  transcript dir. A run that dies mid-flight is NOT a total loss — `TaskStop` it, then either
  resume (`Workflow({scriptPath, resumeFromRunId})`, same session) or harvest the JSONL
  `StructuredOutput` payloads and synthesize the partial yourself. **Resume replays completed agents
  at 0 tokens** — so when a run crashes in *post-barrier combine logic* (a bug after the agents
  finished), fix the script and resume: every agent returns cached, only your fixed code re-runs.
  Always offer this before a long run is at risk.
- **Reading the result programmatically:** the task `.output` file is NOT your raw return — it wraps
  it as `{ summary, agentCount, logs, result }`. Parse `.result` for the object your script returned.
  (`<task-notification>` shows a truncated `result`; the file has the full thing.)
- **Iterate without resending the script:** every `Workflow` call persists its script under the
  session dir and returns the path. To revise, `Write`/`Edit` that file and re-invoke with
  `{scriptPath}` — cheaper than re-pasting, and it pairs with `resumeFromRunId`.

## Step 6 — Scale to the ask & declare caps

"find any bugs" → a few finders, single-vote verify. "thoroughly audit" → bigger pool, cascade
3-vote, synthesis. If you cap coverage (top-N, sampling, no-retry), `log()` what was dropped —
silent truncation reads as "covered everything."

## Output

Produce a runnable script: `export const meta = {…}` (pure literal; phase titles match
`phase()` calls) then the body. **Deployment is repo-dependent — pick the portable path unless the
repo says otherwise:**
- **Portable / always works:** save the `.js` anywhere and invoke `Workflow({ scriptPath: '<abs path>', args })`.
- **Named workflow:** to call it as `Workflow({ name: '<name>' })`, place it where the harness looks —
  `.claude/workflows/<name>.js`. **Caveat (bit us):** the *name* registry loads at session start, so a
  newly-added file is invokable by `scriptPath` immediately but by `name:` only after a restart. (The
  script itself hot-reloads when run by path; the name→file registry does not.)
- **This repo (claude-dotfiles) only:** source lives in `claude/workflows/<name>.js`, materialized to
  `.claude/workflows/` by a chezmoi template `dot_claude/workflows/symlink_<name>.js.tmpl`. That's a
  delivery detail of *this* repo, not a Workflow requirement — don't replicate it elsewhere.

Do NOT run it unless asked — authoring is free; running spends. State the estimated cost tier
(low/med/high) and the model mix.

## Checklist before handing back
- [ ] Is a workflow actually justified (comprehensiveness/confidence/scale)? If not, say so.
- [ ] Is discovery scouted inline / passed via args? Is `args` coerced from a JSON string (Step 1)?
- [ ] Is it a `pipeline` unless a barrier is genuinely needed?
- [ ] Are models tiered with FULL IDs (Haiku/Sonnet workers, Opus only for scope+synthesis)?
- [ ] Is verification cascaded, not flat-paneled? Are the cheap stages batched (one agent over N items)?
- [ ] Does every agent have a `schema`? Do `parallel`/`pipeline` thunks return only JSON-plain data?
- [ ] If you used `agentType: 'lean-worker'`/`'web-worker'`, does THIS repo have them? (Appendix A — else omit.)
- [ ] Are partial results / caps handled and logged? Is there a hard agent/file ceiling so a misfire can't balloon?

---

## Appendix A — Helper agents (copy into any repo to unlock the floor-trim)

These two scoped agents are what make `agentType: 'lean-worker'` / `'web-worker'` work. The win is
the **`tools:` allowlist**: with no `Skill` tool the ~30-skill `skill_listing` injection vanishes, and
with no MCP tools the `deferred_tools_delta` block vanishes — together ~5.2k tok/agent off the floor
(measured). Both ship in `claude/agents/` and chezmoi deploys them to `~/.claude/agents/`. Do not
paste a copy into a repo: an earlier copy here gave lean-worker `Bash`, and a shell can write, so it
was not read-only. Pin the model per call
for web-worker (Haiku for search, Sonnet for fetch/verify); it does not fix one. **They register at the
next session start**, so a workflow can't reference one created mid-session.

Verify after a restart with a 3-agent probe (no-tool agents, read `agent-*.jsonl`): a `lean-worker`
should show **no** `skill_listing` and **no** `deferred_tools_delta` attachments and a lower input-token
floor than the default workflow-subagent. If the attachments are still present, the allowlist didn't
take — check the agent registered (it won't, mid-session).
