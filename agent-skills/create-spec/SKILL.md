---
name: create-spec
description: |
  Interview-driven spec creation. Reads existing spec (if any), then interviews
  the user in-depth about implementation details, UX, concerns, and tradeoffs
  until the spec is complete.
  Triggers: "create spec", "write spec", "interview me about", "spec interview",
  "help me spec this out".
allowed-tools:
  - Read
  - Write
  - Glob
  - AskUserQuestion
  - WebSearch
---

# Create Spec

A preset of the `interviewing` skill: **Specify** stance, a completeness
checklist, a spec bank, and a spec file. Stance, medium, budget, the
checkpoint, and stopping all come from `interviewing` — read it first.

The best specs come from extracting what the person knows but hasn't
articulated: hidden requirements, implicit assumptions, tradeoffs, edge cases.
Don't ask what they already wrote down; ask what they're worried about, what
they've tried, what they want to avoid, and who else cares.

## Invocation

```bash
/create-spec @docs/SPEC.md                                   # from a draft
/create-spec "A CLI tool for managing dotfiles"              # from scratch
/create-spec "Authentication system" --output=docs/auth-spec.md
```

Said inline ("spec this out"), it specs whatever is already on the table.

If the idea reads earlier than Specify — no option chosen yet — say so in the
opening line and offer to explore or grill first. A spec of an undecided idea
freezes the first guess.

## Context load

If a file is provided, read it and note what's well-defined versus vague.
From scratch, take the topic as the seed and begin with scoping. Then check
the material against the completeness checklist — every gap is an interview
topic, and every item the material already settles is one you don't ask about.

## Completeness checklist

**Always needed:**
- [ ] Problem statement — what does this solve, for whom?
- [ ] Target users
- [ ] Success criteria — how do we know it works?
- [ ] Technical constraints — languages, platforms, dependencies
- [ ] Input/output formats

**Often missing:**
- [ ] Error handling strategy
- [ ] Edge cases and limitations
- [ ] Security considerations
- [ ] Performance requirements
- [ ] Integration points
- [ ] Migration/upgrade path
- [ ] Testing strategy

**Completeness condition:** every "always needed" item is addressed, and edge
cases have been discussed for the critical paths. Before writing, ask once:
*"Is there anything I haven't asked about that I should know?"*

## Spec bank

Settle scope before implementation detail. Don't assume their technical
level — ask.

**Technical implementation**
- "You mentioned [X] — any constraints on version or configuration?"
- "How should this behave when [dependency] is unavailable?"
- "What's the expected data volume? 10 items? 10 million?"
- "What existing systems does this integrate with?"

**User experience**
- "Walk me through a typical session."
- "What's the error experience? How does the user recover?"
- "Who's the least technical person who'll use this? What do they need?"

**Concerns and risks**
- "What worries you most about this?"
- "What's been tried before that didn't work?"
- "What would make this a failure even if it 'works'?"
- "Any compliance, legal, or security concerns?"

**Tradeoffs**
- "If you had to choose: [A] or [B]?"
- "What can be deferred to v2?"
- "Fail fast or degrade gracefully?"

**Non-obvious**
- "Who besides you cares about this, and what do they need to know?"
- "What's the migration story from the current state?"
- "What's the definition of done?"
- "What's NOT in scope that someone might assume is?"

A worked choice in this domain:

```
When the external API is down, should the tool:
  1. Retry with backoff (recommended) — 3 tries over 30s
  2. Fail immediately — return an error, user retries
  3. Use cached data — last known good response
  4. Queue for later — process when the API recovers
```

At the checkpoint, frame the summary around the checklist: which items are
now settled, which are still open.

## Artifact

Write the spec to the output path (or back to the draft). Scale the structure
to the project — small projects need less formality.

```markdown
# [Project Name] Specification

## Overview
## Problem Statement
## Goals
## Non-Goals
## Technical Requirements
## User Stories / Use Cases
## Data Model / Formats
## Error Handling
## Security Considerations
## Open Questions
## Decisions Made
[Key tradeoffs and why]
```

Then offer next steps: breaking it into sprints or tasks, iterating on
specific sections, or sharing it with stakeholders.
