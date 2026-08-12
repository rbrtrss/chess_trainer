# Implementation Plan: Training Session Core

**Branch**: `001-training-session-core` | **Date**: 2026-08-12 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-training-session-core/spec.md`

## Summary

Build the complete delayed-feedback training loop over a handful of bundled positions, with
no network, accounts, or persistence. The player analyses each position by entering a tree
of variations for both colours, commits, and sees nothing until the session ends; review
then shows their tree beside the solution with a divergence point, the author's notes, an
advisory match indicator, and a self-grade.

The technical approach rests on four decisions from [research.md](./research.md):

- An **immutable domain tree** (`VariationTree`), converted to and from dartchess's
  `PgnNode` at the boundary — needed because `PgnNode` is mutable and has no value
  equality, which defeats both FR-015 and the required tests.
- Bundled positions authored as **PGN**, so the parser this feature builds is the one
  feature 004 will reuse for Lichess studies.
- A **`TrainingProjection`** type that carries no solution or metadata, making feedback
  leaks a compile error rather than a matter of discipline.
- Illegal moves made **unreachable** rather than rejected, by feeding the board
  `makeLegalMoves(position)`.

## Technical Context

**Language/Version**: Dart 3.13.0 (bundled with Flutter 3.47.0)

**Primary Dependencies**: `chessground` ^10.1.1 (board UI), `dartchess` ^0.13.1 (rules, SAN,
PGN), `flutter_riverpod` (state), `fast_immutable_collections` (IList/IMap — already a
transitive dependency of chessground, so no new licence surface)

**Storage**: None. In-memory only; positions load from a bundled asset.

**Testing**: `flutter test` — unit tests for `lib/domain/`, widget tests for the tree editor
and the Principle I guard.

**Target Platform**: Android (phone). Verified on a physical device over `adb`.

**Project Type**: Mobile app, single Flutter module.

**Performance Goals**: 60 fps board interaction with a 40-move, 8-branch tree (SC-006).

**Constraints**: Fully offline (FR-030). Domain layer has zero Flutter imports.

**Scale/Scope**: 3–10 positions per session; one user; roughly 5 screens.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | How this design satisfies it |
|---|---|---|
| **I. Delayed feedback (non-negotiable)** | PASS | `TrainingProjection` (D5) removes solution data from the training layer entirely. The board is constructed with empty `annotations` and `shapes` — the two chessground parameters through which solution knowledge could reach the screen. `TreeEdit.createdBranch` is marked test-only so branch creation stays silent (FR-009). Commit advances straight to the next position with no interstitial (FR-016). Guard tests at three levels (D8). |
| **II. Offline-first** | PASS | No network code exists in this feature. Positions come from a bundled asset. |
| **III. Delegated chess correctness** | PASS | All legality, SAN, FEN and PGN handling goes through dartchess. No hand-rolled rules. `fromPgnNode` replays every move through `Position.play` so illegal nodes cannot be constructed. |
| **IV. Layering** | PASS | `lib/domain/` is pure Dart (dartchess is a pure Dart package and is the designated authority, so it is permitted there). `lib/data/` holds only the asset loader. `lib/ui/` depends inward. |
| **V. Testing floor** | PASS | Required units — tree construction/navigation/branching, tree comparison, session state machine — are all in `lib/domain/` with value equality, and enumerated as invariants 1–10 in [contracts/domain-api.md](./contracts/domain-api.md). Tree editor widget tests cover branching. The Principle I guard test is specified. |
| **Licensing** | PASS | chessground and dartchess are GPL-3.0; the project is GPL-3.0. `fast_immutable_collections` is MIT and compatible. Riverpod is MIT. No new licence risk. |
| **No secrets** | PASS | No credentials in this feature. |
| **Complexity justified** | PASS | The one added abstraction — a domain tree type distinct from `PgnNode` — is justified in D1 against three present problems, not anticipated ones. |

**Post-design re-check (after Phase 1)**: still PASS. The design added no network surface,
no persistence, and no dependency beyond those listed. `TrainingProjection` strengthened
Principle I relative to the pre-design position, where the plan had been to pass the full
`TrainingPosition` and rely on care.

## Project Structure

### Documentation (this feature)

```text
specs/001-training-session-core/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — decisions D1–D8
├── data-model.md        # Phase 1 — entities and state machine
├── quickstart.md        # Phase 1 — how to run and validate
├── contracts/
│   └── domain-api.md    # Phase 1 — domain surface and invariants
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 — created by /speckit-tasks, not here
```

### Source Code (repository root)

```text
lib/
├── main.dart
├── domain/                          # pure Dart — no Flutter imports
│   ├── tree/
│   │   ├── move_node.dart
│   │   ├── variation_tree.dart
│   │   └── move_path.dart
│   ├── position/
│   │   ├── training_position.dart   # + PositionMetadata
│   │   └── training_projection.dart # the leak barrier
│   ├── attempt/
│   │   ├── attempt.dart
│   │   └── comparison.dart          # compareToSolution
│   └── session/
│       ├── training_session.dart    # state machine
│       └── grade.dart
├── data/
│   ├── pgn_position_parser.dart     # PGN -> TrainingPosition; reused by feature 004
│   └── bundled_position_source.dart # loads assets/positions/*.pgn
└── ui/
    ├── app.dart
    ├── session/
    │   ├── session_setup_screen.dart
    │   └── session_controller.dart  # Riverpod notifier
    ├── training/
    │   ├── training_screen.dart     # consumes TrainingProjection only
    │   ├── analysis_editor.dart     # board + ◀ ▶ ⟲ + tree view
    │   └── analysis_editor_state.dart
    └── review/
        ├── review_screen.dart
        ├── tree_comparison_view.dart
        └── grade_buttons.dart

