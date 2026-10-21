export const meta = {
  name: 'deep-research',
  description: 'Deep research harness (cost-tiered) — fan-out web search, fetch, cascade-verify claims, synthesize a cited report.',
  whenToUse: 'When the user wants a deep, multi-source, fact-checked research report. BEFORE invoking, check if the question is specific enough — if underspecified, ask 2-3 clarifying questions first, then pass the refined question as args.',
  phases: [
    { title: 'Scope', detail: 'Decompose question (from args) into 5 search angles', model: 'claude-opus-5' },
    { title: 'Search', detail: '5 parallel Haiku web-worker searches, one per angle', model: 'claude-haiku-4-5' },
    { title: 'Fetch', detail: 'URL-dedup, fetch top sources, extract falsifiable claims (Sonnet web-worker)', model: 'claude-sonnet-5' },
    { title: 'Dedup', detail: 'Semantic-cluster claims so each is verified once', model: 'claude-sonnet-5' },
    { title: 'Screen', detail: 'One cheap Haiku no-web coherence vote per claim', model: 'claude-haiku-4-5' },
    { title: 'Verify', detail: 'Escalate only central/uncertain/weak-sourced claims to a 3-vote web panel (Sonnet)', model: 'claude-sonnet-5' },
    { title: 'Synthesize', detail: 'Merge, rank by confidence, cite (Opus)', model: 'claude-opus-5' },
  ],
}

// Cost-tiered rebuild of the bundled deep-research skill. The bundled version blew a session at
// 57/107 agents because the verify phase was a FLAT 3-vote panel on EVERY claim, each running a
// WebSearch, all on inherited Opus. This version:
//   1. Tiers models with FULL IDs (short alias 'haiku' silently falls back to Sonnet — never use it).
//   2. Routes web roles through agentType:'web-worker' (allowlist WebSearch+WebFetch → drops the
//      ~5k skill_listing+deferred_tools floor) and the no-tool screen through 'lean-worker'.
//      NOTE: custom agents register only at SESSION START — after first deploy this workflow must be
//      run in a session started AFTER claude/agents/{web,lean}-worker.md existed, else the agentType
//      is "not found". Model tiering alone still works without them.
//   3. Semantic-dedups claims so each cluster is verified once.
//   4. CASCADE verify (Trust-or-Escalate, ~88% handled cheap): 1 cheap no-web screen vote on every
//      claim → escalate to the full 3-vote web panel ONLY for central / low-confidence / weak-sourced
//      claims. The expensive web-search verifiers drop from ~75 to ~12.
// Question is passed via Workflow({name: 'deep-research', args: '<question>'}).

// ─── Model tiers (FULL IDs — never the bare 'haiku' alias) ───
const M_SCOPE  = 'claude-opus-5'
const M_SEARCH = 'claude-haiku-4-5'
const M_FETCH  = 'claude-sonnet-5'
const M_DEDUP  = 'claude-sonnet-5'
const M_SCREEN = 'claude-haiku-4-5'
const M_VERIFY = 'claude-sonnet-5'
const M_SYNTH  = 'claude-opus-5'

// ─── Scoped agentTypes (floor-trimmed; register at session start) ───
const A_WEB  = 'web-worker'   // WebSearch + WebFetch only
const A_LEAN = 'lean-worker'  // Read/Grep/Glob only, no shell (screen needs no tools)

// ─── Tunables ───
const VOTES_PER_CLAIM = 3
const REFUTATIONS_REQUIRED = 2
const MAX_FETCH = 15
const MAX_SCREEN_CLAIMS = 30   // screening is cheap, so cap higher than the old verify cap of 25

