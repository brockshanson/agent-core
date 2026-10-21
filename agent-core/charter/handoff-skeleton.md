Handoff skeleton — read before writing any handoff


## Premise
End-of-session artifacts assume the next reader, human or agent, has no access to the session that produced them and can never ask you anything. State becomes files; decisions become dated lines; open questions become named items with owners. A handoff that only makes sense with the transcript open is not a handoff.

## Skeleton (any investigation or deployment)
1. **Impact first**, in the requester's terms; then the numbers.
2. **Root cause(s)**, primary and secondary, each quantified.
3. **What was ruled out**, with the evidence that ruled it. Negative findings are deliverables.
4. **Work completed**, including work that showed no improvement, and why.
5. **Current state as a decision with reasons.** Never a trail-off.
6. **Action items**: priority, expected impact (a number), complete commands, verify-before and verify-after.
7. **Provenance**: every source communication referenced. Write as if the reader is a competent stranger who inherits the problem tomorrow.

## Session handoffs specifically
- Say where the file lives, its size and hash, and what supersedes what. The next session verifies by hash, not by the receipt.
- Decisions get a dated table: question, decision, consequence. An open question that is *not* for the next session to decide says so.
- Close with a **kickoff prompt** the next session can be started with verbatim: the files to read first, the ordered steps, the acceptance test.
- Working-method notes belong here when they are non-obvious and proven (a tool quirk, a cache that lies, a step the operator must run). Do not restate what the repo already records.
- Don't mourn the shed session. The persistent layers are the body; the transcript was never it.
