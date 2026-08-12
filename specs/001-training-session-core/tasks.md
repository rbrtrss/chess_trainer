---

description: "Task list for Training Session Core"
---

# Tasks: Training Session Core

**Input**: Design documents from `/specs/001-training-session-core/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/domain-api.md](./contracts/domain-api.md), [quickstart.md](./quickstart.md)

**Tests**: Test tasks are included and are **not optional here**. Constitution Principle V
requires unit tests for tree construction/navigation/branching, tree comparison, and the
session state machine; widget tests for the editor's branching behaviour; and a guard test
for Principle I. The invariant numbers referenced below are from
[contracts/domain-api.md](./contracts/domain-api.md).

**Organization**: Tasks are grouped by user story so each story can be implemented, tested,
and judged on a device independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths are given in every task

## Path Conventions

Single Flutter module at the repository root (`/home/roberto/chess_trainer`), with the
constitution's three layers as top-level directories under `lib/`, per plan.md's Structure
Decision. All paths below are repository-relative.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A Flutter project that builds and installs on the phone, with the layer
directories and dependencies in place.

- [X] T001 Scaffold the Flutter app in place at the repository root with `flutter create --project-name chess_trainer --org dev.chesstrainer --platforms android .`, keeping the existing `LICENSE`, `.gitignore`, `.specify/`, `.claude/` and `specs/` untouched
- [X] T002 Add dependencies to `pubspec.yaml` — `chessground: ^10.1.1`, `dartchess: ^0.13.1`, `flutter_riverpod`, `fast_immutable_collections`, `meta` — then run `flutter pub get` and record the resolved versions
- [X] T003 [P] Configure strict analysis in `analysis_options.yaml`: enable `flutter_lints`, plus `strict-casts`, `strict-inference` and `strict-raw-types` under `analyzer.language`
- [X] T004 [P] Create the layer directory skeleton `lib/domain/{tree,position,attempt,session}/`, `lib/data/`, `lib/ui/{session,training,review}/`, `test/{domain,data,ui}/` and `assets/positions/`, and declare `assets/positions/` under `flutter.assets` in `pubspec.yaml`
- [X] T005 [P] Set the app label and confirm no `INTERNET` permission is declared in `android/app/src/main/AndroidManifest.xml` (FR-030 — the feature must build with no network capability at all)
- [X] T006 Verify a debug build installs and launches on the physical device with `flutter devices` then `flutter run`, per the prerequisites in [quickstart.md](./quickstart.md)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The immutable domain tree and the bundled-position pipeline. Every user story
reads and writes a `VariationTree`, and every user story needs positions to load, so none
can start until this phase is done.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Domain tree

- [X] T007 [P] Define `IllegalMoveError`, `InvalidPathError` and `PositionParseError` per the error contract in `lib/domain/errors.dart`
- [X] T008 [P] Implement immutable `MovePath` (`IList<int>` indices, `root`, `child`, `parent`, `isRoot`, `length`, value equality, readable `toString` for test output) in `lib/domain/tree/move_path.dart`
- [X] T009 [P] Implement immutable `MoveNode` (`move`, `san`, `IList<MoveNode> children`, `comments`, `nags`, value equality) in `lib/domain/tree/move_node.dart`
- [X] T010 Implement `VariationTree` fields and read accessors — `initialPosition`, `children`, `isEmpty`, `primaryLine`, `nodeCount`, `depth`, `positionAt`, `nodeAt`, `legalMovesAt` (replay from the root per research D2, throwing `InvalidPathError` for stale paths) in `lib/domain/tree/variation_tree.dart`
- [X] T011 Implement `TreeEdit` and `VariationTree.play(MovePath, Move)` in `lib/domain/tree/variation_tree.dart` — append a child when the move is new, navigate to the existing child when its SAN is already recorded (FR-007, FR-008), throw `IllegalMoveError` otherwise, and mark `createdBranch` test-only in dartdoc so it cannot justify a UI announcement (FR-009)
- [X] T012 Implement `VariationTree.promote(MovePath)` and `VariationTree.delete(MovePath)` in `lib/domain/tree/variation_tree.dart` (FR-011, FR-013)
- [X] T013 [P] Unit tests for invariants 1–3 — replaying a recorded move does not duplicate a sibling, branching leaves the original subtree intact, promotion changes only child ordering — in `test/domain/variation_tree_test.dart`
- [X] T014 [P] Unit tests for navigation and construction — `positionAt`/`nodeAt`/`legalMovesAt` at root and deep paths, `primaryLine`, `nodeCount`, `depth`, `InvalidPathError` on a stale path, `IllegalMoveError` on an illegal `play` — in `test/domain/variation_tree_navigation_test.dart`

### Positions

- [X] T015 [P] Implement immutable `PositionMetadata` (with `empty`) and `TrainingPosition` (`id`, `initialPosition`, `solution`, `metadata`, derived `sideToMove`) in `lib/domain/position/training_position.dart`
- [X] T016 [P] Implement `TrainingProjection` (`positionId`, `initialPosition`, `sideToMove`, `indexInSession`, `sessionLength`) in `lib/domain/position/training_projection.dart`, with the dartdoc warning from the contract forbidding any field derived from `solution` or `metadata`
- [X] T017 Implement `fromPgnNode` and `toPgnNode` in `lib/data/pgn_position_parser.dart`, replaying every move through `Position.play` so an illegal node cannot be constructed (invariant 10)
- [X] T018 Implement `parseTrainingPosition(String pgn, {required String id})` in `lib/data/pgn_position_parser.dart` — `[FEN]` header with fallback to the standard position, headers into `PositionMetadata`, mainline into the solution's primary line, variations into sibling branches, `{comments}` and NAGs onto `MoveNode`, and `PositionParseError` on a bad FEN or illegal mainline move
- [X] T019 [P] Unit tests for the parser in `test/data/pgn_position_parser_test.dart`: invariant 10 over a nested-variation fixture, `fromPgnNode`/`toPgnNode` round trip, comment and NAG preservation, metadata extraction, and `PositionParseError` on a malformed FEN and on an illegal mainline move
- [X] T020 [P] Author three bundled sample positions as PGN with `[FEN]` headers, at least one variation and at least one `{comment}` each — a plain tactic, a quiet positional choice, and an endgame technique — in `assets/positions/001-tactic.pgn`, `assets/positions/002-positional.pgn`, `assets/positions/003-endgame.pgn`
- [X] T021 Implement `BundledPositionSource` loading `assets/positions/*.pgn` via `rootBundle` and returning `IList<TrainingPosition>` in `lib/data/bundled_position_source.dart`
- [X] T022 [P] Widget-binding test asserting every bundled PGN parses and that each yields a non-empty solution, in `test/data/bundled_position_source_test.dart`

### App shell

- [X] T023 Create the app entry point with a `ProviderScope` and a placeholder home route in `lib/main.dart` and `lib/ui/app.dart`

**Checkpoint**: The domain tree is proven by unit tests and the bundled positions load. User story work can begin.

---

## Phase 3: User Story 1 - Analyse one position without feedback (Priority: P1) 🎯 MVP

**Goal**: A single-position session in which the player builds a branching analysis for both
colours with nothing on screen reacting to correctness, commits it, and only then sees the
solution.

**Independent Test**: Launch the app with a single-position session, enter an analysis with
at least one branch, commit, and confirm the solution appears only afterward and that no
element before that point varied with correctness (quickstart scenarios 1, 2 and 3).

### Tests for User Story 1

> Write these first and confirm they fail before implementing.

- [X] T024 [P] [US1] Unit test for invariant 7 — a `TrainingProjection` built from a position with a full solution and rich metadata exposes no value derived from either — in `test/domain/training_projection_test.dart`
- [X] T025 [P] [US1] Unit tests for the single-position path of the state machine: `commitAttempt` on the only position moves `phase` to `review`, a committed `Attempt` is unaffected by later edits to the source tree (FR-015), and an empty tree is a valid attempt — in `test/domain/training_session_test.dart`
- [X] T026 [P] [US1] Widget tests for branching in `test/ui/analysis_editor_test.dart`: play four plies, step back twice, play a different move → sibling branch created with the original line intact; step back and replay the same move → navigates into the existing line with no duplicate; no dialog, snackbar or highlight appears in either case (FR-007, FR-008, FR-009)
- [X] T027 [P] [US1] Principle I guard test in `test/ui/no_feedback_guard_test.dart`: pump the training screen, play a move matching the solution and a move that does not, assert the two widget trees are identical apart from piece placement, and assert the `Chessboard` is constructed with empty `annotations` and empty `shapes` (research D8 layer 3)

### Implementation for User Story 1

- [X] T028 [P] [US1] Implement immutable `Attempt` (`positionId`, `tree`, `duration`, `committedAt`) in `lib/domain/attempt/attempt.dart`
- [X] T029 [US1] Implement `SessionPhase` and the `TrainingSession` core — `positions`, `attempts`, `phase`, `currentIndex`, `projectionFor(int)` as the only read path for training, `commitAttempt`, `allPositionsAttempted` — in `lib/domain/session/training_session.dart`
- [X] T030 [US1] Implement immutable `AnalysisEditorState` (tree, cursor `MovePath`, current `Position`, `validMoves` from `makeLegalMoves`, `isTerminal`) in `lib/ui/training/analysis_editor_state.dart`
- [X] T031 [US1] Implement the Riverpod `AnalysisEditorNotifier` play action in `lib/ui/training/analysis_editor_state.dart` — delegate to `VariationTree.play`, move the cursor to the returned path, and discard `TreeEdit.createdBranch` without surfacing it (FR-009)
- [X] T032 [US1] Add notifier actions for backward/forward/reset navigation and for promote and delete, recomputing the cursor after every structural edit (research D3), in `lib/ui/training/analysis_editor_state.dart`
- [X] T033 [US1] Build the board in `lib/ui/training/analysis_editor.dart`: `Chessboard` fed `validMoves` from `makeLegalMoves(position)` so illegal moves are unreachable (research D6), `onMove` routed to the notifier, orientation from the side to move (FR-002), explicit empty `annotations` and `shapes`, and controller disposal
- [X] T034 [US1] Add the `◀ ▶ ⟲` navigation controls to `lib/ui/training/analysis_editor.dart` (FR-006), styled identically regardless of position or move (FR-003)
- [X] T035 [US1] Implement the variation tree view — the entered structure, all branches visible, tap any node to move the cursor there (FR-010) — in `lib/ui/training/variation_tree_view.dart`, with uniform styling for every node
- [X] T036 [US1] Add promote and delete affordances for the selected branch to `lib/ui/training/variation_tree_view.dart` (FR-011, FR-013)
- [X] T037 [US1] Handle terminal positions in `lib/ui/training/analysis_editor.dart` — when `Position.isGameOver`, the branch accepts no further moves and the app says nothing about why (spec edge case)
- [X] T038 [US1] Implement `SessionController` as a Riverpod notifier holding the `TrainingSession`, exposing only `projectionFor(currentIndex)` to the training layer and a `commit` action that builds the `Attempt` with elapsed time, in `lib/ui/session/session_controller.dart`
- [X] T039 [US1] Build `TrainingScreen` consuming a `TrainingProjection` only — board, a permanent neutral turn indicator, no metadata of any kind (FR-001, FR-003) — in `lib/ui/training/training_screen.dart`
- [X] T040 [US1] Add the Done control to `lib/ui/training/training_screen.dart`, enabled with zero moves entered (FR-014) and locking the analysis on commit (FR-015)
- [X] T041 [US1] Build a minimal reveal in `lib/ui/review/review_screen.dart` showing the committed attempt and the solution tree side by side, both steppable — sufficient to make Story 1 a complete loop; the richer review arrives in Phase 5
- [X] T042 [US1] Wire the entry route in `lib/ui/app.dart` to load bundled positions and start a one-position session, replacing the Phase 2 placeholder

**Checkpoint**: The core interaction is judgeable by hand on the device. This is the plan's first device checkpoint and the point at which the product thesis can be evaluated.

---

## Phase 4: User Story 2 - Complete a multi-position session (Priority: P2)

**Goal**: A session of N positions where each commit advances straight to the next with no
interstitial, progress is visible as a plain count, review begins only after the final
commit, and abandoning forfeits the review.

**Independent Test**: Run a session of five positions, confirm no correctness information
appears at any point across the five, that commit advances with no result screen, and that
review begins only after the fifth commit (quickstart scenarios 1.6 and 6).

### Tests for User Story 2

- [X] T043 [US2] Unit tests for invariants 8 and 9 in `test/domain/training_session_test.dart`: `commitAttempt` advances `currentIndex` and keeps `phase == training` until the final position, enters `review` on the last commit and not before, and `abandon()` from any phase yields `abandoned` with no solution readable afterwards
- [X] T044 [P] [US2] Widget test in `test/ui/session_flow_test.dart`: committing position 2 of 5 renders position 3 with no intervening screen (FR-016), and the progress indicator reads "3 of 5" identically whether the prior attempts matched their solutions or not (FR-017)

### Implementation for User Story 2

- [X] T045 [US2] Extend `commitAttempt` in `lib/domain/session/training_session.dart` to advance `currentIndex` for non-final positions and transition to `review` only when `allPositionsAttempted` (FR-016, FR-018)
- [X] T046 [US2] Implement `abandon()` as a terminal transition to `SessionPhase.abandoned` that exposes no solution or metadata, in `lib/domain/session/training_session.dart` (FR-019)
- [X] T047 [US2] Populate `indexInSession` and `sessionLength` in `projectionFor` in `lib/domain/session/training_session.dart` (FR-017)
- [X] T048 [US2] Build `SessionSetupScreen` to choose the number of positions (3–10) from the bundled set and start the session, in `lib/ui/session/session_setup_screen.dart`
- [X] T049 [US2] Add the plain "N of M" progress indicator, fixed in style and position, to `lib/ui/training/training_screen.dart` (FR-017)
- [X] T050 [US2] Add abandon to `lib/ui/training/training_screen.dart` with a confirmation dialog warning that no answers will be shown, and route a confirmed abandon through `SessionController` (FR-019)
- [X] T051 [US2] Handle the training → review transition in `lib/ui/session/session_controller.dart` so review is entered only after the final commit (FR-018)
- [X] T052 [US2] Extend `test/ui/no_feedback_guard_test.dart` to assert the progress indicator's rendered widget is identical across sessions with differing attempt quality (SC-001)

**Checkpoint**: A full multi-position session runs end to end with the Phase 3 minimal reveal.

---

## Phase 5: User Story 3 - Review the session and grade yourself (Priority: P3)

**Goal**: For each position, the committed attempt and the solution shown together and
navigable, the first divergence identified, the author's notes at their moves, an advisory
match indicator, the previously withheld metadata revealed, and a self-grade recorded as the
authoritative assessment.

**Independent Test**: Complete a session, then confirm each position's review shows the
committed analysis, the solution, the divergence point, the notes and the match indicator,
records a grade, and never characterises a non-primary branch as wrong (quickstart scenario 4).

### Tests for User Story 3

- [X] T053 [P] [US3] Unit tests for invariants 4–6 in `test/domain/comparison_test.dart`: *diverged*, *ran short* and *ran long* stay distinguishable; an attempt that merely stopped early reports no divergence; the empty attempt gives `agreementLength == 0` with no divergence; `agreementLength` is capped at `solutionLength`; and adding non-primary branches to either tree changes nothing
- [X] T054 [P] [US3] Unit tests in `test/domain/grade_test.dart`: `recordGrade` stores by position id and overwrites cleanly, `allPositionsGraded` gates `complete`, `goToReviewPosition` moves freely in both directions without requiring a grade (FR-028)
- [X] T055 [P] [US3] Widget tests in `test/ui/review_screen_test.dart`: both trees render and step, the divergence is marked, solution comments appear at their moves, the match indicator reads as a measurement, metadata withheld during training is now present (FR-025), and a user branch absent from the solution carries no correct/incorrect marking (FR-024)

### Implementation for User Story 3

- [X] T056 [P] [US3] Implement immutable `Divergence` (`ply`, `playedSan`, `expectedSan`) and `ComparisonResult` (`agreementLength`, `solutionLength`, `divergence`, `ranShort`, `isComplete`) in `lib/domain/attempt/comparison.dart`
- [X] T057 [US3] Implement `compareToSolution` in `lib/domain/attempt/comparison.dart` — walk both primary lines in lockstep on `san`, stop at the first mismatch or when either runs out, never inspect non-primary branches (FR-021, FR-023, FR-024)
- [X] T058 [P] [US3] Implement `GradeValue` (`failed`, `hard`, `good`, `easy`) and immutable `Grade` in `lib/domain/session/grade.dart`
- [X] T059 [US3] Add `grades`, `recordGrade`, `allPositionsGraded`, `goToReviewPosition` and the review → complete transition to `lib/domain/session/training_session.dart` (FR-026, FR-028)
- [X] T060 [US3] Build `TreeComparisonView` in `lib/ui/review/tree_comparison_view.dart`: the attempt tree and the solution tree side by side, each navigable, sharing one board (FR-020)
- [X] T061 [US3] Add synchronised stepping through the two primary lines to `lib/ui/review/tree_comparison_view.dart`, so the board shows both sides' position at the same ply (SC-004)
- [X] T062 [US3] Mark the first divergence in `lib/ui/review/tree_comparison_view.dart`, showing the played and expected SAN at that ply (FR-021)
- [X] T063 [US3] Render solution `comments` and `nags` at their corresponding moves in `lib/ui/review/tree_comparison_view.dart` (FR-022)
- [X] T064 [US3] Build the match indicator in `lib/ui/review/match_indicator.dart`, worded as a measurement ("matched 4 of 6"), with distinct wording for *ran short* that does not read as a wrong move, and no wording for *ran long* beyond the cap (FR-023, spec edge cases)
- [X] T065 [US3] Present non-primary user branches neutrally in `lib/ui/review/tree_comparison_view.dart` — shown, navigable, and carrying no correctness marking, since without an engine there is no basis for one (FR-024)
- [X] T066 [US3] Build the metadata panel revealing `title`, `goal`, `themes`, `rating` and `source` in `lib/ui/review/review_screen.dart`, reachable only from review (FR-025)
- [X] T067 [US3] Build `GradeButtons` for the four `GradeValue`s in `lib/ui/review/grade_buttons.dart`, styled identically to each other and never preselected from the match indicator (FR-026, FR-027)
- [X] T068 [US3] Replace the Phase 3 minimal reveal in `lib/ui/review/review_screen.dart` with the full layout — comparison view, match indicator, metadata panel, grade buttons — and per-position next/previous navigation (FR-020, FR-028)
- [X] T069 [US3] Wire review state into `lib/ui/session/session_controller.dart`: compute `ComparisonResult` per position on entering review, record grades, and expose the session-complete transition (FR-027)

**Checkpoint**: All three user stories are independently functional and the loop is complete end to end.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T070 [P] Layering test asserting no file under `lib/domain/` imports `package:flutter/`, in `test/domain/layering_test.dart` (Principle IV)
- [X] T071 [P] Performance test building a 40-move, 8-branch tree and asserting `positionAt`, `play` and `primaryLine` stay within budget, in `test/domain/tree_performance_test.dart` (SC-006)
- [X] T072 [P] Audit every `ChessboardController` and Riverpod notifier created under `lib/ui/` for disposal
- [X] T073 Run `flutter analyze` and resolve every diagnostic across `lib/` and `test/`
- [X] T074 [P] Write `README.md` covering what the feature does, how to run it, and the constitution's Principle I constraint on contributions
- [X] T075 Run quickstart scenarios 1–4, 6 and 7 on the physical device and record the results in [quickstart.md](./quickstart.md)
- [X] T076 Run quickstart scenario 5 — a full five-position session in airplane mode — confirming nothing fails or degrades (FR-030, SC-003)
- [X] T077 Perform the SC-001 exhaustive audit: enumerate every element reachable during training and confirm none varies with correctness, then confirm the guard tests in `test/ui/no_feedback_guard_test.dart` cover each one

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational
- **User Story 2 (Phase 4)**: Depends on Foundational; extends the `TrainingSession` and `TrainingScreen` created in US1, so it follows US1 in practice
- **User Story 3 (Phase 5)**: Depends on Foundational; replaces the minimal reveal built in US1 (T041)
- **Polish (Phase 6)**: Depends on the stories being shipped

### User Story Dependencies

- **US1 (P1)**: Independent once Foundational is done. Delivers the MVP.
- **US2 (P2)**: Shares `training_session.dart`, `training_screen.dart` and `session_controller.dart` with US1. It is testable on its own (a five-position session with the minimal reveal) but is not file-independent from US1.
- **US3 (P3)**: The domain half (T053–T059, comparison and grades) is fully independent of US1 and US2 and can be built in parallel with either. The UI half replaces US1's T041.

### Within Each User Story

- Tests are written first and confirmed failing
- Domain types before services, services before UI
- Editor state before editor widget before training screen

### Parallel Opportunities

- T003, T004, T005 in Setup
- T007, T008, T009 (tree primitives) then T013, T014 (their tests) in Foundational
- T015, T016 (position types) and T019, T020, T022 (parser tests and fixtures) in Foundational
- All four US1 test tasks (T024–T027) together
- All three US3 test tasks (T053–T055) together
- US3's domain work (T053–T059) alongside US1 or US2 with a second developer
- T070, T071, T072, T074 in Polish

---

## Parallel Example: Foundational tree primitives

```bash
# Three independent files, no shared state:
Task: "Define error types in lib/domain/errors.dart"
Task: "Implement MovePath in lib/domain/tree/move_path.dart"
Task: "Implement MoveNode in lib/domain/tree/move_node.dart"

# Then, once VariationTree exists, its two test files in parallel:
Task: "Invariants 1-3 in test/domain/variation_tree_test.dart"
Task: "Navigation tests in test/domain/variation_tree_navigation_test.dart"
```

## Parallel Example: User Story 1 tests

```bash
Task: "Projection invariant 7 in test/domain/training_projection_test.dart"
Task: "Single-position state machine in test/domain/training_session_test.dart"
Task: "Branching widget tests in test/ui/analysis_editor_test.dart"
Task: "Principle I guard test in test/ui/no_feedback_guard_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup — a build on the phone
2. Phase 2: Foundational — the domain tree and bundled positions (CRITICAL, blocks everything)
3. Phase 3: User Story 1
4. **STOP and VALIDATE**: run quickstart scenarios 1, 2 and 3 by hand on the device

Step 4 is the point of this feature. The plan names tree navigation on a phone as the design
risk, and a one-position session with a minimal reveal is enough to judge whether withholding
feedback feels good to use. If it does not, that finding is worth more than Phases 4–6.

### Incremental Delivery

1. Setup + Foundational → domain proven by unit tests, positions loading
2. US1 → a complete single-position loop → **MVP, judge on device**
3. US2 → five-position sessions with deferred review
4. US3 → the full review with comparison, notes and self-grading
5. Polish → guard audit, offline pass, performance

### Parallel Team Strategy

Phases 1 and 2 are shared. After that, one developer can take US1 → US2 on the UI path while
a second takes US3's domain work (T053–T059), which touches no US1 or US2 file. The US3 UI
tasks (T060–T069) must wait for US1's review screen to exist.

---

## Notes

- `TreeEdit.createdBranch` must never reach a widget. It exists for T013 and nothing else.
- `projectionFor` is the only permitted read path from the training layer into a position. A
  task that needs more than `TrainingProjection` carries is a task that has gone wrong.
- Commit after each task or logical group; stop at any checkpoint to validate independently.
- Steps in Phases 2 and 5's domain half need no device and can proceed while the phone is
  disconnected.
