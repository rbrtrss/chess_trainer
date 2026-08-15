---

description: "Task list for 005: positions with no author's line"
---

# Tasks: Positions With No Author's Line

**Input**: Design documents from `/specs/005-engine-judged-positions/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/evaluation-api.md](./contracts/evaluation-api.md)

**Tests**: included, and not optional. The constitution's Principle V requires them, and this
feature adds the strongest source of correctness the app has ever held — the guard tests are not
housekeeping here, they are the thing that keeps Principle I true.

**Organization**: grouped by user story. Note the priorities: **US1 and US3 are both P1**, US2 is
P2, so the phases run US1 → US3 → US2 rather than in numeric order. A version of US1 that leaks is
not a lesser version, it is one that must not ship.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel — different files, no dependency on an unfinished task
- **[Story]**: which user story the task serves (US1, US2, US3)
- Every task names the file it touches

## Path Conventions

Single Flutter module. `lib/domain/`, `lib/data/`, `lib/ui/`, tests mirroring them under `test/`.

**Run `dart run build_runner build --delete-conflicting-outputs` after any task touching
`lib/data/local/tables.dart` or `lib/data/local/database.dart`.** Generated files are gitignored.

---

## Phase 1: Setup — the gate, and it passed

**Purpose**: establish the baseline, and answer the one question a build could not.

Both costs are now known. Size was measured before the dependency was adopted: 34.9 MB → 79.7 MB
per install. Seconds per position was measured on the phone on 2026-08-15: **257 ms at depth 12**,
worst of five representative positions. **D2's design survives contact with hardware** and its
fallback is not needed (research D10).

- [X] T001 Run `flutter test` and `dart analyze` on `005-engine-judged-positions` and record that both are clean — every later "still green" claim is relative to this
- [X] T002 Measure the engine on the target device — **done 2026-08-15 on the TECNO KJ6**. Five positions, four depths, `Threads` at 1; worst case 43 ms at depth 8, 257 ms at 12, 1.25 s at 16, 2.6 s at 20. Full table in [research.md](./research.md) D10. The harness was a throwaway entrypoint and is deleted
- [X] T003 **Depth 12, principal variation capped at 12 plies**, recorded in [contracts §4](./contracts/evaluation-api.md#4-fixed-values). Chosen on the worst case rather than the mean — 257 ms against a mean of 87 — because an import is only as fast as its slowest entry. **The gate is passed and D2's fallback is not needed**: depth 16 would have cost 1.25 s per position and put a hundred-position import over two minutes

**Checkpoint**: the feature's cost is fully known and accepted — 44.8 MB of install and about a quarter of a second per hand-made position. Nothing has been built yet, which is the point.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the domain types, the seam, the schema, and the confinement rules. Every user story
needs these, and none can start until they are done.

**⚠️ CRITICAL**: no user story work begins until Phase 2 is complete.

**The layering rule lands here, before the engine implementation exists** — the same ordering
feature 003 used for its Principle I guards, so the rule is in place before the temptation is.

- [X] T004 [P] Create `lib/domain/position/evaluation.dart` — `SolutionSource`, the sealed `Score` with `Centipawns` and `MateIn`, and `PositionEvaluation` carrying score, depth and perspective, per [contracts §1](./contracts/evaluation-api.md). Pure Dart, no engine types
- [X] T005 Add `solutionSource` and the optional `evaluation` to `TrainingPosition` in `lib/domain/position/training_position.dart`, and **add neither to `TrainingProjection`** — the type the training screen consumes gains nothing in this feature
- [X] T006 Create `lib/data/engine/evaluator.dart` — the `Evaluator` interface and `EngineLine`, per [contracts §2](./contracts/evaluation-api.md). `bestLine` returns null rather than throwing, because one position upsetting the engine must not cost an import its other entries
- [X] T007 [P] Create `test/data/engine/fake_evaluator.dart` — returns canned lines, can be told to return null, and records what it was asked. Every test in this feature uses it; none can use the real engine (research D8)
- [X] T008 Add `solution_source`, `evaluation_json` and `engine_id` to the `positions` table in `lib/data/local/tables.dart` per [data-model.md](./data-model.md#stored-schema-v3)
- [X] T009 Raise `schemaVersion` to 3 in `lib/data/local/database.dart` and add the v2 → v3 migration: add the three columns, set every existing row to `author`, touch nothing else
- [X] T010 Extend `test/data/migration_test.dart` and add `test/generated/schema_v3.dart` plus the `drift_schemas/drift_schema_v3.json` dump, asserting a v2 database with played sessions upgrades with its history intact and every existing position reading as `author` (FR-021, FR-022). **The existing v1 tests had to move with it**: once the app is at v3, `createTable` builds v3 tables, so a v1 database can never validate against the v2 snapshot — they now validate against the current version, which is the assertion that was always worth making
- [X] T011 Read and write the three new columns in `lib/data/local/drift_collection_repository.dart`, and extend `test/data/collection_repository_test.dart` with a round trip that keeps an engine-sourced solution, its evaluation and its engine id intact
- [X] T012 Add a rule to `test/domain/layering_test.dart`: nothing outside `lib/data/engine/` imports `package:multistockfish`, and `lib/domain/` and `lib/ui/` never import `data/engine/`. Written now, before the implementation exists (research D7, Constitution III)

**Checkpoint**: the app behaves exactly as it did, with an unused seam, a schema that can hold an evaluation, and a rule that stops the engine escaping the one directory it belongs in.

---

## Phase 3: User Story 1 — Train a position I set up myself (Priority: P1) 🎯 MVP

**Goal**: a study chapter with a position and no moves imports as a trainable position.

**Independent test**: import a study containing one chapter with a position and no moves, and
confirm a session can be started on it and completed.

- [X] T013 [US1] In `lib/domain/library/import_outcome.dart`, retire `RejectionReason.noMoves` and add `noLegalMoves`. Removing the old value rather than leaving it unused means nothing can produce it by accident
- [X] T014 [US1] In `lib/data/pgn_position_parser.dart`, stop throwing on an entry with no moves, and reject a position with no legal move as `noLegalMoves` — **asking `dartchess`, never the engine** (research D9, and now Constitution III: the engine must not be consulted about anything dartchess can answer)
- [X] T015 [P] [US1] Extend `test/data/pgn_position_parser_test.dart`: a `[FEN]` with no moves now parses; checkmate and stalemate are rejected with the new reason; every other rejection is unchanged (FR-002, FR-003, SC-003)
- [X] T016 [US1] In `lib/data/import_parser.dart`, carry entries that need an evaluation through to the import service rather than dropping them
- [X] T017 [US1] Add the evaluation step to `lib/data/import_service.dart` — **plus an `ImportEvaluating` progress state**, not in the original task: a search costs about a quarter of a second per position, and leaving "Reading 12 of 12" on screen while the engine works would have the app claiming to do something it finished seconds ago: for each entry with no author's line, ask the injected `Evaluator`, store the returned line as the position's `solution` with `SolutionSource.engine`, and store `SolutionSource.none` with an empty solution when it returns null (research D3, FR-007, FR-010)
- [X] T018 [P] [US1] Create `test/data/evaluation_import_test.dart` covering [contract invariants 1–4](./contracts/evaluation-api.md#6-invariants-the-tests-hold): a no-moves entry becomes a position; a terminal position is rejected **and the evaluator is never asked about it**; an evaluator returning null leaves the rest of the import untouched and that entry trainable
- [X] T019 [US1] Make the import report describe an accepted no-moves entry as accepted — **no change was needed**, and that is research D3 paying off: the report counts positions and an engine-judged one is a position, so nothing in it could single one out. Proved by T020 rather than assumed (FR-005, FR-006)
- [X] T020 [P] [US1] Add to `test/ui/import_flow_test.dart`: a source mixing authored and no-line entries reports both as imported, and singles out neither
- [X] T021 [US1] Create `lib/data/engine/stockfish_evaluator.dart` — the one class that speaks UCI, with `Threads` at 1, depth 12, the 12-ply PV cap, and an `engineId` naming the engine, its version and the budget ([contracts §3](./contracts/evaluation-api.md)). **Every failure path yields `null`, never a pending future**: a time-boxed start, a per-position timeout, a crashed process. A hung start was actually seen on this phone on 2026-08-15 — see the contract — and an import that hangs is worse than one reporting a position it could not evaluate
- [X] T022 [US1] Dispose the engine when an import finishes, in `lib/data/engine/stockfish_evaluator.dart` and its caller. The package permits one instance at a time, and an engine left running after an import is an engine running while the next session starts — which Constitution III now forbids outright
- [X] T023 [US1] Provide the evaluator to the import service in `lib/ui/library/library_controller.dart`, keeping construction of the implementation to that one place, as `connection_controller.dart` does for the Lichess client
- [ ] T024 [US1] Verify on device: quickstart scenario 1 — import **"Probando probando"**, the study that prompted this feature and that on 2026-08-15 imported as "1 of the 1 entries could not be used". It must now import as one trainable position, and a session on it must run to review
- [ ] T025 [US1] Verify on device: quickstart scenario 3 — what is still refused. No `[FEN]`, a non-standard variant, illegal moves, and a checkmate position, each rejected with its reason in words

**Checkpoint**: the feature's central request is answered. A position set up by hand is trainable, and the engine supplied the standard.

---

## Phase 4: User Story 3 — Nothing waits, and nothing leaks (Priority: P1)

**Goal**: the player cannot tell, from anything the app does, which positions were judged by an
engine — and never waits for one.

**Why this phase comes before US2**: it is P1, and US1 must not ship without it. This is the
constitution's non-negotiable principle applied to the most dangerous thing the app has ever
contained.

**Independent test**: train a session mixing engine-judged and author-lined positions with the
device offline, and confirm every screen, every wording and every timing is indistinguishable.

- [X] T026 [US3] Extend the training-directory rule in `test/domain/layering_test.dart` with `SolutionSource`, `PositionEvaluation`, `Score`, `Evaluator`, `EngineLine` and `stockfish` — the account joined this list in 004 for the same reason (FR-020)
- [X] T027 [P] [US3] Create `test/ui/no_engine_during_session_test.dart` — drive setup, training, every commit, review and resume against an `Evaluator` that **fails the test on contact**, with a control case proving it would fire if called. This is the structural half of FR-019 and it is modelled exactly on `no_network_during_training_test.dart`, which is the test that replaced 003's lost offline guarantee
- [X] T028 [P] [US3] Add to `test/ui/no_feedback_guard_test.dart`: a session mixing an engine-judged and an authored position renders identically on the training screen — same widget tree, same semantics, same wording — compared through what a screen reader would announce rather than by eye (FR-016, SC-004)
- [X] T029 [P] [US3] Add to `test/ui/no_feedback_guard_test.dart`: no evaluation, score, depth, best move or the word "engine" is reachable from the training screen's widget tree or its semantics, for a position that has all of them stored (FR-018, SC-010)
- [X] T030 [US3] Add to `test/ui/no_network_during_training_test.dart`: an engine-judged position trains and reviews with the Lichess client still failing on contact — this feature adds no network path, and that is worth asserting rather than assuming (FR-008, SC-006)
- [ ] T031 [US3] Verify on device: quickstart scenario 6 — with a session open, `adb shell top` shows **no engine process at all**. Not idle, absent. This is what makes FR-017 structural rather than careful
- [ ] T032 [US3] Verify on device: quickstart scenario 4 — dump what a screen reader would announce on the training screen for both kinds of position and confirm they are indistinguishable, then time the gap between committing and the next position appearing for each (SC-005)

**Checkpoint**: the engine is invisible from the training screen, provably and on hardware. US1 is now safe to ship.

---

## Phase 5: User Story 2 — See what the engine made of it, at review (Priority: P2)

**Goal**: at review, the player is shown the engine's line, what it thought, and where their own
line parted from it — and is told which kind of solution they are looking at.

**Independent test**: review a completed session containing one engine-judged position and confirm
the engine's line, the evaluation, and the standing of the player's own line are all shown, and
that the player can still grade themselves.

**Note**: most of this story is already built. `compareTrees` reports where two lines part
company, and the review panes already render a solution — that is research D3 paying off. What is
left is honesty about provenance.

- [X] T033 [US2] In `lib/ui/review/tree_comparison_view.dart`, say where the solution came from when it came from an engine, and show the evaluation of the starting position — and show neither for an authored position (FR-012, FR-014, FR-015)
- [X] T034 [US2] Distinguish the two empty cases in `lib/ui/review/tree_comparison_view.dart`: an author who recorded no solution, and an engine that could not produce one. The existing "No solution was recorded." covers only the first (research D6, FR-010)
- [X] T035 [P] [US2] Add to `test/ui/review_screen_test.dart`: an engine-judged position shows the engine's line, its evaluation and its provenance; the comparison still reports where the player's line parted; the grade buttons behave identically (FR-013, FR-014)
- [X] T036 [P] [US2] Add to `test/ui/review_screen_test.dart`: an authored position's review is byte-identical to what it was before this feature, and a `SolutionSource.none` position reviews to the distinct empty message rather than a blank pane (FR-015, SC-009)
- [ ] T037 [US2] Verify on device: quickstart scenario 5 — review a session containing both kinds and confirm the engine's line, the evaluation and the provenance are shown for one and absent from the other

**Checkpoint**: all three user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

The first two tasks are corrections the constitution's amendment review identified: two comments
in the source explain a rule by asserting that no engine exists. After this feature they are
false, and a false comment is worse than none.

- [ ] T038 [P] Correct the comment in `lib/domain/attempt/comparison.dart` — "no engine evaluates anything here, so this type can say where two lines parted company and nothing whatever about which was better". The rule it explains is unchanged; the reason is not. The self-grade now outranks the comparison **by choice rather than by incapacity**
- [ ] T039 [P] Correct the comment in `lib/ui/review/grade_buttons.dart` — "without an engine there is nothing here that could make that suggestion honestly". An engine now exists and still must not make that suggestion, which is a stronger statement and needs saying
- [ ] T040 [P] Record in `specs/003-position-import/spec.md` that FR-006's "no moves at all" clause is superseded by 005 FR-001, so a later reader is not misled by a requirement the app deliberately stopped honouring
- [ ] T041 [P] Update `README.md`: the app now judges positions an author left unsolved, it carries an engine, what that cost in install size, and that the engine never runs while a session does
- [ ] T042 Run `dart analyze` and `flutter test` — both clean, and the suite larger than the T001 baseline
- [ ] T043 Verify on device: quickstart scenario 7 — import twenty hand-made positions and time it, recorded beside 003's figure of 330 authored positions in under three seconds. Starting a session must never wait on any of it (SC-007)
- [ ] T044 Verify on device: quickstart scenario 8 — with airplane mode on, import a **file** containing a no-moves position, then train and review it. The engine's line is there and no network was needed at any point
- [ ] T045 Verify on device: quickstart scenario 9 — a build whose evaluator returns null: the position still imports, is still trainable, and its review says no evaluation could be produced (FR-010, SC-009)
- [ ] T046 Verify on device: quickstart scenario 10 — install over a 004 build and confirm collections, positions and sessions survive and every existing position reads as `author` (FR-021, FR-022)
- [ ] T047 Append "What was done, and what was not" to this file, recording what the device pass found, what was left unverified and why — the convention features 003 and 004 both used, and the reason their records are worth reading

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: no dependencies, and **T002–T003 gate the whole design**
- **Foundational (Phase 2)**: depends on Setup — **blocks every user story**
- **US1 (Phase 3)**: depends on Foundational
- **US3 (Phase 4)**: depends on US1 — it asserts things about positions that must first exist.
  **US1 does not ship without it**; they are one release, not two
- **US2 (Phase 5)**: depends on US1 for something to review
- **Polish (Phase 6)**: depends on everything it asserts about

### Task dependencies worth naming

- T003 depends on T002 — the depth is chosen from a measurement, not from taste
- T017 depends on T006 and T007: the import step is built and tested against the interface and the
  fake, with no engine anywhere near it
- T021 and T022 are the only tasks that cannot be verified off-device — they are the one class that
  speaks to the engine — which is why they are late, small, and followed immediately by T024
- T027 depends on T017 — there must be an evaluator in the import path for its absence during a
  session to mean anything
- T033 and T034 both edit `tree_comparison_view.dart`, so they are sequential
- T042 depends on every code task; T043–T046 depend on T042

## Parallel Example: Phase 2

```bash
# Independent files:
Task: "Create lib/domain/position/evaluation.dart"        # T004
Task: "Create test/data/engine/fake_evaluator.dart"       # T007
# then, once the interface exists:
Task: "Add the three columns to tables.dart"              # T008
```

## Parallel Example: US3's guards

```bash
# Three test files, none of which the others touch:
Task: "Create test/ui/no_engine_during_session_test.dart" # T027
Task: "Extend no_feedback_guard_test.dart — identical"    # T028
Task: "Extend no_feedback_guard_test.dart — unreachable"  # T029
```

## Implementation Strategy

**Phase 1 is a gate, not a formality.** If a usable search depth costs more than a second or two
per position, the design changes before anything is built on it, and D2's recorded fallback is
where to go. That is the whole reason it is first.

**MVP is Phase 1 + Phase 2 + US1 + US3** (T001–T032). Note that this is *two* user stories, not
one: US3 is P1 because a version of US1 that leaks correctness is not a lesser version, it is one
that must not ship. At that point a hand-made position is trainable, the engine supplied the
standard, and the engine is provably invisible from the training screen.

**Increment 2 is US2** (T033–T037): review admits where the line came from. Small, because
research D3 arranged for the review to need almost nothing.

**Phase 6 last**, and its first three tasks are corrections to things this feature makes untrue —
two comments in the source and one clause in feature 003's specification. Leaving them would mean
the repository asserts, in three places, something the code no longer does.

### The two things no test can cover

`stockfish_evaluator.dart` (T021) cannot be exercised off-device, because the package supports
Android and iOS only. And nothing in `flutter test` can see latency, battery or heat, which are
the channels an engine actually leaks through. Both are why T031 and T032 exist, and why they are
not optional.
