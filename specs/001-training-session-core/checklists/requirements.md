# Specification Quality Checklist: Training Session Core

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-12
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

Checked against `.specify/memory/constitution.md` v1.0.0.

- [x] **Principle I (delayed feedback)**: upheld by FR-003, FR-005, FR-009, FR-016,
      FR-019 and SC-001. Story 1 scenarios 4 and 5 make the rule directly testable.
- [x] **Principle II (offline-first)**: upheld by FR-030 and SC-003. No network surface
      exists in this feature.
- [x] **Principle III (delegated chess correctness)**: the spec states legality and
      terminal-position requirements without prescribing how they are computed, leaving
      the constitution's mandate to the plan.
- [x] **Principle IV (layering)**: no layering claims are made in the spec, as intended —
      this belongs in the plan.
- [x] **Principle V (testing floor)**: the spec's testable units line up with the
      constitution's required tests — tree construction and branching (FR-007, FR-008),
      comparison (FR-021, FR-023), session state (FR-016, FR-018, FR-019).

## Validation Notes

Two items warrant attention before planning, neither blocking:

1. **SC-005 is not verifiable at this project's scale.** It posits nine of ten first-time
   users, but this is a single-user personal tool with no test cohort. It is retained
   because it captures a real design risk — that being asked to move for the opponent
   reads as a bug rather than a feature — but it should be treated as a design prompt, not
   a gate. Planning should either recruit a handful of real testers or restate it as an
   observable interface property.

2. **FR-012 and FR-013 introduce "primary line" mechanics** (first-child ordering and
   branch promotion) that the comparison in FR-021 and FR-023 depends on entirely. The
   match indicator's meaning is only as good as the user's control over which line is
   primary. This coupling is deliberate and correct, but it makes branch promotion more
   load-bearing than it first appears, and planning should not treat FR-013 as optional
   polish.

The known open question — how to score a *tree* against a *tree* — is resolved in this
spec by scope rather than deferred: FR-023 compares primary lines only, and FR-024
explicitly forbids judging other branches. Widening this later requires an engine and is
recorded as out of scope.

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
- All items pass as of 2026-08-12. Spec is ready for planning.