// ─── Schemas ───
const SCOPE_SCHEMA = {
  type: "object", required: ["question", "angles", "summary"],
  properties: {
    question: { type: "string" },
    summary: { type: "string" },
    angles: { type: "array", minItems: 3, maxItems: 6, items: {
      type: "object", required: ["label", "query"],
      properties: { label: { type: "string" }, query: { type: "string" }, rationale: { type: "string" } },
    }},
  },
}
const SEARCH_SCHEMA = {
  type: "object", required: ["results"],
  properties: {
    results: { type: "array", maxItems: 6, items: {
      type: "object", required: ["url", "title", "relevance"],
      properties: {
        url: { type: "string" }, title: { type: "string" }, snippet: { type: "string" },
        relevance: { enum: ["high", "medium", "low"] },
      },
    }},
  },
}
const EXTRACT_SCHEMA = {
  type: "object", required: ["claims", "sourceQuality"],
  properties: {
    sourceQuality: { enum: ["primary", "secondary", "blog", "forum", "unreliable"] },
    publishDate: { type: "string" },
    claims: { type: "array", maxItems: 5, items: {
      type: "object", required: ["claim", "quote", "importance"],
      properties: {
        claim: { type: "string" }, quote: { type: "string" },
        importance: { enum: ["central", "supporting", "tangential"] },
      },
    }},
  },
}
const DEDUP_SCHEMA = {
  type: "object", required: ["clusters"],
  properties: {
    clusters: { type: "array", items: {
      type: "object", required: ["representative", "memberIndexes"],
      properties: {
        representative: { type: "integer" },     // index into the input claim list
        memberIndexes: { type: "array", items: { type: "integer" } },
      },
    }},
  },
}
const SCREEN_SCHEMA = {
  type: "object", required: ["refuted", "confidence", "needsDeepCheck"],
  properties: {
    refuted: { type: "boolean" },                 // claim NOT supported by its quote / source too weak / obviously stale-or-marketing
    confidence: { enum: ["high", "medium", "low"] },
    needsDeepCheck: { type: "boolean" },          // screener flags it wants live web cross-checking
    reason: { type: "string" },
  },
}
const VERDICT_SCHEMA = {
  type: "object", required: ["refuted", "evidence", "confidence"],
  properties: {
    refuted: { type: "boolean" },
    evidence: { type: "string" },
    confidence: { enum: ["high", "medium", "low"] },
    counterSource: { type: "string" },
  },
}
const REPORT_SCHEMA = {
  type: "object", required: ["summary", "findings", "caveats"],
  properties: {
    summary: { type: "string" },
    findings: { type: "array", items: {
      type: "object", required: ["claim", "confidence", "sources", "evidence"],
      properties: {
        claim: { type: "string" }, confidence: { enum: ["high", "medium", "low"] },
        sources: { type: "array", items: { type: "string" } },
        evidence: { type: "string" }, vote: { type: "string" },
      },
    }},
    caveats: { type: "string" },
    openQuestions: { type: "array", items: { type: "string" } },
  },
}

// ─── Phase 0: Scope ───
phase("Scope")
const QUESTION = (typeof args === "string" && args.trim()) || ""
if (!QUESTION) {
  return { error: "No research question provided. Pass it as args: Workflow({name: 'deep-research', args: '<question>'})." }
}
const scope = await agent(
  "Decompose this research question into complementary search angles.\n\n" +
  "## Question\n" + QUESTION + "\n\n" +
  "## Task\n" +
  "Generate 5 distinct web search queries that together cover the question from different angles. Pick angles that suit the question's domain. Examples:\n" +
  "- broad/primary  · academic/technical  · recent news  · contrarian/skeptical  · practitioner/implementation\n" +
  "- For medical: anatomy · common causes · serious differentials · authoritative refs · red flags\n" +
  "- For tech: state-of-art · benchmarks · limitations · industry adoption · cost/tradeoffs\n\n" +
  "Make queries specific enough to surface high-signal results. Avoid redundancy.\n" +
  "Return: the question (verbatim or lightly normalized), a 1-2 sentence decomposition strategy, and the angles.\n\nStructured output only.",
  { label: "scope", phase: "Scope", model: M_SCOPE, schema: SCOPE_SCHEMA }
)
if (!scope) {
  return { error: "Scope agent returned no result — cannot decompose the research question." }
}
log("Q: " + QUESTION.slice(0, 80) + (QUESTION.length > 80 ? "…" : ""))
log("Decomposed into " + scope.angles.length + " angles: " + scope.angles.map(a => a.label).join(", "))

