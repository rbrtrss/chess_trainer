---

description: "Task list for Session Persistence"
---

# Tasks: Session Persistence

**Input**: Design documents from `/specs/002-session-persistence/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/storage-api.md](./contracts/storage-api.md), [quickstart.md](./quickstart.md)

**Tests**: Test tasks are included and are **not optional here**. Constitution Principle V
carries over from feature 001, and this feature's plan adds five named obligations of its own:
repository round-trip tests, an atomic-commit test, a resume-fidelity test, a migration
harness, and the two Principle I guards. Invariant numbers below refer to
[contracts/storage-api.md](./contracts/storage-api.md), "Invariants the tests must enforce".

**Organization**: Tasks are grouped by user story so each can be implemented, tested, and
judged on a device independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Exact file paths are given in every task

## Path Conventions

Single Flutter module at the repository root (`/home/roberto/chess_trainer`), with the
constitution's three layers as top-level directories under `lib/`. Drift is confined to
`lib/data/local/`; nothing outside that directory learns that SQLite exists. All paths below
are repository-relative.

**New build step**: after Phase 2, `flutter test` and `flutter run` fail on a fresh clone
until `dart run build_runner build --delete-conflicting-outputs` has been run (research D8).
Generated `*.g.dart` files are gitignored on purpose.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies and the build step that code generation introduces.

- [X] T001 Add persistence dependencies to `pubspec.yaml` — `drift: ^2.34.3` and `drift_flutter: ^0.3.1` under `dependencies`, `drift_dev: ^2.34.5` and `build_runner: ^2.16.0` under `dev_dependencies`, each with the licence comment the file's house style uses (all MIT, GPL-3.0 compatible) — then run `flutter pub get` and record the resolved versions. **Do not add `sqlite3_flutter_libs`**: it resolves to `0.6.0+eol` and arrives transitively as a no-op, and adding it reintroduces the Flutter build scripts the package exists to retire (research, "A trap worth naming")
- [X] T002 [P] Confirm `.gitignore` keeps generated code out (`*.g.dart` and `*.drift.dart` are already listed) and add an explicit note that `drift_schemas/` is **committed on purpose** — the schema snapshots are inputs to the migration test in T055, not build output
- [X] T003 [P] Add the code-generation step to `README.md` under the build instructions: `flutter pub get` then `dart run build_runner build --delete-conflicting-outputs`, with the symptom it fixes (`Target of URI hasn't been generated: 'database.g.dart'`) named, per research D8

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The schema, the tree codec, and the repository surface. Both user stories read
and write through the same repository, so neither can start until this phase is done. This is
plan steps 1 and 2, and it needs no device.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Domain and codec

- [X] T004 [P] Define `SessionStatus` (`inProgress`, `complete`, `abandoned`) and the immutable `SessionRecord` (`id`, `startedAt`, `endedAt`, `status`, `IList<String> positionIds`, value equality) in `lib/domain/session/session_record.dart`, with the dartdoc note from data-model.md explaining why the live `SessionPhase` values `setup`, `training` and `review` are deliberately not persisted
- [X] T005 [P] Add `TreeDecodeError` to `lib/domain/errors.dart` alongside `PositionParseError`, documented as "stored PGN that this app cannot replay"
- [X] T006 Implement `encodeTree(VariationTree)` and `decodeTree(String)` in `lib/data/pgn_position_parser.dart`, built on the existing `toPgnNode` / `fromPgnNode` codec (research D2): write a PGN with a `[FEN]` header so the stored row is self-describing, replay it back through `fromPgnNode`, and throw `TreeDecodeError` on a missing/invalid FEN header or an illegal move
- [X] T007 [P] Codec tests in `test/data/tree_codec_test.dart` — invariant 9: a tree of at least 40 moves across 8 branches survives `encodeTree`/`decodeTree` unchanged, including comments, NAGs, and which sibling is primary at every branch point; plus `TreeDecodeError` on garbage text and on a PGN with no `[FEN]` header. Build the fixture with the helpers in `test/domain/tree_helpers.dart`

### Schema

