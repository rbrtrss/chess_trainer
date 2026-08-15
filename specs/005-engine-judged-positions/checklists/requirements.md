# Specification Quality Checklist: Positions With No Author's Line

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-15
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Constitution Alignment

- [x] **Principle I (delayed feedback)** — the constitution requires that a specification which
      cannot state how it upholds this principle is not ready for planning, and that a feature
      risking a correctness leak is **rejected at specification time rather than mitigated at
      implementation time**. This feature introduces the strongest source of correctness the app
      has ever held, so the burden is highest here. FR-016 to FR-020 confine it to review, forbid
      it varying anything on a training screen *including latency*, and require it to be out of
      the training layer's reach entirely rather than merely unused. US3 is P1 for the same
      reason. SC-004 and SC-010 check it by what is reachable and what a screen reader would
      announce, not by eye — the method that caught the near-misses in 003 and 004.
- [x] **Principle II (offline-first)** — FR-008 requires the evaluation at review with no network;
      FR-009 forbids a session ever waiting on one; FR-010 defines the degraded case as "still
      trainable, and the review says so", which is the constitution's "a failed sync degrades to
      no new positions, never to a broken session". SC-006 and SC-007 verify it.
- [x] **Principle III (chess correctness delegated)** — engaged, and the spec deliberately does not
      say by what. It states what must be true of the evaluation (obtained, recorded, stable,
      available offline) and leaves the source to planning, where the licence check the
      constitution demands also belongs.
- [x] **Principle V (testing floor)** — the floor's existing items are untouched. This feature will
      add its own, and the Principle I guard test the constitution already requires gains the
      hardest case it has had.
- [x] Scope is justified against the goal: one rejection rule widens, no others (FR-002, FR-003,
      SC-003); authored positions are explicitly untouched (FR-011, FR-015).

## Notes

- Validated 2026-08-15. No clarification markers were raised: the questions that looked like
  clarifications turned out to be **plan** decisions, not spec decisions, and are listed below so
  planning does not mistake them for settled.
- **"Engine" is used as domain vocabulary, not as an implementation choice.** In chess it names a
  kind of answer, the way "solution" does. The spec never says which engine, whether it runs on
  the device or is asked over a network, or when it runs — only that the answer must exist, be
  stable, and be readable offline. Those constraints are strict enough that planning will find
  its options narrow, which is the intended effect.
- **The three questions planning must answer, none of which the spec settles:**
  1. What supplies the evaluation, given FR-008 forbids needing a network at review. A bundled
     engine and a fetch-at-import-and-keep both satisfy the wording, and they differ enormously
     in cost, app size and what happens when a file is imported with no signal.
  2. When it runs, given FR-009 forbids a session waiting and FR-017 forbids latency differences
     during training. "While the player is training" is the tempting answer and the one most
     likely to leak.
  3. Whether adding an engine warrants a constitution amendment. The Technology Constraints
     section names `dartchess`, `chessground`, Riverpod and Drift, and does not contemplate an
     engine; the licence compatibility check it demands applies before anything is adopted.
- **One judgement made rather than asked**, and the one most worth pushing back on: FR-004 rejects
  a position with no legal move — checkmate, stalemate — as having nothing to calculate. Nobody
  asked for that rule; it follows from the same reasoning that rejects a game record, but it is a
  new rejection in a feature whose purpose is to reject less.