// ─── Dedup state — accumulates across searchers as they complete ───
const normURL = u => {
  try {
    const p = new URL(u)
    return (p.hostname.replace(/^www\./, "") + p.pathname.replace(/\/$/, "")).toLowerCase()
  } catch { return u.toLowerCase() }
}
const seen = new Map()
const urlDupes = []
const budgetDropped = []
const relRank = { high: 0, medium: 1, low: 2 }
let fetchSlots = MAX_FETCH

// ─── Prompts ───
const SEARCH_PROMPT = (angle) =>
  "## Web Searcher: " + angle.label + "\n\n" +
  "Research question: \"" + QUESTION + "\"\n\n" +
  "Your angle: **" + angle.label + "** — " + (angle.rationale || "") + "\n" +
  "Search query: `" + angle.query + "`\n\n" +
  "## Task\nUse WebSearch with the query above (or a refined version). Return the top 4-6 most relevant results.\n" +
  "Rank by relevance to the ORIGINAL question, not just the search query. Skip obvious SEO spam/content farms.\n" +
  "Include a short snippet capturing why each result is relevant.\n\nStructured output only."

const FETCH_PROMPT = (source, angle) =>
  "## Source Extractor\n\n" +
  "Research question: \"" + QUESTION + "\"\n\n" +
  "Fetch and extract key claims from this source:\n" +
  "**URL:** " + source.url + "\n**Title:** " + source.title + "\n**Found via:** " + angle + " search\n\n" +
  "## Task\n1. Use WebFetch to retrieve the page content.\n" +
  "2. Assess source quality: primary research/institution? secondary reporting? blog/opinion? forum? unreliable?\n" +
  "3. Extract 2-5 FALSIFIABLE claims that bear on the research question. Each claim must:\n" +
  "   - be a concrete, checkable statement (not vague generalities)\n" +
  "   - include a direct quote from the source as support\n" +
  "   - be rated central/supporting/tangential to the research question\n" +
  "4. Note publish date if available.\n\n" +
  "If the fetch fails or the page is irrelevant/paywalled, return claims: [] and sourceQuality: \"unreliable\".\n\nStructured output only."

const SCREEN_PROMPT = (claim) =>
  "## Claim Screener (cheap pass — NO web search)\n\n" +
  "Judge this claim on INTERNAL coherence only. Do NOT search the web. Decide fast.\n\n" +
  "## Research question\n" + QUESTION + "\n\n" +
  "## Claim\n\"" + claim.claim + "\"\n\n" +
  "**Source:** " + claim.sourceUrl + " (" + claim.sourceQuality + ")\n" +
  "**Supporting quote:** \"" + claim.quote + "\"\n" +
  "**Importance:** " + claim.importance + "\n\n" +
  "## Decide\n" +
  "1. Is the claim actually supported by the quote, or an overreach/misread of it?\n" +
  "2. Is the source quality adequate for the claim's strength? (extraordinary claims need primary sources)\n" +
  "3. Is it obviously stale or pure marketing/press-release language?\n\n" +
  "Set **refuted=true** if the claim plainly fails (1)-(3) on its face. Set **refuted=false** if it looks sound.\n" +
  "Set **needsDeepCheck=true** if you cannot decide from the quote alone and a live web cross-check is warranted\n" +
  "(e.g. a strong empirical claim that could be contradicted by other sources). Set **confidence** for your own call.\n\nStructured output only. reason MUST be specific."