- [X] T008 [P] Define the four Drift tables in `lib/data/local/tables.dart` per data-model.md — `Sessions` (`id` TEXT PK, `startedAt` INT, `endedAt` INT?, `status` TEXT, `currentIndex` INT), `SessionPositions` (PK `(sessionId, ordinal)`, `positionId`, `initialFen`, `solutionPgn`, `metadataJson`), `Attempts` (PK `(sessionId, positionId)`, `treePgn`, `durationMs`, `committedAt`), `Grades` (PK `(sessionId, positionId)`, `value`, `gradedAt`) — with foreign keys to `sessions.id`
- [X] T009 Define `AppDatabase` in `lib/data/local/database.dart` — `@DriftDatabase(tables: [...])`, `schemaVersion = 1`, a `MigrationStrategy` whose `onCreate` creates the tables and then the **partial unique index** `CREATE UNIQUE INDEX one_session_in_progress ON sessions(status) WHERE status = 'in_progress'` (FR-010, research D7), a production constructor over `driftDatabase(name: 'chess_trainer')`, and an `AppDatabase.memory()` constructor over `NativeDatabase.memory()` for tests
- [X] T010 Run `dart run build_runner build --delete-conflicting-outputs`, confirm `lib/data/local/database.g.dart` is produced and gitignored, and confirm `flutter analyze` is clean (depends on T008, T009)

### Repository surface

- [X] T011 Define the storage contract in `lib/data/session_repository.dart` — the `SessionRepository` abstract interface exactly as in [contracts/storage-api.md](./contracts/storage-api.md), the immutable `StoredSession` (`record`, `positions`, `attempts`, `grades`, `answersForfeited`) and `PositionSnapshot` (`positionId`, `ordinal`, `initialPosition`, nullable `solution`, nullable `metadata`), and the errors `SessionAlreadyInProgressError` and `StorageWriteError`. Keep the contract's comment explaining why there is deliberately **no** history repository
- [X] T012 Implement `DriftSessionRepository` in `lib/data/local/drift_session_repository.dart` — the class, its `AppDatabase` dependency, the row ⇄ domain mappers, and the `PositionMetadata` ⇄ JSON codec (title, goal, themes, rating, source). UTC epoch on the way in, `DateTime` on the way out (data-model.md, "Stored schema")
- [X] T013 Implement `start(IList<TrainingPosition> positions, {DateTime? now})` in `lib/data/local/drift_session_repository.dart` — in **one transaction**, insert the session row as `in_progress` at index 0 and one `session_positions` row per position snapshotting `initial_fen`, `solution_pgn` (via `encodeTree`) and `metadata_json` (research D4). Throw `SessionAlreadyInProgressError` when the partial unique index rejects the insert (FR-010)
- [X] T014 Implement `loadInProgress()` in `lib/data/local/drift_session_repository.dart` — return the unfinished session with its snapshots, attempts and grades, or **null**; catch `TreeDecodeError` and any malformed row and return null rather than propagating, because unreadable stored data is treated as absent (FR-023, research D10)
- [X] T015 [P] Test harness in `test/data/repository_harness.dart` — an `AppDatabase.memory()` fixture with `addTearDown` closing, a `DriftSessionRepository` over it, sample `TrainingPosition`s with rich solutions and metadata, and a helper to read raw rows for the tests that need to bypass application logic
- [X] T016 Round-trip tests in `test/data/session_repository_test.dart` — invariant 1: a session written and read back is equal to what was written, across record, snapshots, attempts and grades, including branches and which line is primary in every stored tree
- [X] T017 One-in-progress tests in `test/data/session_repository_test.dart` — invariant 4: `start` throws `SessionAlreadyInProgressError` while a session is unfinished, **and** a raw insert of a second `in_progress` row through the harness is rejected by the database index, so the constraint holds even when application logic is bypassed (research D7)
- [X] T018 Corrupt-data tests in `test/data/session_repository_test.dart` — invariant 8: with a truncated `solution_pgn`, an unparseable `initial_fen`, and a session row whose snapshots are missing, `loadInProgress` returns null and does not throw (FR-023)
- [X] T019 Wire the repository into the app in `lib/ui/session/session_controller.dart` and `lib/main.dart` — a `sessionRepositoryProvider` beside the existing `bundledPositionsProvider` (the house style keeps Riverpod providers in `lib/ui/`, so the data layer stays Flutter-free), opening one `AppDatabase` for the app's lifetime and closing it on dispose. Tests override this provider with the memory-backed repository from T015

