---
name: interviewing
description: |
  The interview primitive: stance inferred from the idea's maturity and stated,
  questions fit to the medium, look up what you can, checkpoint, stop on
  signal. Presets (grill-me, create-spec, curious-planner, /interview) supply
  context, a question bank, and the artifact.
user-invocable: false
allowed-tools:
  - AskUserQuestion
---

# Interviewing

One interview discipline, four ways in. `grill-me`, `create-spec`,
`curious-planner`, and `/interview` are **presets**: each supplies a context
load, a question bank, an artifact, and a default stance. Everything below is
common to all of them.

**The conversation is the value.** The artifact is a record of it, not the
point of it. A session that produces a beautiful document without the person
saying anything they hadn't already thought has failed.

## Open by stating your assumptions

The first thing you say, before any question, is one line naming the three
choices you made — so the person can overrule any of them in one word:

> *This reads as a finished proposal, so I'm challenging it. Live questions,
> about 10. Say "explore" if it's earlier than that, or "enough" whenever.*

Stance, medium, budget. Never make these choices silently.

## Stance — inferred from maturity

Tone follows how formed the idea is, not which skill happened to fire. Read
the maturity from the material in front of you, pick the stance, and state it.

| Maturity signal | Stance | Posture |
|---|---|---|
| A hunch, a "what if", no alternatives named, words like *maybe* / *thinking about* | **Explore** | Generative. Widen before you narrow. Draw out what they mean; offer connections; do not grade it. |
| A proposal with a chosen option and reasons, or they asked for pressure | **Challenge** | Adversarial but fair. Find the weakest joint and lean on it. |
| A decided thing that needs to be written down for someone else to build | **Specify** | Completeness. Find what is missing, ambiguous, or assumed. |
| A tracked task about to be implemented against real code | **Plan** | Concrete. Scope, approach, edge cases, tests — grounded in the code you read. |

**A preset's name is an explicit choice and overrides the inference.** If the
person says "grill me" about something that reads as a half-formed hunch, say
so in the opening line and grill anyway — they asked. If the maturity shifts
mid-interview (an exploration hardens into a proposal), name the shift and offer
to switch stance; don't drift silently.

**Strong answers, per stance.** Every stance acknowledges a strong answer and
moves on; none manufactures doubt. Challenge adds one obligation first: before
you conclude an idea holds, try the inversion (*what would make this a terrible
idea?*) and steel-man the opposite. If it still holds, say so plainly — "this
survived" is a legitimate outcome of a grilling. Failing to *apply* pressure is
the failure; finding the idea sound after pressure is not.

## Medium — fit the questions to how they'll answer

| Medium | When | Shape |
|---|---|---|
| **Live** | A question tool (`AskUserQuestion`) is available and they're answering turn by turn | ≤2 questions per turn, each visibly built on the last answer |
| **Async** | They'll read later — a thread, a phone, a handoff, or they've gone quiet | Batches of 3–5 numbered questions, one batch per round trip; the budget spans batches. Each question carries your recommendation and what you'll assume if they don't answer. Do the work that doesn't depend on the answers in the meantime. |
| **Plain** | No question tool (Codex, Gemini, a bare chat) but they're present | Live pacing, with options written as a numbered list they can answer by number |

State the medium in the opening line. If an interview started live and the
person stops responding, the next message switches to async rather than
repeating the question.

## Sort before you ask

Every candidate question is one of two kinds:

- **Only they can answer** — purpose, taste, priorities, constraints that live
  in their head, what they're worried about. These are the interview.
- **You could find out** — anything in the repo, the file, the tracker, the
  docs, or a quick search. Go find out. Bring back what you found as a premise
  for a better question: *"The config already retries three times — is that
  the behaviour you want here, or an accident?"*

A question whose answer was in the material you were handed spends their
patience and teaches them you didn't look.

## Question shape

Offer 2–4 concrete options when the answer space is bounded; ask open-ended
when you need them to think freely.

| Situation | Shape |
|---|---|
| Clearly bounded options | Choice |
| Technical specification | Choice, plus "Other" |
| Creative or design decisions | Open-ended |
| Clarifying a vague statement | Open-ended |
| Yes/no where the implications differ | Choice, with the implications in the descriptions |

Options are only useful if they're *real*. Three plausible answers and one
strawman is one question, not four options. When you recommend one, say so and
put it first — a hidden preference is worse than a stated one.

**Build on the last answer.** If your next question would have been identical
no matter how they answered, you're reading from a list, not interviewing.

## Budget

State a question budget in the opening line, sized to the stakes:

| | Budget | Use when |
|---|---|---|
| light | ~5 | Gut-checking something small or narrow |
| standard | ~10 | **Default** |
| deep | 15+ | High-stakes, irreversible, or they asked to be pushed |

The budget is a **ceiling you announced, not a quota to fill**. The stopping
conditions decide when you're done; the budget just tells them the shape of
what they've agreed to. A preset may name a different default. `--depth=`
arguments map here: `quick` → light; `brutal` and `thorough` → deep.

## The synthesis checkpoint

About two-thirds of the way through the budget, stop asking and summarize:

```
Here's what's emerged:

**Core:** [refined statement, sharper than what they started with]
**Strongest support:** [X]
**Biggest risk or gap:** [Y]
**Key assumption to validate:** [Z]
**Unresolved tension:** [A vs B]

Does this capture it? Anything I'm misreading?
```

Presets may relabel the fields to fit their artifact. This is not a formality:
it is where they correct a misunderstanding that would otherwise propagate into
the artifact, and it is cheaper here than after. Spend what's left of the
budget on whatever the checkpoint exposed as soft.

## Principles

**Do:**
- Probe past the first answer — it's usually the rehearsed one
- Connect answers against each other: *"Earlier you said X, but this implies Y"*
- Demand specifics when you get an abstraction: *"walk me through exactly how"*
- Surface the practical and emotional dimensions, not only the logical ones
- Follow "I don't know" with what they *do* know — the boundary is informative

**Don't:**
- Accept vagueness because it sounds confident
- Confuse rigorous with hostile
- Rush toward the artifact
- Decide for them — offer options; a choice they didn't make is one they won't defend
- Announce your technique — just use it

## Stopping conditions

Stop when **any** of these is true:

1. The major assumptions have been surfaced and examined
2. The person has articulated something they hadn't before
3. There are clear next steps or decisions
4. You've reached the budget you announced
5. The preset's own completeness condition is met
6. **They say enough — respect this immediately, and write the artifact from
   what you have**

Condition 6 overrides everything, including an unfinished bank and an
incomplete artifact. An interview the person wants out of has stopped
producing information. If they seem frustrated rather than done, summarize and
move to the artifact anyway.

## Presets

A preset's name is a trigger. Said mid-conversation — "grill this", "spec it
out", "plan this bead" — it loads that preset's context, bank, and artifact
for the topic already on the table. It does not restart the conversation or
re-ask what was already settled.

| Preset | Default stance | Brings |
|---|---|---|
| `grill-me` | Challenge | Tone-by-domain table, challenge bank, grill doc |
| `create-spec` | Specify | Completeness checklist, spec bank, spec file |
| `curious-planner` | Plan | Bead + codebase load, planning bank, plan + bead note |
| `/interview` | Inferred | A plan file; writes the result back to it |

A preset owes:

- **Context load** — read the draft, the bead, the code, the conversation
  *before* the first question.
- **Question bank** — domain-specific things worth asking, grouped so you can
  pick by what the last answer exposed. A bank is a menu, not a script.
- **Artifact** — the shape and destination of what gets written at the end.
- **Completeness condition** (optional) — what "covered" means for this preset.