const VERIFY_PROMPT = (claim, v) =>
  "## Adversarial Claim Verifier (voter " + (v + 1) + "/" + VOTES_PER_CLAIM + ")\n\n" +
  "Be SKEPTICAL. Try to REFUTE this claim. ≥" + REFUTATIONS_REQUIRED + "/" + VOTES_PER_CLAIM + " refutations kill it.\n\n" +
  "## Research question\n" + QUESTION + "\n\n" +
  "## Claim under review\n\"" + claim.claim + "\"\n\n" +
  "**Source:** " + claim.sourceUrl + " (" + claim.sourceQuality + ")\n" +
  "**Supporting quote:** \"" + claim.quote + "\"\n\n" +
  "## Checklist\n" +
  "1. Is the claim actually supported by the quote, or is it an overreach/misread?\n" +
  "2. WebSearch for contradicting evidence — does any credible source dispute or heavily qualify this?\n" +
  "3. Is the source quality sufficient for the claim's strength? (extraordinary claims need primary sources)\n" +
  "4. Is the claim outdated? (check dates — old claims about fast-moving fields are suspect)\n" +
  "5. Is this a marketing claim / press release / cherry-picked benchmark / forum speculation?\n\n" +
  "**refuted=true** if: unsupported by quote / contradicted / low-quality source for strong claim / outdated / marketing fluff.\n" +
  "**refuted=false** ONLY if: claim is well-supported, current, and source quality matches claim strength.\n" +
  "Default to refuted=true if uncertain.\n\nStructured output only. Evidence MUST be specific."

// ─── Pipeline: search → dedup → fetch+extract (no barrier) ───
const searchResults = await pipeline(
  scope.angles,

  angle => agent(SEARCH_PROMPT(angle), {
    label: "search:" + angle.label, phase: "Search", model: M_SEARCH, agentType: A_WEB, schema: SEARCH_SCHEMA
  }).then(r => {
    if (!r) return null
    log(angle.label + ": " + r.results.length + " results")
    return { angle: angle.label, results: r.results }
  }),

  searchResult => {
    if (!searchResult) return null
    const sorted = [...searchResult.results].sort((a, b) => relRank[a.relevance] - relRank[b.relevance])
    const novel = sorted.filter(r => {
      const key = normURL(r.url)
      if (seen.has(key)) {
        urlDupes.push({ ...r, angle: searchResult.angle, dupOf: seen.get(key) })
        return false
      }
      if (fetchSlots <= 0 && relRank[r.relevance] >= 1) {
        budgetDropped.push({ ...r, angle: searchResult.angle })
        return false
      }
      seen.set(key, { angle: searchResult.angle, title: r.title })
      fetchSlots--
      return true
    })
    if (novel.length < searchResult.results.length) {
      log(searchResult.angle + ": " + novel.length + " novel (" + (searchResult.results.length - novel.length) + " filtered)")
    }
    return parallel(
      novel.map(source => () => {
        let host = "unknown"
        try { host = new URL(source.url).hostname.replace(/^www\./, "") } catch {}
        return agent(FETCH_PROMPT(source, searchResult.angle), {
          label: "fetch:" + host, phase: "Fetch", model: M_FETCH, agentType: A_WEB, schema: EXTRACT_SCHEMA,
        }).then(ext => {
          if (!ext) return null
          return {
            url: source.url, title: source.title, angle: searchResult.angle,
            sourceQuality: ext.sourceQuality, publishDate: ext.publishDate,
            claims: ext.claims.map(c => ({ ...c, sourceUrl: source.url, sourceQuality: ext.sourceQuality })),
          }
        }).catch(e => {
          log("fetch failed: " + source.url + " — " + (e.message || e))
          return { url: source.url, title: source.title, angle: searchResult.angle, sourceQuality: "unreliable", claims: [] }
        })
      })
    )
  }
)

const allSources = searchResults.flat().filter(Boolean)
const allClaims = allSources.flatMap(s => s.claims)
const impRank = { central: 0, supporting: 1, tangential: 2 }
const qualRank = { primary: 0, secondary: 1, blog: 2, forum: 3, unreliable: 4 }
const WEAK_SOURCE = q => (qualRank[q] ?? 4) >= 2   // blog/forum/unreliable