**Checkpoint**: The schema, the codec and the repository's read/write core are proven against
an in-memory database with no device attached. User story work can begin.

---

## Phase 3: User Story 1 - Resume an interrupted session (Priority: P1) 🎯 MVP

**Goal**: A session killed mid-flight comes back at the right position with every committed
attempt intact, and the training screen looks exactly as it would have had nothing happened.

**Independent Test**: Start a five-position session, commit two, enter a branching analysis on
the third, kill the app with `adb shell am force-stop`, reopen it, and confirm the session
resumes at position three of five with both committed attempts kept, the board back at the
starting position, and nothing revealed (quickstart scenarios 1, 2, 3 and 7).

**Design note on FR-003 vs SC-003**: the player must be told that the analysis in progress was
not kept (FR-003), and the resumed training screen must be byte-identical to a fresh one
(SC-003). Both hold only if the notice lives in the **resume flow** — the prompt that offers to
continue — and not as an element of the training screen. T031 places it there deliberately, and
T035 compares the two screens after the prompt is dismissed.

### Tests for User Story 1

> Write these first and confirm they fail before implementing.

- [X] T020 [US1] Atomicity test in `test/data/session_repository_test.dart` — invariant 2: a failure injected part way through `commitAttempt` leaves the session with **neither** the attempt nor the advanced index, never one without the other. The state to prove impossible is "index past a position that has no attempt", which is unrecoverable because `allPositionsAttempted` can never become true (FR-005, research D6)
- [X] T021 [US1] Resume-fidelity storage test in `test/data/session_repository_test.dart` — invariant 3: after committing two of five positions, `loadInProgress` returns both attempts, `currentIndex == 2`, and **no** attempt for the position in progress, because nothing was stored for it (FR-003, FR-007)
- [X] T022 [US1] Grading and abandonment storage tests in `test/data/session_repository_test.dart` — invariant 5: `recordGrade` twice for the same position in the same session leaves exactly one grade holding the later value (FR-017); invariant 6 (storage half): `abandon` deletes the attempts and grades and keeps the session row as `abandoned` (FR-016)
- [X] T023 [P] [US1] Resume widget tests in `test/ui/resume_test.dart` — with a memory-backed repository seeded with an unfinished session: the setup screen offers to continue, continuing lands on the stored position with the stored count and the stored attempts present, declining discards under the warning, and a completed or abandoned stored session is **not** offered (FR-006, FR-007, FR-009, FR-011)

### Implementation for User Story 1

