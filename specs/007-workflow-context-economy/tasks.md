# Tasks — Workflow Context Economy

> Task-line format: `- [ ] T<nnnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier, resolved
> through `.claude/MODELS.md` at run time. Task IDs use the **T12xx** block (4-digit
> format owner-ratified on #213; this block assignment ratified by the spec-007
> conversion PR) — unique across the repo (spec 001 = T1xx–T6xx, 002 = T7xx,
> 003 = T8xx, 004 = T9xx, 005 = T10xx, 006 = T11xx).

## Phase 1 — The measurement substrate

- [x] T1201 [strong] Repository token-budget check — per-file and per-bundle counts over
      the named context artifacts/bundles that exist at landing time; documented
      owner-ratified budgets (initial values from #166) with an explicit override path,
      budgets for later-landing surfaces (compact packet, stage cards, task index,
      restructured bundles) registered but gating deferred to the owning task's diff
      per US1.AC1 — this task creates no downstream artifact; wired into `verify` with
      the wiring asserted; two-sided falsification fixtures (planted over-budget fails
      naming artifact + count / within-budget control passes); tokenizer identity kept
      out of `workflow/**`, neutrality scan green (US1)

## Phase 2 — The compact surfaces

- [x] T1202 [strong] Shrink resident `AGENTS.md` to per-turn rules + pointers within its
      ratified budget; every removed rule re-homed in a named source-of-truth doc behind
      a surviving pointer; guard/workflow/CI references still resolve and the existing
      line-ceiling residency check stays enforced alongside the token budget; blocked by
      T1201 (US2)
- [x] T1203 [strong] Compact project packet — active routing facts only, within budget;
      two-sided drift check against `.claude/PROJECT.md` (planted drift fails naming the
      field / in-sync control passes) wired into `verify`; entrypoints read the packet by
      default with full-profile escalation explicit; blocked by T1201 (US3)
- [x] T1204 [strong] Split the per-task procedure into demand-loaded stage cards within
      budget (or documented override); entrypoint loads current card + compact packet
      only; full source stays coherent via generated assembly or index with a
      deterministic completeness/drift check compared against an independently captured
      pre-split obligation inventory (committed as a fixture the cards cannot influence)
      so a dropped obligation fails verification; existing references resolve and
      neutrality-scan coverage includes every card; blocked by T1201, T1203 (US4)
- [x] T1205 [strong] Generated task index — selection-critical fields only, within
      budget; two-sided staleness CI check (planted stale fails naming the entry /
      regenerated control passes) wired into `verify`; selection reads index-first then
      the selected task's full context with the deterministic selection preconditions
      unchanged; blocked by T1201 (US5)

## Phase 3 — Prose to determinism

- [x] T1206 [strong] Account for the governance-rule candidate set without duplicating
      existing coverage: merge-not-pre-approved is carried by T623's existing
      `guard.test.sh` regression (cite it, assert it still runs, extend only on a found
      gap — no re-implementation); budget-checks-wired is cited from US1.AC2; any new
      encoded rule ships with two-sided focused tests; non-encodable candidates
      documented with explicit P3 justification, never silently dropped; per encoded
      rule, resident prose reduced to a pointer at the check; all new checks name their
      repair target on failure (US6)

## Phase 4 — Runtime-surface amendment (issue #259)

- [x] T1207 [strong] Budget the runtime-attached context surface (spec-007 amendment,
      #259): an adapter-owned command (Claude Code side, beside `claude-code-probes.md`;
      named in no `workflow/**` doc, P1) reports fresh-session per-category counts (MCP
      servers, enabled skills, non-deferred tools, deferred-tool catalog size) + a token
      total for the runtime-attached surface on US1's counter (identity per US1.AC4 /
      context-budgets.md, so authored+floor sums like units), compact counts/totals only
      (two-sided fidelity test: counts AND token total derived from the actual inventory —
      two differing fixtures → differing counts and totals, or an absent category → zero and
      a smaller total; AND a count-independent limb — an equal-count/different-content fixture
      pair → strictly larger total for the larger body, equal to the US1 counter's measurement
      of those bytes — so a constant stub, or one that counts categories but hard-codes or
      count-derives the total, fails / negative assertion — no schema/config/secret bytes in
      output); the floor recorded as a named non-gating baseline produced by that command
      (outside the `context-budgets.md` gating table, read by no gate/tier/selection path —
      P5) consumable by the budget report to render `authored + floor = resident`; the
      command fails open/loud/never-gates on an unrecognized runtime shape (two-sided:
      unrecognized-shape fixture → loud notice + non-failing exit / supported-shape control
      reports counts); and an explicit ordering statement lands (constitution or
      `governance-rules.md`) that a budget-motivated removal of auditor-relied-on context is
      rejected — encoded with two-sided tests where deterministic, else explicit P3
      justification per US6.AC1's posture, registered in `governance-rules.md`, never
      silently dropped; measurement + baseline only, never a new gate; blocked by T1201 (US7)

## Phase 5 — Doc-pointer resolution (issue #273)

- [x] T1208 [strong] Deterministic doc-pointer resolution check (spec-007 amendment, #273):
      a `verify`-wired check that scans the pointer-bearing surfaces (at minimum `AGENTS.md`,
      `.claude/PROJECT.md`, `.claude/PROJECT.compact.md`), extracts the backtick-quoted
      repo-relative path pointers by shape (a `/` separator + a file-type suffix, minus AC2's
      non-path forms AND minus non-lexically-repo-relative tokens — absolute `/…`, `..`
      traversal, and `scheme://` URIs are out of contract, never resolved/flagged, keeping the
      check deterministic across machines) — candidacy NOT gated on the leading segment already
      existing AND leading-segment-agnostic (no fixed segment allowlist), so a bare
      `workflow/…md`/`hooks/…`/`adapters/…` pointer (resolves only under `.claude/`) is a
      candidate and then fails — and fails when one does not exist from the repo root, naming
      surface + path + line; non-vacuity proven by a positive-extraction assertion (the
      unmodified extractor recovers the COMPLETE real in-surface set present via a hand-verified
      independent oracle, not a subset) while leading-segment-agnosticism is proven off the
      mutable tree by AC3's held-out planted case (AC4 rewrites the real danglers in-diff, so
      the bare-nested coverage cannot live on the real surfaces) (AC1); no false positives
      on globs (`*`/`**`), brace-expansions (`{…,…}`, e.g. `specs/000-template/{spec,tasks}.md`),
      `<…>` placeholders, `→ "Heading"` anchors, command/flag tokens, or non-repo-relative
      tokens (absolute `/…`, `..` traversal, `scheme://` URIs) — a within-tree control
      carrying such forms passes (AC2); two-sided falsification tests in-diff — a planted
      dangling pointer fails naming surface/path/line, the planted form including the real
      `workflow/…md` shape (not only a synthetic `nonexistent.md`), plus a held-out bare-nested
      pointer under a leading segment named nowhere in the spec, also flagged, so neither a
      `workflow/`-only hard-code nor a fixed allowlist passes / an all-resolve control passes,
      plus a containment control (absolute `/…`, `..` traversal, `scheme://` URI) the check
      neither resolves nor flags (AC3); check green on the current tree — fix every flagged dangling pointer regardless of
      leading segment (illustrative non-exhaustive lower bound, ≥7 as of drafting:
      `.claude/PROJECT.md` `workflow/telemetry.md`+`workflow/maker-eval.md`+
      `workflow/reviewers/evasion-register.md`+`hooks/isolated-workspace.sh`+
      `hooks/isolation-falsification.test.sh`+`adapters/claude-code-probes.md`,
      `.claude/PROJECT.compact.md` mirror) → real `.claude/…` path, mirror kept in sync so
      `compact-packet-drift.sh` stays green; enumeration NOT load-bearing — the `verify`-green
      behavior is (AC4); wired into `verify` with the wiring asserted, diagnostics name the
      repair target (AC5); path existence only — section
      anchors deferred; carries US1.AC5 before/after token counts for the compact packet it
      edits; blocked by T1201, T1203 (US8)

## Phase 6 — Trajectory stability (issue #303)

- [ ] T1209 [strong] Dispatch-template stability check (#303) — spec-007 amendment: a
      committed, hand-verified declared-slot manifest per §7 dispatch template (the
      reviewer dispatch prompt and the fix-round maker prompt, at every site carrying
      template text — `.claude/workflows/gate-loop.js` plus any `workflow/**` site that
      restates template text); a `verify`-wired deterministic check extracts every
      interpolation/placeholder token from those sites and fails naming site + undeclared
      token; the manifest is an independent oracle, never regenerated from the template
      under test (US4.AC4/US8.AC1 discipline); two-sided in-diff falsification (planted
      undeclared-interpolation fixture fails naming site+token / unmodified real templates
      pass) plus a positive-extraction non-vacuity assertion (the unmodified extractor
      recovers the complete real slot set against a hand-verified expected set); cites —
      never re-encodes — `reviewer-roster.test.sh` for roster membership/tier/condition
      (anti-fork, cf. `lib-tasks-drift.sh`); governs template fixed text + slot inventory
      only, never reviewer output or gate semantics; no catch-all/wildcard slot; a new
      slot lands only by reviewed manifest edit in the template change's own diff; carries
      US1.AC5 before/after token counts for any measured surface touched (US9.AC1)
- [ ] T1210 [strong] Context-offloading design rules (#303) — spec-007 amendment: the
      handles-not-payloads rule in `.claude/DESIGN-NOTES.md` beside §11 — bounded
      structured sub-agent/broad-run returns (verdict + artifact pointers; full analysis
      on disk/tracker), naming the governed surfaces (§7 verdict returns, [bulk-read
      offload] returns, the retry feedback channel), recording the retry-granularity
      adjudication explicitly (verbatim kept with rationale, or bounded form via its own
      PR — P4) and the non-licenses (no weakening verbatim verdict posting to the PR; no
      removal without a surviving home), with an explicit P3 prose justification recorded
      in the note (US9.AC2); plus the code-over-prose orchestration entry — both
      justifications named side by side (P3 + root-context abstraction), the §7 prose
      procedure designated the degradation path when no [orchestrated run] exists, §12's
      derived-mirror contract cited not restated (US9.AC3)
- [ ] T1211 [strong] Maker-eval coverage-by-trajectory-class table (#303) — spec-007
      amendment: enumerated class taxonomy (at minimum spec/feature implementation,
      repo-maintenance/docs, bug fix, spec drafting/amendment, contract/architecture-
      touching) in `.claude/workflow/maker-eval.md` or the corpus doc it points to; every
      frozen golden task assigned to exactly one class; every class row names ≥1 corpus
      task ID or an explicit gap marker (never silently omitted); documentation of
      coverage only — feeds no gate/score/tier/selection (P5); instrument docs change only
      by the reviewed-PR path (P4); maker-eval docs/fence checks and the neutrality scan
      stay green (US9.AC4)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T1201 |
| US1.AC2 | T1201 |
| US1.AC3 | T1201 |
| US1.AC4 | T1201 |
| US1.AC5 | T1201–T1211 (every task, graded on its own PR body) |
| US2.AC1 | T1202 |
| US2.AC2 | T1202 |
| US2.AC3 | T1202 |
| US3.AC1 | T1203 |
| US3.AC2 | T1203 |
| US3.AC3 | T1203 |
| US4.AC1 | T1204 |
| US4.AC2 | T1204 |
| US4.AC3 | T1204 |
| US4.AC4 | T1204 |
| US5.AC1 | T1205 |
| US5.AC2 | T1205 |
| US5.AC3 | T1205 |
| US6.AC1 | T1206 |
| US6.AC2 | T1206 |
| US6.AC3 | T1206 |
| US7.AC1 | T1207 |
| US7.AC2 | T1207 |
| US7.AC3 | T1207 |
| US7.AC4 | T1207 |
| US8.AC1 | T1208 |
| US8.AC2 | T1208 |
| US8.AC3 | T1208 |
| US8.AC4 | T1208 |
| US8.AC5 | T1208 |
| US9.AC1 | T1209 |
| US9.AC2 | T1210 |
| US9.AC3 | T1210 |
| US9.AC4 | T1211 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Sequencing note (not a blocker): T1206's carried-coverage audit is independent of the
> measurement substrate and may land alongside T1201. Evidence rule: graded as
> **US1.AC5** — each T120x PR body carries measured before/after token counts for the
> surfaces its diff touches, alongside the standard red→green falsification evidence.