// Rank by importance then source quality, cap before the (cheap) screen.
const rankedClaims = [...allClaims]
  .sort((a, b) => (impRank[a.importance] - impRank[b.importance]) || (qualRank[a.sourceQuality] - qualRank[b.sourceQuality]))
  .slice(0, MAX_SCREEN_CLAIMS)
const screenDropped = allClaims.length - rankedClaims.length
if (screenDropped > 0) log("Capped claim pool: verifying top " + rankedClaims.length + " of " + allClaims.length + " (dropped " + screenDropped + " low-rank tail)")

if (rankedClaims.length === 0) {
  return {
    question: QUESTION,
    summary: "No claims extracted. " + allSources.length + " sources fetched, all empty/failed. " + urlDupes.length + " URL dupes, " + budgetDropped.length + " budget-dropped.",
    findings: [], refuted: [], sources: allSources.map(s => ({ url: s.url, quality: s.sourceQuality })),
    stats: { angles: scope.angles.length, sources: allSources.length, claims: 0, urlDupes: urlDupes.length },
  }
}

// ─── Semantic dedup: cluster claims so each meaning is verified once ───
// Barrier: the full claim pool must be assembled before clustering.
phase("Dedup")
let clusters
const dedupOut = await agent(
  "## Semantic claim de-duplicator\n\n" +
  "Below is a numbered list of research claims gathered from many sources. Group claims that assert the\n" +
  "SAME underlying fact (even if worded differently or from different sources) into clusters, so each\n" +
  "distinct claim is verified only once. A claim that stands alone is its own single-member cluster.\n\n" +
  "## Research question\n" + QUESTION + "\n\n" +
  "## Claims\n" +
  rankedClaims.map((c, i) => i + ". [" + c.importance + ", " + c.sourceQuality + "] " + c.claim).join("\n") + "\n\n" +
  "## Task\nReturn clusters. For each cluster pick the single best-worded claim index as `representative`\n" +
  "and list ALL member indexes (including the representative) in `memberIndexes`. Every input index must\n" +
  "appear in exactly one cluster. Prefer the representative with the strongest source / clearest wording.\n\nStructured output only.",
  { label: "dedup", phase: "Dedup", model: M_DEDUP, schema: DEDUP_SCHEMA }
)
if (dedupOut && Array.isArray(dedupOut.clusters) && dedupOut.clusters.length) {
  // Build representative claims, merging member source URLs. Guard against bad indexes.
  const valid = c => Number.isInteger(c) && c >= 0 && c < rankedClaims.length
  clusters = dedupOut.clusters
    .filter(cl => valid(cl.representative))
    .map(cl => {
      const members = (cl.memberIndexes || []).filter(valid)
      const rep = rankedClaims[cl.representative]
      const mergedSources = [...new Set([rep.sourceUrl, ...members.map(i => rankedClaims[i].sourceUrl)])]
      return { ...rep, mergedSources, memberCount: members.length || 1 }
    })
  // Safety net: if clustering dropped indexes, append the missing ones as singletons.
  const covered = new Set(dedupOut.clusters.flatMap(cl => (cl.memberIndexes || []).filter(valid)))
  rankedClaims.forEach((c, i) => { if (!covered.has(i)) clusters.push({ ...c, mergedSources: [c.sourceUrl], memberCount: 1 }) })
  log("Deduped " + rankedClaims.length + " claims → " + clusters.length + " distinct clusters")
} else {
  // Dedup failed/skipped — fall back to verifying every ranked claim.
  clusters = rankedClaims.map(c => ({ ...c, mergedSources: [c.sourceUrl], memberCount: 1 }))
  log("Dedup skipped — verifying all " + clusters.length + " claims individually")
}