- [X] T024 [US1] Implement `commitAttempt(String sessionId, Attempt attempt)` in `lib/data/local/drift_session_repository.dart` — in **one transaction**: insert the attempt row (tree via `encodeTree`), advance `current_index`, and set `status = 'complete'` with `ended_at` when it was the last position (FR-005, research D6)
- [X] T025 [US1] Implement `recordGrade(String sessionId, Grade grade, {DateTime? now})` in `lib/data/local/drift_session_repository.dart` as an upsert on `(session_id, position_id)`, overwriting value and `graded_at` in place with no earlier grade retained (FR-017)
- [X] T026 [US1] Implement `abandon(String sessionId)` and `discardInProgress()` in `lib/data/local/drift_session_repository.dart` — delete attempts and grades, set the session row to `abandoned` with `ended_at`, keep the snapshot rows. `discardInProgress` is `abandon` applied to the unfinished session; both exist so the caller's intent is legible (FR-011, FR-016)
- [X] T027 [US1] Wrap every write path in `lib/data/local/drift_session_repository.dart` so a failed write raises `StorageWriteError` rather than a Drift exception — a failed *read* is swallowed (T014), a failed *write* never is, because the one thing that must not happen is the player believing their work was stored (FR-024, research D10)
- [X] T028 [US1] Change `SessionController` in `lib/ui/session/session_controller.dart` to write through `sessionRepositoryProvider`: `start`, `commit`, `recordGrade` and `abandon` become async and await the corresponding repository call before updating state, and a `StorageWriteError` is surfaced to the player rather than swallowed (FR-002, FR-024). The in-memory `TrainingSession` remains the source of truth for the live screen
- [X] T029 [US1] Add `resumeCandidateProvider` (a `FutureProvider<StoredSession?>` over `loadInProgress`) to `lib/ui/session/session_controller.dart`, resolving null both when there is nothing to resume and when stored data is unreadable (FR-006, FR-023)
- [X] T030 [US1] Add `SessionController.resume(StoredSession stored)` to `lib/ui/session/session_controller.dart` — rebuild the `TrainingPosition` list from the snapshots (`initialFen`, `solutionPgn`, `metadataJson`), and construct a `TrainingSession` in `SessionPhase.training` at the stored `currentIndex` with the stored attempts and grades, or in `SessionPhase.review` when every position is already attempted (FR-007)
- [X] T031 [US1] Build the resume prompt in `lib/ui/session/resume_prompt.dart` — "Continue" and "Start fresh", and the FR-003 notice that the analysis in progress was not kept, worded so an empty board reads as a known consequence rather than as lost work. This is the only place that notice appears; see the design note above
- [X] T032 [US1] Change `lib/ui/session/session_setup_screen.dart` to show the resume prompt when `resumeCandidateProvider` yields a session, and to warn before starting a new one while an unfinished session exists — that the unfinished session is discarded and its answers forfeited, **in the same words as abandoning** — discarding via `discardInProgress` on confirmation and leaving it untouched on decline (FR-010, FR-011)
- [X] T033 [US1] Gate the first frame on the resume lookup in `lib/ui/session/session_flow.dart` — while `resumeCandidateProvider` is loading, show the setup screen's loading state rather than a flash of a session-less setup screen; the resumed session must be on screen within three seconds of launch (SC-002)
- [X] T034 [US1] Add `pumpResumedTrainingScreen` to `test/ui/editor_harness.dart` — pumps the real training screen over a session restored through `SessionController.resume` from a memory-backed repository, so the guard test in T035 compares the app's actual resume path rather than a stub
- [X] T035 [US1] Extend `test/ui/no_feedback_guard_test.dart` with invariant 11 — a resumed training screen renders identically to a fresh one at the same point, compared with the existing `renderSnapshot` and `boardSnapshot` helpers, run both after a matching move and after a diverging one (FR-008, SC-003)
- [X] T036 [US1] Add invariant 10 to `test/domain/layering_test.dart` — no file under `lib/ui/training/` references `Grade`, `GradeValue`, `SessionRecord`, `StoredSession`, `SessionRepository`, or any provider derived from them. Nothing displays history today; the rule exists so that the storage this feature creates cannot quietly grow a display later (FR-019, research D5)
- [X] T037 [US1] Keep the existing network rule in `test/domain/layering_test.dart` honest now that `lib/` contains generated code — confirm it still passes over `lib/data/local/` including `database.g.dart`, and if drift's generated output trips the `dart:io` check, narrow the rule to hand-written files with the reason recorded in the test's dartdoc rather than deleting the check
- [X] T038 [US1] **Device checkpoint**: run quickstart scenarios 1 (a killed session comes back), 2 (interruption at the worst moment), 3 (nothing leaks across a restart) and 7 (one session at a time) on the physical device, killing the app with `adb shell am force-stop dev.chesstrainer.chess_trainer`

  > **Passed on device (2026-08-13, TECNO KJ6, Android 15)**: scenario 1 — committed position 1, entered `1. Nxc6` on position 2, `adb shell am force-stop`, reopened → offered "Position 2 of 3, 1 answer committed" with the not-kept notice; continuing landed on position 2 with the board at its starting point and the earlier attempt intact; committing the rest reached review with all three. Scenario 2 — Done raced against a kill at 0s / 0.08s / 0.2s / 0.35s gave `(index 0, 0 attempts) → (1,1) → (2,2) → complete/3`; the forbidden "index past an unattempted position" never occurred. Scenario 3 — the resumed screen was indistinguishable from a fresh one. Scenario 7 — the discard warning appeared in the same words as abandoning, and after confirming, the database held exactly one `in_progress` row beside one `complete` and one `abandoned`.

