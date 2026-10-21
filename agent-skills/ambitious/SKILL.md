---
name: ambitious
description: Push a task higher before building it. Use when the user invokes ambitious (/ambitious in Claude Code, $ambitious in Codex) or asks to be more ambitious, think bigger, push this further, ask what a top expert would do, or raise a task's altitude, depth or range. Produces a planning pass and a rewritten prompt, then waits for go-ahead. Never for an ordinary build, fix or question.
---

# Ambitious

Source: Felix Rieseberg, "How to be more ambitious: a tutorial for humans with models", 13 October 2026, https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/

A planning pass that pushes a task up three axes (altitude, depth, range) and ends with a rewritten prompt. The goal is a **deeper version of the task, not a bigger one**.

This pass is read-only. Do not edit files, run changes, or open PRs until the user gives an explicit go-ahead. You may read code, logs, data and docs to ground the answer; prefer specifics from the actual repo or system over generic advice.

## The task

The task is whatever the user passed when invoking this skill (in Claude Code, the text after /ambitious, shown as $ARGUMENTS). If nothing was passed, or that placeholder appears unfilled, use the most recent task the user described in this conversation and say which one you picked. If there is none, ask for it in one line and stop.

If the task is ambiguous, state your assumptions up front and proceed with them.

## Produce these sections, in order

### 1. Altitude: the outcome behind the task

A task is the user's best guess at how to reach an outcome. Ask: *what does the user want to happen next? What is the goal beyond the goal?* Then:

- State the outcome the user is really after, beyond the literal ask.
- Propose the task at three rungs, each more ambitious than the last:
  1. **Richer input:** same task, fed everything relevant instead of the minimum, so the result says what changed, why, and what should be done about it.
  2. **Decisions, not output:** identify the three most urgent decisions this work should inform and start on directions for each, with arguments for and against.
  3. **Rethink the mechanism:** state what the task exists to achieve, design a better mechanism than the current one, show from the user's own history that it would have caught things sooner, and propose running it beside the current one for a period.
- List the access and setup needed to pursue the top rung **without the user in the loop** and verify results independently: logs, crash or error reports, analytics, data exports, version-to-commit mappings, test hosts or devices, scripts, CI, credentials. Name the least-privilege scope for each. The aim is a durable workflow the user does not have to feed task by task; say what in their workflow has to change first.
- Say whether altitude fits. It fits work aimed at an ultimate outcome (a tell: the work needs meetings to discuss it). It fits creative work less well, and fully open-ended goals do not work on their own yet.

### 2. Depth: work like the top practitioner

Push toward the tools, techniques, media and knowledge the best professionals in the field use, until even they might learn something from the result. Changing vocabulary is not depth; changing methods is.

Answer these four questions:

1. What would a top professional in this field do here that the user is not asking for?
2. What is the **rawest material** they would start from, instead of what has already been digested for the user (logs, events, source data, measurements, not summaries or someone else's numbers)?
3. What **specific methods and tools** would they use? Name them. Where the default is a markdown table, the expert reaches for a database and a statistical model; elsewhere profilers, test harnesses, telemetry, fuzzers, simulations, controlled experiments.
4. What, other than you or the user, would show the result is right? (Expanded in section 4.)

Then add:

- **Challenge what the user believes:** name the task's underlying assumptions and plan to test them adversarially against the raw data ("we believe X; try to reproduce that from the raw data").
- **Produce new knowledge:** once inside the data, where are the blind spots? Propose one thing to discover that the user does not yet know, and how to show it predicts on data it has not seen.
- **One unreasonable target:** a goal that looks implausible but is achievable, stated as a number or a checkable condition (5 s to 200 ms, not 10 s to 5 s). Present it as solvable. Do not argue it is impossible; say what it would take.

### 3. Range: verbs, crew, and a red team

- **Verbs, not nouns:** restate the task as what it must actually *do* for the user or the people downstream (a quarterly review is not "a deck"; it is "getting busy people to believe a story about cause and effect, and to decide under uncertainty, in 30 minutes"). The verbs show which fields can contribute.
- **Assemble the crew:** name 3 to 5 fields outside software that would see this differently (for a deck: an analyst, a journalist, an editor, a motion and audio designer). For each, one concrete technique you will actually apply and the artifact it produces. Do not role-play the professional; do what the professional does. Not "write like a short seller" but "do what a short seller does to research a position".
- **Red team:** one adversarial perspective that tries to break or disprove the work (short seller, forensic accountant, attacker, hostile reviewer), and the first specific attack or counterexample it would try.
- Note what this crew needs that the environment does not yet provide (software to install, data to connect, MCP servers, machines to run on). Where parallel subagents would let several fields work at once, say so.

### 4. Verification: an outside judge

Do not judge your own work. Define how we will know it worked using something other than your judgment or the user's: tests, benchmarks, measurements, held-out data, real user data. Prefer a tool you can run for immediate feedback. For each check give the command or data source, the baseline, and the pass threshold.

### 5. Rewritten prompt

Rewrite the user's task as one self-contained prompt that asks for exactly the version above: the outcome, the raw material, the instruments, the assumptions to attack, the crew and red team, the unreasonable target, the access required, and the verification criteria. Specific, hard goals beat "do your best". Put it in a fenced block so it can be copied as is.

## Then stop

End with a one-line request for a go-ahead. Do not start executing until the user says to. If they edit the rewritten prompt, their version is the task.

## Style

- Concise and information-dense; the user is technically fluent. Specifics over generalities; absolute dates.
- Flag uncertainty as uncertainty. Each section earns its lines by changing what the user would do next.
- Hard targets are allowed to miss. Say what was reached and what was not.