// ─── CASCADE verify: cheap screen on all → escalate only the uncertain/high-stakes ───
phase("Screen")
const screened = (await parallel(
  clusters.map(claim => () =>
    agent(SCREEN_PROMPT(claim), { label: "screen:" + claim.claim.slice(0, 36), phase: "Screen", model: M_SCREEN, agentType: A_LEAN, schema: SCREEN_SCHEMA })
      .then(s => ({ claim, screen: s }))
  )
)).filter(x => x && x.screen)

// Escalation rule (Trust-or-Escalate): a cheap verdict is trusted UNLESS the claim is high-stakes
// or the screen itself is unsure. Escalate if central-importance, OR screen low-confidence, OR the
// screener asked for a deep check, OR the source is weak (blog/forum/unreliable).
const needsEscalation = ({ claim, screen }) =>
  claim.importance === "central" ||
  screen.confidence === "low" ||
  screen.needsDeepCheck === true ||
  WEAK_SOURCE(claim.sourceQuality)

const toEscalate = screened.filter(needsEscalation)
const trusted = screened.filter(x => !needsEscalation(x))
log("Screened " + screened.length + " claims → " + toEscalate.length + " escalated to 3-vote panel, " + trusted.length + " resolved on cheap screen")

phase("Verify")
const escalatedVerdicts = (await parallel(
  toEscalate.map(({ claim }) => () =>
    parallel(
      Array.from({ length: VOTES_PER_CLAIM }, (_, v) => () =>
        agent(VERIFY_PROMPT(claim, v), { label: "v" + v + ":" + claim.claim.slice(0, 36), phase: "Verify", model: M_VERIFY, agentType: A_WEB, schema: VERDICT_SCHEMA })
      )
    ).then(verdicts => {
      const valid = verdicts.filter(Boolean)
      const refuted = valid.filter(v => v.refuted).length
      const abstained = VOTES_PER_CLAIM - valid.length
      // Survive only if actually adjudicated: a quorum of valid votes AND fewer than the kill threshold.
      const survives = valid.length >= REFUTATIONS_REQUIRED && refuted < REFUTATIONS_REQUIRED
      log("[deep] \"" + claim.claim.slice(0, 46) + "…\": " + (valid.length - refuted) + "-" + refuted + (abstained ? " (" + abstained + " abstain)" : "") + " " + (survives ? "✓" : "✗"))
      return { ...claim, tier: "deep", verdicts: valid, refutedVotes: refuted, survives }
    })
  )
)).filter(Boolean)

// Trusted claims carry their single screen verdict forward.
const trustedVerdicts = trusted.map(({ claim, screen }) => ({
  ...claim, tier: "screen",
  verdicts: [{ refuted: screen.refuted, evidence: screen.reason || "(cheap screen)", confidence: screen.confidence }],
  refutedVotes: screen.refuted ? 1 : 0,
  survives: !screen.refuted,
}))

const voted = [...escalatedVerdicts, ...trustedVerdicts]
const confirmed = voted.filter(c => c.survives)
const killed = voted.filter(c => !c.survives)
log("Verify done: " + voted.length + " claims (" + escalatedVerdicts.length + " deep, " + trustedVerdicts.length + " screen) → " + confirmed.length + " confirmed, " + killed.length + " killed")

if (confirmed.length === 0) {
  return {
    question: QUESTION,
    summary: "All " + voted.length + " claims refuted by cascade verification. Research inconclusive — sources may be low-quality or claims overstated.",
    findings: [],
    refuted: killed.map(c => ({ claim: c.claim, tier: c.tier, source: c.sourceUrl })),
    sources: allSources.map(s => ({ url: s.url, quality: s.sourceQuality, claimCount: s.claims.length })),
    stats: { angles: scope.angles.length, sources: allSources.length, claims: allClaims.length, clusters: clusters.length, escalated: toEscalate.length, confirmed: 0, killed: killed.length },
  }
}