**Checkpoint**: The pain feature 001 knowingly left behind is gone, and the two Principle I
guards are in place *before* history exists — which is the point of doing them here.

---

## Phase 4: User Story 2 - Look back at a finished session (Priority: P2)

**Goal**: Finished sessions stay findable and readable, showing the review exactly as it was
at the time, and grades can be revised from it.

**Independent Test**: Complete a session, close the app, reopen it, open the history, open that
session, and confirm the review content is identical to what was shown when the session ended
(quickstart scenarios 5 and 6).

### Tests for User Story 2

> Write these first and confirm they fail before implementing.

- [X] T039 [US2] History listing tests in `test/data/session_repository_test.dart` — `listSessions` returns finished sessions newest first, honours `limit` and `offset`, and includes abandoned sessions alongside completed ones (FR-013)
- [X] T040 [US2] Snapshot-fidelity test in `test/data/session_repository_test.dart` — invariant 7: a completed session reopened *after* the bundled positions have changed under it still yields the solution, notes and metadata it was run against, because the session carries its own copy (FR-015, SC-005, research D4)
- [X] T041 [US2] Abandoned-session read test in `test/data/session_repository_test.dart` — invariant 6 (read half): `loadSession` for an abandoned session returns snapshots whose `solution` and `metadata` are **null**, so the answers are absent from the returned record rather than merely hidden by the UI, and `answersForfeited` is true (FR-016)
- [X] T042 [US2] Deletion test in `test/data/session_repository_test.dart` — `deleteEverything` removes every session, snapshot, attempt and grade, and leaves a usable database that a new session can start against (FR-018)
- [X] T043 [P] [US2] History widget tests in `test/ui/history_screen_test.dart` — the list shows each past session's date and position count; opening a completed one shows its review with the stored analysis, solution, divergence, notes and grade; an abandoned one is shown as abandoned and reveals no solution, note or metadata for any of its positions; re-grading from a past review replaces the grade; and delete-everything warns before it acts (FR-013, FR-014, FR-016, FR-017, FR-018)

### Implementation for User Story 2

- [X] T044 [US2] Implement `listSessions({int limit, int offset})` in `lib/data/local/drift_session_repository.dart` — finished sessions newest first as `IList<SessionRecord>`, reading only the `sessions` table and its position ids so that opening the history does not load every snapshot (FR-013, SC-009)
- [X] T045 [US2] Implement `loadSession(String id)` in `lib/data/local/drift_session_repository.dart` — the full `StoredSession` for a known id and null for an unknown one, **stripping `solution` and `metadata` from every snapshot when the session is abandoned** (FR-014, FR-016)
- [X] T046 [US2] Implement `deleteEverything()` in `lib/data/local/drift_session_repository.dart` in one transaction across all four tables (FR-018)
- [X] T047 [US2] Add `sessionHistoryProvider` (the list) and `pastSessionProvider` (a family over session id) to `lib/ui/session/session_controller.dart`, plus a converter that turns a `StoredSession` into a `TrainingSession` in `SessionPhase.complete` at index 0 with its attempts and grades — this is what lets the past review reuse the existing review screen rather than growing a second one
- [X] T048 [US2] Build `lib/ui/history/history_screen.dart` — past sessions newest first, each showing when it happened in the device's local time and how many positions it had, with abandoned ones labelled as abandoned. Paged off `listSessions` so a history of hundreds stays usable (FR-013, SC-009)
- [X] T049 [US2] Build `lib/ui/history/past_review_screen.dart` — reopen a completed session's review by wrapping the existing `ReviewScreen` in a scoped `ProviderScope` that overrides `sessionControllerProvider` with the converted stored session, so the tree comparison, divergence, notes and metadata are the same widgets the player saw at the time (FR-014, SC-005)
- [X] T050 [US2] Handle abandoned sessions in `lib/ui/history/history_screen.dart` — they open to a plain "abandoned, answers forfeited" panel and never to a review, which is enforceable because `loadSession` already returned no solutions to render (FR-016)
- [X] T051 [US2] Route re-grading from `lib/ui/history/past_review_screen.dart` through `recordGrade` against the **past** session's id, so a revised grade replaces the stored one and is the one that counts (FR-017)
- [X] T052 [US2] Add the delete-everything control to `lib/ui/history/history_screen.dart` behind a confirmation that says plainly the deletion cannot be undone (FR-018)
- [X] T053 [US2] Add a history entry point to `lib/ui/session/session_setup_screen.dart` — an app-bar action to `HistoryScreen`, present only outside the training phase so the training screen gains no new affordance (FR-019)
- [X] T054 [US2] **Device checkpoint**: run quickstart scenarios 5 (abandoning forfeits the answers permanently) and 6 (finished sessions stay readable, including changing a grade) on the physical device

  > **Passed on device (2026-08-13)**: scenario 6 — the finished session reopened from the history showed the same tree comparison, solution notes and metadata panel as when it ended, with the recorded grade selected; re-grading from it replaced the grade in place (one row, `failed` → `good`). Scenario 5 — the abandoned session opened to "Its answers were forfeited and are not kept", with no solution, note or metadata for any position, including the one committed before it ended. Scenario 4 — a new session containing a position graded in an earlier session rendered identically to its first-ever appearance.