assets/positions/                    # bundled sample PGNs

test/
├── domain/                          # invariants 1–10 from the contract
│   ├── variation_tree_test.dart
│   ├── comparison_test.dart
│   └── training_session_test.dart
├── data/
│   └── pgn_position_parser_test.dart
└── ui/
    ├── analysis_editor_test.dart    # branching behaviour
    └── no_feedback_guard_test.dart  # Principle I
```

**Structure Decision**: A single Flutter module with the constitution's three layers as
top-level directories under `lib/`. No multi-package split: there is one deployable, and
`flutter test` already enforces the domain's purity because a stray Flutter import in
`lib/domain/` is visible in review and fails the layering test. Splitting into packages to
enforce it mechanically is complexity the constitution says to defer until a concrete
problem demands it.

## Implementation sequence

Ordered so the riskiest, most novel work is proven earliest, and so the app is runnable on
a device as soon as there is anything worth looking at.

1. **Scaffold** — `flutter create`, dependencies, layer directories, Android manifest.
   Confirm a debug build installs on the phone.
2. **Domain tree** — `MoveNode`, `MovePath`, `VariationTree` with `play`/`promote`/`delete`.
   Unit tests for invariants 1–3. *This is the piece everything else rests on.*
3. **PGN parsing** — `fromPgnNode`/`toPgnNode`, `parseTrainingPosition`, round-trip tests
   (invariant 10). Author 3 sample positions: a plain tactic, a quiet positional choice, an
   endgame technique.
4. **Analysis editor** — chessground wired to the tree, `◀ ▶ ⟲` navigation, silent
   branching, promotion and deletion. Widget tests for branching. **First device checkpoint:**
   the core interaction can be judged by hand here.
5. **Session state machine** — `TrainingSession`, projections, commit and abandon. Unit
   tests for invariants 7–9.
6. **Training screen** — consumes `TrainingProjection` only. Guard test (invariant 7 plus
   the widget-level check).
7. **Comparison** — `compareToSolution` with the diverged / ran-short / ran-long
   distinction. Unit tests for invariants 4–6.
8. **Review screen** — side-by-side trees, divergence highlight, comments, match indicator,
   self-grade. Metadata revealed here and only here.
9. **End-to-end pass on device** — the quickstart scenarios, including airplane mode.

Steps 2, 3, 5 and 7 are pure domain work and need no device, so they proceed regardless of
whether a phone is connected.

## Complexity Tracking

No constitution violations require justification. The single judgement call — a domain tree
type separate from dartchess's `PgnNode` — is recorded here for visibility rather than as a
violation.

| Decision | Why needed | Simpler alternative rejected because |
|---|---|---|
| `VariationTree` distinct from `PgnNode` | FR-015 requires committed attempts to be immutable; Principle V's tests need value equality; the cursor needs stable addressing | Using `PgnNode` directly leaves a mutable interior reachable from committed attempts and makes every tree assertion a hand-written recursive walk |

## Known risks

- **Tree navigation on a phone is the design risk.** Board-first implicit branching is easy
  to describe and easy to get subtly wrong; the user can lose track of which branch they are
  in. Step 4 exists as an early checkpoint precisely so this is judged by hand, on a device,
  before the rest is built on top of it.
- **SC-005 cannot be validated here** (one user, no cohort). Mitigated by a permanent,
  neutral turn indicator; genuinely settling it needs someone unfamiliar to try the app.
- **Match indicator honesty.** It compares primary lines only and says nothing about other
  branches. If it ever reads as a verdict rather than a measurement, users will treat it as
  a score and the self-grade becomes ceremony. Wording in the review UI matters more than it
  looks.