// ─── Synthesize ───
phase("Synthesize")
const confRank = { high: 0, medium: 1, low: 2 }
const block = confirmed.map((c, i) => {
  const best = c.verdicts.filter(v => !v.refuted).sort((a, b) => confRank[a.confidence] - confRank[b.confidence])[0] || c.verdicts[0]
  const voteStr = c.tier === "deep" ? (c.verdicts.length - c.refutedVotes) + "-" + c.refutedVotes + " panel" : "screen-pass"
  return "### [" + i + "] " + c.claim + "\n" +
    "Verify: " + voteStr + " · Sources: " + (c.mergedSources || [c.sourceUrl]).join(", ") + " (" + c.sourceQuality + ")\n" +
    "Quote: \"" + c.quote + "\"\nVerifier evidence (" + (best ? best.confidence : "n/a") + "): " + (best ? best.evidence : "—") + "\n"
}).join("\n")

const killedBlock = killed.length > 0
  ? "\n## Refuted claims (for transparency)\n" +
    killed.map(c => "- \"" + c.claim + "\" (" + c.sourceUrl + ", " + (c.tier === "deep" ? (c.verdicts.length - c.refutedVotes) + "-" + c.refutedVotes + " panel" : "screen-refuted") + ")").join("\n")
  : ""

const report = await agent(
  "## Synthesis: research report\n\n" +
  "**Question:** " + QUESTION + "\n\n" +
  confirmed.length + " claims survived cascade verification (cheap screen + selective 3-vote panel). Merge semantic duplicates and synthesize.\n\n" +
  "## Confirmed claims\n" + block + "\n" + killedBlock + "\n\n" +
  "## Instructions\n" +
  "1. Identify claims that say the same thing — merge them, combine their sources.\n" +
  "2. Group related claims into coherent findings. Each finding should directly address the research question.\n" +
  "3. Assign confidence per finding: high (multiple primary sources, unanimous votes), medium (secondary sources or split votes), low (single source or blog-quality / screen-only).\n" +
  "4. Write a 3-5 sentence executive summary answering the research question.\n" +
  "5. Note caveats: what's uncertain, what sources were weak, what time-sensitivity applies.\n" +
  "6. List 2-4 open questions that emerged but weren't answered.\n\nStructured output only.",
  { label: "synthesize", phase: "Synthesize", model: M_SYNTH, schema: REPORT_SCHEMA }
)

if (!report) {
  return {
    question: QUESTION,
    summary: "Synthesis step was skipped or failed — returning " + confirmed.length + " verified claims unmerged.",
    findings: [],
    confirmed: confirmed.map(c => ({ claim: c.claim, source: c.sourceUrl, quote: c.quote, tier: c.tier })),
    refuted: killed.map(c => ({ claim: c.claim, tier: c.tier, source: c.sourceUrl })),
    sources: allSources.map(s => ({ url: s.url, quality: s.sourceQuality, claimCount: s.claims.length })),
    stats: { angles: scope.angles.length, sources: allSources.length, claims: allClaims.length, clusters: clusters.length, escalated: toEscalate.length, confirmed: confirmed.length, killed: killed.length, afterSynthesis: 0 },
  }
}

return {
  question: QUESTION,
  ...report,
  refuted: killed.map(c => ({ claim: c.claim, tier: c.tier, source: c.sourceUrl })),
  sources: allSources.map(s => ({ url: s.url, quality: s.sourceQuality, angle: s.angle, claimCount: s.claims.length })),
  stats: {
    angles: scope.angles.length,
    sourcesFetched: allSources.length,
    claimsExtracted: allClaims.length,
    clusters: clusters.length,
    screened: screened.length,
    escalatedToPanel: toEscalate.length,
    resolvedOnScreen: trusted.length,
    confirmed: confirmed.length,
    killed: killed.length,
    afterSynthesis: report.findings.length,
    urlDupes: urlDupes.length,
    budgetDropped: budgetDropped.length,
    // Cascade keeps the expensive web-verifier count low: ~escalated×3 instead of every-claim×3.
    agentCalls: 1 + scope.angles.length + allSources.length + 1 + screened.length + (toEscalate.length * VOTES_PER_CLAIM) + 1,
  },
}