**Checkpoint**: Both user stories are independently functional. The loop's output is durable
and readable, and nothing anywhere shows a position's history across sessions.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T055 Establish the migration harness (research D9, FR-025) — run `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/` to snapshot version 1, commit `drift_schemas/`, generate the step helpers, and write `test/data/migration_test.dart` asserting that a v1 database opens at the current schema with its data intact. Doing this while there is nothing to migrate is the point: retrofitting it after real user data exists is what fails
- [X] T056 [P] Performance test in `test/data/session_repository_test.dart` — seed 200 synthetic sessions and assert that `listSessions` for the first page returns well inside the budget, so SC-009 is bounded by a test rather than by waiting a year for real history (research, "Open items")
- [X] T057 [P] Resume-timing check in `test/ui/resume_test.dart` — assert the resumed session is on screen without an intervening frame that would read as a stall, standing in for SC-002's three seconds, which is confirmed by hand in T060
- [X] T058 [P] Documentation pass — `README.md` and this feature's [quickstart.md](./quickstart.md) both state the `build_runner` step, its failure symptom, and that generated files are gitignored on purpose (research D8)
- [X] T059 Run `flutter analyze` and confirm it is clean across the new data and UI files, including that no analyzer suppression was added to make generated code pass
- [X] T060 **Device pass**: quickstart scenarios 8 (survives an app update — `adb install -r` over the existing install, without uninstalling), 9 (a full offline run in airplane mode), and 10 (a simulated storage failure is admitted to the player, not swallowed)

  > **Passed on device (2026-08-13)**: scenario 8 — `adb install -r` over the existing install (no uninstall) left 1 session, 3 attempts and the grade intact. Scenario 9 — with airplane mode on, a full pass (start, kill, resume, commit through to review, history, past review) ran with nothing failing or degrading. FR-018 was checked too: delete-everything warned that it cannot be undone and emptied all four tables. **Scenario 10 was not run in its device form** — filling the phone's disk is not something to do to the user's device; the behaviour it checks is covered by T063 against a repository whose writes fail.
- [X] T061 Manual audit for SC-004 — read every file under `lib/ui/training/` and confirm nothing on the training screen is derived from the player's history with the position on screen: no earlier grade, no encounter count, no last-seen date, no ordering or emphasis difference. T036 keeps this true automatically; this task confirms it is true once, by reading
- [X] T062 Run `flutter test` in full and confirm every suite passes from a clean clone, i.e. after `flutter pub get` and `dart run build_runner build --delete-conflicting-outputs` and nothing else
- [X] T063 Automated cover for quickstart scenario 10 in `test/ui/storage_failure_test.dart` — a repository whose writes fail on demand, asserting that a session that cannot be stored does not start, that a commit that cannot be stored does not advance the session, and that a failed *read* stays silent (FR-023 against FR-024). Added because the device pass in T060 is blocked, and this is the half of scenario 10 that does not need a phone

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — start immediately
- **Foundational (Phase 2)**: depends on Setup — **blocks both user stories**
- **User Story 1 (Phase 3)**: depends on Foundational
- **User Story 2 (Phase 4)**: depends on Foundational. Independent of US1's UI, but shares
  `drift_session_repository.dart`, so its repository tasks queue behind US1's
