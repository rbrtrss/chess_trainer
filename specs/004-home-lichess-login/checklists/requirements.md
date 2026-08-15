# Specification Quality Checklist: Lichess Login on the Home Screen

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

- [x] **Principle I (delayed feedback)**: this feature adds an element to the screen a session
      starts from, so the withholding question is asked rather than assumed. FR-020 keeps the
      account off every training screen; FR-021 forbids the control varying by library
      contents, chosen collection or session state, so it can carry no information about the
      position. SC-009 checks it against the accessibility tree rather than by eye.
- [x] **Principle II (offline-first)**: FR-004 forbids any network request to render the home
      screen or start the app — the state shown is a local fact; FR-008 keeps the login
      user-initiated; FR-019 forbids fetching as a consequence of logging in. SC-004 and SC-005
      verify it, in every account state.
- [x] **Principle III (chess correctness delegated)**: not engaged. No chess logic, parsing or
      position handling changes.
- [x] **Principle IV (layered architecture)**: not constrained by the spec, which says where the
      account appears and not how it is reached. The existing rule that no screen names the
      Lichess implementation is untouched.
- [x] **Lichess constraints**: FR-013 keeps "no refresh token, so expiry means log in again",
      and adds that expiry must be determined locally rather than by asking. FR-016 preserves
      the public-study-without-login path. No change to scopes, client id or token storage
      (Out of Scope).
- [x] Scope is justified against the goal: the account moves, and the duplicate control in the
      library is removed. Nothing new is fetched, validated or added to the account model.

## Notes

- Validated on 2026-08-15 with no failing items and no clarification markers raised.
- **Amended the same day.** FR-003 and SC-002 required the login to start in one action; the
  disclosure FR-007 requires does not fit in a bar that leaves the Start button on screen, so both
  were relaxed to two. See [spec.md, Amendments](../spec.md#amendments). Worth noting against the
  "requirements are testable and unambiguous" item above: FR-003 was testable and unambiguous, and
  still went unmet for a day, because nothing was checking it.
- One decision was made rather than asked, and is the one most worth pushing back on: **the
  library's account section is removed** (FR-012), not left in place alongside the new one.
  Recorded in Assumptions.
- Two facts the plan will have to confront: the home screen currently holds the resume prompt
  and three navigation actions already, so where the account goes is a real layout question;
  and connection state is deliberately never validated against the service (Assumptions), which
  means "connected" means "we hold a credential we have no local reason to doubt".