- **Polish (Phase 5)**: depends on both stories being complete

### User Story Dependencies

- **US1 (P1)**: needs only Phase 2. It is the MVP and the reason the feature exists
- **US2 (P2)**: needs only Phase 2 for its storage half. Its UI half reuses `ReviewScreen`,
  which already exists from feature 001, so it does not wait on US1

### Within Each User Story

- Tests are written first and confirmed failing before implementation
- Repository methods before the controller changes that call them
- Controller changes before the screens that read them
- The Principle I guards (T035, T036) are deliberately placed at the end of US1, before
  history exists — the rule goes in before the temptation does

### Parallel Opportunities

- T002 and T003 in Setup
- T004, T005, T007, T008 in Foundational — four independent files
- T015 while T013 and T014 are being implemented
- T023 alongside T020–T022, which are in a different file
- T043 alongside T039–T042, which are in a different file
- T056, T057 and T058 in Polish
- The whole of Phase 2 and the storage halves of Phases 3 and 4 need no device and can proceed
  while the phone is disconnected

**Serialisation to respect**: `lib/data/local/drift_session_repository.dart` is touched by
T012–T014, T024–T027, T044–T046, and `test/data/session_repository_test.dart` by T016–T018,
T020–T022, T039–T042, T056. Tasks within each of those groups run sequentially.

---

## Parallel Example: Foundational

```bash
# Four independent files, no shared state:
Task: "SessionRecord and SessionStatus in lib/domain/session/session_record.dart"
Task: "TreeDecodeError in lib/domain/errors.dart"
Task: "Drift tables in lib/data/local/tables.dart"
Task: "Codec tests in test/data/tree_codec_test.dart"
```

## Parallel Example: User Story 1 tests

```bash
# Storage tests and widget tests live in different files:
Task: "Atomicity, resume fidelity, grading and abandonment in test/data/session_repository_test.dart"
Task: "Resume flow widget tests in test/ui/resume_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup — dependencies and the codegen step
2. Phase 2: Foundational — schema, codec, repository (CRITICAL, blocks everything)
3. Phase 3: User Story 1
4. **STOP and VALIDATE**: quickstart scenarios 1, 2, 3 and 7 by hand on the device (T038)

Step 4 is the feature's whole claim. A session that survives being killed is what makes the
app safe to start; if that does not hold on a real phone under a real `force-stop`, nothing in
Phase 4 is worth building yet.

### Incremental Delivery

1. Setup + Foundational → storage proven against an in-memory database, no device needed
2. US1 → interrupted sessions resume, with both Principle I guards in place → **MVP**
3. US2 → history and past reviews
4. Polish → migration harness, performance bound, offline and update passes

### Parallel Team Strategy

Phases 1 and 2 are shared. After that, one developer can take US1's controller and UI
(T028–T038) while a second takes US2's repository methods (T044–T046) and history screens
(T048–T053) — the two touch no common file once each has landed its repository work, which is
the one queue between them.

---

## Notes

- **The training layer must stay history-free.** Grades are now stored, so the ingredients for
  "last seen 3 days ago, graded Hard" exist for the first time. T036 is the guard; the
  scheduling feature will arrive with a good-sounding reason to remove it
- **A failed read is swallowed, a failed write never is.** T014 returns null for corrupt data;
  T027 raises. The asymmetry is deliberate (FR-023 against FR-024)
- **Uncommitted analysis is not stored, by decision.** The defect is not the empty board on
  resume — it is the app failing to say why (FR-003, research D3)
- Generated code is not committed; `drift_schemas/` is. Commit after each task or logical
  group, and stop at any checkpoint to validate independently
