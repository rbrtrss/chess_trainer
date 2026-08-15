---

description: "Task list for feature 003: position import"
---

# Tasks: Position Import

**Input**: Design documents from `/specs/003-position-import/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: Included, and not optional here. The constitution's Principle V names a testing floor
that this feature is required to extend — "Study PGN → training position extraction, against real
fixture files" has been on that floor since ratification with nothing covering it. The two
contract documents list 26 named invariants between them; each is a test task below.

**Organization**: Tasks are grouped by user story so each can be implemented and tested
independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US4)
- Every task names the exact file it touches

## Path Conventions

Single Flutter module, the constitution's three layers as top-level directories:
`lib/domain/`, `lib/data/`, `lib/ui/`, with tests mirroring them under `test/`. Paths below are
repository-relative and match the structure in [plan.md](./plan.md#source-code-repository-root).

**Run `dart run build_runner build --delete-conflicting-outputs` after any task touching
`lib/data/local/tables.dart` or `lib/data/local/database.dart`.** Generated files are gitignored;
the build fails pointing at the generated file rather than at the missing step.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies, fixtures, and correcting the repository's stale feature numbering

- [X] T001 Add `file_selector` ^1.1.0, `http` ^1.6.0, `crypto` ^3.0.7, `flutter_secure_storage` ^11.0.0 and `flutter_web_auth_2` ^5.1.0 to `pubspec.yaml`, each with the licence and rationale comment the existing entries use (research, "Verified package facts"), then run `flutter pub get`
- [X] T002 [P] Fetch a real multi-chapter Lichess study to `test/fixtures/study_multi_chapter.pgn` using the export URL in `specs/003-position-import/quickstart.md`, and commit it — the constitution's testing floor requires real fixture files, not synthesised ones
- [X] T003 [P] Add `test/fixtures/study_mixed_chapters.pgn` (chapters that start from a position mixed with "analyse this game" chapters carrying no `[FEN]`) and `test/fixtures/study_variant.pgn` (a non-standard `[Variant]` chapter), both from real exports
- [X] T004 [P] Correct the stale numbering that promises "feature 004" will import Lichess studies — it is this feature — in `lib/data/pgn_position_parser.dart` (lines 5, 102, 200), `lib/data/bundled_position_source.dart`, and `specs/001-training-session-core/research.md`, `specs/001-training-session-core/plan.md`, `specs/001-training-session-core/contracts/domain-api.md`, `specs/002-session-persistence/research.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The parser, the schema, and the Principle I guards. Everything else rests on these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete. The guards (T020–T023)
land **before any import UI exists** — the same ordering feature 002 used, so the rule is in place
before the temptation is.

### Domain types

- [X] T005 [P] Add `headers: IMap<String, String>` to `PositionMetadata` in `lib/domain/position/training_position.dart`, holding every PGN header verbatim, with the five typed fields kept as a view over it (research D11); do **not** add anything to `TrainingProjection`
- [X] T006 [P] Create `Collection` and the sealed `CollectionOrigin` (`BundledOrigin`, `FileOrigin`, `LichessOrigin`) in `lib/domain/library/collection.dart`
- [X] T007 [P] Create `ImportOutcome`, `RejectedEntry` and the `RejectionReason` enum (`noStartingPosition`, `noMoves`, `illegalMove`, `unsupportedVariant`, `unparseable`) in `lib/domain/library/import_outcome.dart`
- [X] T008 [P] Add `SourceUnreadableError` and `SourceTooLargeError` to `lib/domain/errors.dart`, and extend `PositionParseError` to carry a `RejectionReason`

### Parser

- [X] T009 Change `parseTrainingPosition` in `lib/data/pgn_position_parser.dart`: require `[FEN]` (throw `noStartingPosition` instead of falling back to `Chess.initial`), reject non-standard `[Variant]`, and capture every header into `PositionMetadata.headers` (research D10, D11)
- [X] T010 [P] Extend `test/data/pgn_position_parser_test.dart`: each rejection reason, header capture including headers the app does not recognise, and that all three bundled PGNs still parse unchanged
- [X] T011 Create `lib/data/import_parser.dart` — `parseImport` splitting a source with `PgnGame.parseMultiGamePgn`, collecting `RejectedEntry` per bad entry instead of failing the source, deriving each entry's reference from `[Event]`/`[Title]` or its ordinal, and enforcing the 5 MB / 500-entry caps (research D16)
- [X] T012 Create `test/data/import_test.dart` covering library-api invariants 3, 4 and 5 against the fixtures from T002–T003: per-reason rejection, other entries still importing, and `positions.length + rejections.length == entry count` — always

### Schema v2

- [X] T013 Add the `collections`, `positions` and `app_settings` tables to `lib/data/local/tables.dart` per [data-model.md](./data-model.md#stored-schema-v2), with `ON DELETE CASCADE` from `positions` to `collections` and an index on `content_hash`
- [X] T014 Raise `schemaVersion` to 2 and add `onUpgrade` in `lib/data/local/database.dart`, creating the three new tables and leaving the four v1 tables untouched
- [X] T015 Create the `CollectionRepository` interface in `lib/data/collection_repository.dart` exactly as [contracts/library-api.md](./contracts/library-api.md) defines it
- [X] T016 Implement `DriftCollectionRepository` in `lib/data/local/drift_collection_repository.dart`, with `store` writing the collection row and every position in **one transaction** (library-api invariant 2)
- [X] T017 Change `lib/data/bundled_position_source.dart` from the app's only source into a seeder, and implement `seedSamplesIfNeeded` guarded by the `samples_seeded` key in `app_settings` so a deleted sample collection stays deleted (FR-033, research D12)
- [X] T018 Create `test/data/collection_repository_test.dart` covering library-api invariants 1, 2, 6, 7, 8 and 9: round trip with branches and header bag intact, atomic store, cascade delete leaving sessions byte-identical, and seeding exactly once
- [X] T019 Extend `test/data/migration_test.dart` and add `test/generated/schema_v2.dart` plus the `drift_schemas/drift_schema_v2.json` dump, asserting a v1 database with stored sessions upgrades with its history intact

### Principle I guards — before any import UI exists

- [X] T020 [P] Create `test/fixtures/hostile_metadata.pgn`: one chapter whose `[Event]`, `[Site]`, `[Annotator]`, `[Result]`, `[Opening]`, comments and NAGs each contain a distinctive sentinel string
- [X] T021 Extend `test/ui/no_feedback_guard_test.dart` to import `hostile_metadata.pgn` under a leaking collection name ("Mate in three, back rank") from a leaking file name (`answers.pgn`) and assert no sentinel is reachable anywhere in the training screen's widget tree, including semantics labels and tooltips (SC-003)
- [X] T022 Extend `test/ui/no_feedback_guard_test.dart` with an imported-vs-bundled comparison: the training screen for an imported position renders identically to one for a bundled position at the same point, apart from the pieces (SC-004)
- [X] T023 Extend the training-layer rule in `test/domain/layering_test.dart` so no file under `lib/ui/training/` mentions `Collection`, `CollectionOrigin`, `CollectionRepository`, `PositionMetadata`, `headers`, or any provenance type — the 002 rule covered grades; content provenance is the same class of evidence (FR-026, FR-027)

**Checkpoint**: The parser handles real studies, content is storable, and the guards are in place.

---

## Phase 3: User Story 1 - Train on a study file I already have (Priority: P1) 🎯 MVP

**Goal**: A PGN file on the device becomes a named collection of trainable positions, with an
honest report of what was added and what was rejected, and a session can be run on it.

**Independent Test**: Import a multi-chapter study PGN containing comments, glyphs, variations and
result headers; run a full session on it; confirm the training screen shows nothing but the board
and the side to move, while review shows the author's analysis and notes.

### Tests for User Story 1

- [X] T024 [P] [US1] Create `test/ui/import_flow_test.dart`: pick a file, parse, name, confirm, report — asserting the report lists every rejected entry with a reason and an identifying reference (FR-007, SC-008)
- [X] T025 [P] [US1] Add a test to `test/data/import_test.dart` for the duplicate-hash path: importing content whose hash matches an existing collection warns, and still imports on confirmation (FR-010, library-api invariant 11)
- [X] T026 [P] [US1] Add a progress test to `test/data/import_test.dart` asserting determinate progress over a 300-entry source and that parsing never blocks the UI isolate for more than one frame (SC-007, library-api invariant 12)

### Implementation for User Story 1

- [X] T027 [US1] Create `lib/data/import_service.dart` implementing the import state machine from [data-model.md](./data-model.md#import-states-and-transitions), emitting `ImportProgress` and running `parseImport` through `compute` so parsing stays off the UI isolate (research D15)
- [X] T028 [US1] Add the content hash (SHA-256 of the source text, via `crypto`) and the `findByContentHash` duplicate check to `lib/data/import_service.dart` (research D13)
- [X] T029 [US1] Add file picking to `lib/data/import_service.dart` via `file_selector`'s `openFile()`, accepting any file rather than filtering on a MIME type Android providers report inconsistently (research D1) — the content is validated instead
- [X] T030 [P] [US1] Create `lib/ui/library/import_report_view.dart` presenting rejections **grouped by reason** with a plain-language explanation of the common case ("9 chapters start from the standard position, so there is no position to train")
- [X] T031 [US1] Create `lib/ui/library/import_screen.dart`: pick, name, determinate progress, duplicate warning, then the report — using `import_report_view.dart`
- [X] T032 [US1] Add the Riverpod providers for `CollectionRepository` and `ImportService` in `lib/ui/app.dart`, and route to the import screen
- [X] T033 [US1] Change `lib/ui/session/session_setup_screen.dart` and `lib/ui/session/session_controller.dart` to source positions from `CollectionRepository` instead of `BundledPositionSource`, so an imported collection is trainable — the chooser itself is US3
- [X] T034 [US1] Verify on device: import a real study file, train it, review it, and confirm the report's counts match the file's chapter count (quickstart scenarios 1 and 2) — **the file half was closed on 2026-08-15**, during feature 004's device pass; see "The file picker, finally" below. Training and reviewing were not repeated on this collection, because training is collection-agnostic and the same path was already exercised on the Lichess-imported one

**Checkpoint**: The feature is independently useful with no network code written. US1 delivered.

---

## Phase 4: User Story 2 - Import a study straight from Lichess (Priority: P2)

**Goal**: A study on Lichess — public without logging in, private after logging in — becomes a
local collection that trains identically and works offline afterwards.

**Independent Test**: Log in to Lichess from the app, import a private study of the account's, put
the device in airplane mode, and run a full session on it.

**⚠️ The network guard (T035–T036) is written first**, before any networking exists, so every
line that follows lands against a rule that is already there (research D14).

### Tests for User Story 2

- [X] T035 [US2] Narrow the network rule in `test/domain/layering_test.dart` from "nothing in `lib/` opens a network connection" to "nothing outside `lib/data/lichess/` mentions `package:http/`, `HttpClient`, `WebSocket` or socket use", and add the companion rule that no file under `lib/ui/` or `lib/domain/` imports `lib/data/lichess/` (lichess-api invariant 13) — narrowed, never deleted
- [X] T036 [US2] Create `test/ui/no_network_during_training_test.dart` driving the whole training flow — setup, session, commit, review, resume, history, collection list — against a `LichessApi` fake whose every method fails the test if called (FR-015, SC-009, lichess-api invariant 12). This is the behavioural replacement for the manifest guarantee this feature gives up
- [X] T037 [P] [US2] Create `test/data/study_link_test.dart`: study URL, chapter URL and bare id accepted; game URL, profile URL, other host, and wrong-length id rejected (lichess-api invariant 9)
- [X] T038 [P] [US2] Create `test/data/lichess_api_test.dart` against a fake `http.Client`, covering lichess-api invariants 6, 7, 8 and 10: one request on `429` with no retry loop, serialised requests, the exact export query string, and `logOut` clearing the local credential even when revocation fails
- [X] T039 [P] [US2] Create `test/data/lichess_auth_test.dart` covering lichess-api invariants 1–5 and 11: S256 challenge derivation, verifier length, `state` mismatch aborting with no token stored, the form-encoded exchange with **no client secret**, absolute expiry handling, `401` clearing the credential, no file anywhere mentioning `refresh_token`, and a sentinel token never appearing in any exception, log line or `toString()`

### Implementation for User Story 2

- [X] T040 [P] [US2] Create `LichessConnection` (username and absolute expiry — **not** the token) in `lib/domain/lichess/lichess_connection.dart`
- [X] T041 [P] [US2] Create `lib/data/lichess/study_link.dart` — `parseStudyId` extracting an 8-character id from a study URL, chapter URL or bare id (research D8)
- [X] T042 [P] [US2] Add the network error types from the [lichess-api error contract](./contracts/lichess-api.md#error-contract) to `lib/domain/errors.dart`: `NoConnectionError`, `NotLoggedInError`, `LoginExpiredError`, `LoginCancelledError`, `RateLimitedError`, `StudyNotAvailableError`, `NotAStudyLinkError`, `LichessUnavailableError`
- [X] T043 [US2] Create `lib/data/lichess/lichess_api.dart` implementing the four requests, serialised one at a time, with `exportStudy` sending `clocks=false&comments=true&variations=true` and `listStudies` parsing NDJSON line by line, skipping a malformed line rather than failing the list (research D6, D7, D9)
- [X] T044 [US2] Map every HTTP outcome to the error contract in `lib/data/lichess/lichess_api.dart`: `401` → `LoginExpiredError` with the credential cleared, `429` → `RateLimitedError` with no retry, `404`/`403` → `StudyNotAvailableError`, `5xx` → `LichessUnavailableError`
- [X] T045 [US2] Add `importStudy` to `lib/data/import_service.dart`, handing the fetched PGN to the same `parseImport` the file path uses (research D7) and storing with a `LichessOrigin`
- [X] T046 [US2] Create `lib/data/lichess/credential_store.dart` over `flutter_secure_storage`, holding the token, its absolute expiry and the username, and never exposing the token outside `lib/data/lichess/`
- [X] T047 [US2] Create `lib/data/lichess/lichess_auth.dart`: verifier and state from `Random.secure()`, unpadded base64url SHA-256 challenge, `flutter_web_auth_2` for the Custom Tab and callback, `state` checked on return, form-encoded exchange, absolute expiry stored. **No refresh path, and no method that could invite one** (research D3, D5)
- [X] T048 [US2] Add `INTERNET`, `android:allowBackup="false"`, `android:dataExtractionRules` and the `org.chesstrainer://oauth/callback` activity to `android/app/src/main/AndroidManifest.xml`, replacing the comment that says the release build is deliberately incapable of networking with one that says what replaced that guarantee
- [X] T049 [P] [US2] Create `lib/ui/library/connection_controller.dart` — log in, log out, current connection, expiry surfaced as "log in again" and never as a silent failure
- [X] T050 [P] [US2] Create `lib/ui/library/study_picker_screen.dart` listing the account's studies (FR-013), with a paste-an-address path that works without logging in for a public study (FR-011)
- [X] T051 [US2] Wire the Lichess paths into `lib/ui/library/import_screen.dart`, sharing the progress, duplicate check and report already built in US1
- [ ] T052 [US2] Verify on device: import a public study with no login, log in, import a private one, then enable airplane mode and train it (quickstart scenarios 4 and 5) — **two of the four done on 2026-08-15** during feature 004's pass: a public study imported with no login at all, on a profile that had never connected; and the login itself run by the account holder, though from the home screen this feature did not have. Importing a *private* study and training under airplane mode are still not done

**Checkpoint**: US1 and US2 both work independently. The app has a credential for the first time.

---

## Phase 5: User Story 3 - Choose what a session draws from (Priority: P3)

**Goal**: With several collections, the player picks which one a session works through, and its
name never appears after the setup screen.

**Independent Test**: Import two collections, start a session restricted to one, and confirm every
position came from it and its name never appears on a training screen.

### Tests for User Story 3

- [X] T053 [P] [US3] Add tests to `test/ui/session_flow_test.dart`: every position of a session comes from the chosen collection; a collection with fewer positions than requested yields a shorter session rather than a repeated one; an empty collection refuses to start, saying why (FR-030 – FR-032, library-api invariant 10)
- [X] T054 [P] [US3] Add a case to `test/ui/no_feedback_guard_test.dart` asserting the chosen collection's name appears on the setup screen and on no training screen (FR-026)

### Implementation for User Story 3

- [X] T055 [US3] Add the collection chooser to `lib/ui/session/session_setup_screen.dart`, showing each collection's name and position count
- [X] T056 [US3] Handle the short and empty cases in `lib/ui/session/session_controller.dart`: tell the player how many positions are available and run the shorter session; refuse an empty collection with the reason

**Checkpoint**: US1, US2 and US3 all work independently.

---

## Phase 6: User Story 4 - Manage what I have imported (Priority: P4)

**Goal**: See, rename and delete collections — including the samples — and disconnect the Lichess
account, with past sessions readable throughout.

**Independent Test**: Import a collection, play a session on it, delete it, and confirm it can no
longer be trained while the played session still shows its full review.

### Tests for User Story 4

- [X] T057 [P] [US4] Create `test/ui/collection_list_test.dart`: each collection listed with name, origin, import date and position count; rename; delete behind a warning; the sample collection deletable and not returning on relaunch (FR-033 – FR-036)
- [X] T058 [P] [US4] Add a test to `test/ui/history_screen_test.dart` asserting a past session opened after its collection was deleted still shows every position, solution, note and grade (FR-037, SC-012)
- [X] T059 [P] [US4] Add a test to `test/ui/storage_failure_test.dart` for deleting a collection the unfinished session depends on: the abandon-style warning appears, and confirming discards the session (FR-038)

### Implementation for User Story 4

- [X] T060 [US4] Create `lib/ui/library/collection_list_screen.dart` — name, origin, import date, position count, rename, delete
- [X] T061 [US4] Add the deletion warnings to `lib/ui/library/collection_list_screen.dart`: the cannot-be-undone warning, and the extra warning, in the same words as abandoning, when the unfinished session depends on the collection
- [X] T062 [US4] Add the empty-library state to `lib/ui/library/collection_list_screen.dart` and `lib/ui/session/session_setup_screen.dart` — offer import rather than an error or a broken setup (FR-039)
- [X] T063 [US4] Add disconnect-account to `lib/ui/library/collection_list_screen.dart` via `connection_controller.dart`, leaving imported collections untouched (FR-022)

**Checkpoint**: All four user stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T064 [P] Update `README.md`: content now comes from the player, the app declares `INTERNET` and why, the guarantee that replaced the old one, and that a factory reset now costs the history (`allowBackup="false"`)
- [X] T065 [P] Update the fixture-fetching and troubleshooting notes in `specs/003-position-import/quickstart.md` with anything learned while implementing
- [X] T066 Work through every row of the [lichess-api error contract](./contracts/lichess-api.md#error-contract) on device — **done 2026-08-15**, except two rows judged not reproducible without harming something; see "The error contract on device" below (SC-011, quickstart scenario 6)
- [ ] T067 Measure a 300-chapter import on device against SC-007; if the isolate transfer cost dominates, apply the recorded fallback of sending PGN strings back instead of parsed trees (research D15)
- [X] T068 Install this build over a 002 build on device and confirm history survives and the samples appear (FR-040, quickstart scenario 10)
- [X] T069 Run the full offline pass — **done 2026-08-15** with airplane mode actually on (`Active default network: none`): cold launch with no spinner and the account read from local storage, an unfinished session **resumed**, trained, committed and reviewed with its full solutions, plus history and library, all on a collection that had come from Lichess. An import attempted in that state gave the offline message. The zero-request half was measured separately and more precisely than packet inspection, by reading the app's uid byte counters around four cold starts and a whole session: 0 bytes, against 11,448 for the one action that should fetch (SC-009, quickstart scenario 8)
- [X] T070 Run `dart analyze` and the whole suite with `flutter test` — both clean. `dart format .` deliberately not run; see "What was done, and what was not"

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks every user story**
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on Foundational and on US1's `ImportService` (T027–T028), which it extends rather than duplicates
- **US3 (Phase 5)**: depends on Foundational and on US1's change to session setup (T033)
- **US4 (Phase 6)**: depends on Foundational; the disconnect task (T063) additionally depends on US2's `connection_controller.dart` (T049)
- **Polish (Phase 7)**: depends on whichever stories are being shipped

### Recommended build order differs from priority order

Priorities in [spec.md](./spec.md) rank *value*. The cheapest order to build is:

**US1 → US3 → US4 → US2.**

US3 and US4 are small and complete the file-import product; US2 is the largest piece of the
feature and the only one needing a network, a login, and a manifest change. Build it last unless
Lichess import is the reason you are doing this feature at all, in which case go US1 → US2 and
accept that the collection list arrives later.

Nothing in US2 blocks US3 or US4 except T063, so the file half of the feature can be finished and
shipped even if the OAuth work stalls.

### Within Each Story

- Tests before implementation, and they must fail first
- Domain types before data, data before UI
- The Principle I guards (T020–T023) and the network guard (T035–T036) come **before** the code
  they constrain, not after

### Parallel Opportunities

- T002, T003, T004 in Setup
- T005–T008 (domain types, four different files) and T020 in Foundational
- T024, T025, T026 in US1; T037, T038, T039 in US2; T053–T054 in US3; T057–T059 in US4
- T040, T041, T042 in US2, then T049 and T050 once `LichessApi` exists
- T064 and T065 in Polish

---

## Parallel Example: Foundational domain types

```bash
# Four different files, no dependencies between them:
Task: "Add headers bag to PositionMetadata in lib/domain/position/training_position.dart"
Task: "Create Collection and CollectionOrigin in lib/domain/library/collection.dart"
Task: "Create ImportOutcome and RejectedEntry in lib/domain/library/import_outcome.dart"
Task: "Add SourceUnreadableError and SourceTooLargeError to lib/domain/errors.dart"
```

## Parallel Example: User Story 2 tests

```bash
# Three test files, all against fakes — no device, no network:
Task: "Create test/data/study_link_test.dart"
Task: "Create test/data/lichess_api_test.dart against a fake http.Client"
Task: "Create test/data/lichess_auth_test.dart covering PKCE, expiry and no-refresh"
```

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Phase 1: Setup
2. Phase 2: Foundational — **critical, blocks everything**
3. Phase 3: US1
4. **Stop and validate**: import a real study file, train it, read the report
5. At this point the app trains the player's own content with no network code in it at all

### Incremental Delivery

1. Setup + Foundational → the parser handles real studies and content is storable
2. US1 → file import works → **MVP, shippable**
3. US3 → several collections become usable
4. US4 → the library is manageable
5. US2 → Lichess import, the login, and the manifest change

### Notes

- `[P]` means different files with no incomplete dependencies
- Re-run `dart run build_runner build --delete-conflicting-outputs` after T013 and T014
- Commit after each task or logical group
- **If a guard test fails, the change is wrong — not the test.** That applies to T021, T022, T023,
  T035 and T036 in particular; T035 narrows an existing rule and must never be weakened further to
  make something else pass

---

## What was done, and what was not

Recorded at implementation time rather than left to be inferred from the checkboxes.

### The device pass, 2026-08-14, TECNO KJ6 (Android 13)

Run after the fact, once a device was attached. **T068 passed and is checked.** The rest are
partly verified and stay unchecked, with exactly what was covered recorded here.

**T068 — upgrade over a 002 build: PASS.** The device already had the 002 build from
2026-08-13 carrying one real session (14 August 2026, 21:58, 3 positions). `adb install -r`
over it: the v1 → v2 migration ran on real data, the session is still in the history, and its
review still renders the board, the comparison, the played line and the author's comments —
which also exercises the metadata codec's backward-compatible path against rows written
before the header bag existed. The samples appeared as a seeded collection.

**Verified, though their tasks stay unchecked because each covers more:**

- *Lichess fetch, end to end (part of T034/T052).* A public study imported by pasting its
  address, with no login: 7 positions added and 4 rejected, matching the fixture counts
  exactly. Trained and reviewed; the solution's nine moves replay correctly. This is the first
  time the network path ran against the real service.
- *Principle I on real content (SC-003, SC-004).* A chapter from a real study — carrying
  `[StudyName]`, `[ChapterName]`, `[Event]`, player names and a result — showed only "1 of 3",
  "White to move", the board, the move controls and "Done". Confirmed by reading the
  **accessibility tree**, which is everything a screen reader would announce, rather than by
  eye: nothing from the study, and no collection name, appears in it.
- *Two rows of the error contract (T066).* A malformed address produced "That is not a Lichess
  study address. It should look like lichess.org/study/abcd1234." with no request made. With
  the radios off, an import produced "Importing from Lichess needs a connection. Everything
  already imported still works offline."
- *Offline training on imported content (SC-010, part of T069).* With `Active default network:
  none`, the app opened without a spinner and a session on the imported Lichess collection ran
  normally.

**Still not verified, and why:**

- **The login (T052).** It needs the account holder's Lichess credentials in a browser. Not
  something to do on someone's behalf.
- **The file-picker path (T034).** Distinct code — `file_selector` through the Storage Access
  Framework — and unexercised on device. Covered by tests, not by hardware.
- **T067 on device.** Measured on the development machine only (297 positions in 61 ms).
- **The remaining error rows (T066)** — 401, 429, 404, a connection killed mid-fetch — and
  **packet-level confirmation for T069.**

### What the pass found that the tests did not

The import report rendered **"3 entries starts from the standard position"**. Singular verb,
plural count. Every test passed: they asserted the group existed and named the right reason,
not that the line was a sentence. Fixed by making the summary count-aware, with a regression
test that asserts both forms and rejects the broken ones. It is the one defect the whole
device pass produced, and it is exactly the kind a test suite is bad at.

### A note on how this pass was driven

The app was driven over `adb` with taps and screenshots. Twice, a back-press left the app and
the next screenshot or accessibility dump captured the device owner's personal messages
instead. Those artifacts were deleted immediately, on the host and on the device, and the pass
was stopped at the second occurrence rather than continued. Anything driven this way should
either keep the app in the foreground explicitly or be driven by someone looking at the screen.

What was done instead, so the gap is as small as it can be without a device:

- **`flutter build apk --debug` succeeds.** This exercises the manifest changes — the INTERNET
  permission, `allowBackup="false"`, the data-extraction rules, and the OAuth callback activity
  — which are the parts of T048 that no unit test can reach. It also caught a real break; see
  below.
- **T066's error contract is automated** in `test/ui/import_failure_messages_test.dart`: every
  row of the contract is provoked and asserted to reach the player as a message naming what
  happened and what to do, leaving no collection behind. What still needs a device is
  provoking them for real — airplane mode, a revoked token, a killed connection mid-fetch.
- **T067's timing was measured** on the development machine: 297 positions parsed in 61 ms from
  a 438 KiB source, three orders of magnitude inside SC-007's 10 s budget. A phone is slower,
  but not by that much. What still needs a device is the *responsiveness* half — the isolate
  hop (D15) is what keeps frames drawing, and that cannot be observed in a widget test.
- **T069's offline claim is automated** in `test/ui/no_network_during_training_test.dart`,
  including a control case proving the fake client really is reachable when the player asks for
  an import — without that, every other assertion in the file could be passing because nothing
  was wired up. What still needs a device is watching real traffic.

### Done differently than planned

- **T070** ran `dart analyze` (clean) and the full suite (368 passing), but **did not run
  `dart format .`**. The repository was written against the pre-3.7 formatter: running it now
  rewrites 71 of 89 files and buries this feature's diff in whole-repo churn. Reformatting the
  codebase is its own change, with its own commit, and not this feature's business.
- **`flutter_secure_storage` is pinned to ^10.3.1, not the ^11.0.0 research chose.** 11.0.0 sets
  `compileSdk = 37`, and the Android SDK manager publishes no plain `platforms;android-37` —
  only minor-versioned `android-37.0` and up — so Gradle cannot resolve the platform and the
  APK build fails on the plugin. Found by building, not by reading. The reason is recorded in
  `pubspec.yaml` and in research's package table.
- **The layering rule for the network directory is narrower than the contract stated.** The
  contract said no file under `lib/ui/` may import `lib/data/lichess/`; that is stricter than
  this project's own convention, where providers live in `lib/ui/` and `session_controller.dart`
  already constructs the Drift repository. The rule as implemented is: the domain layer never,
  and under `lib/ui/` exactly one file — `connection_controller.dart` — with every screen going
  through it. `LichessGateway` exists so that even that file never names an HTTP client.

### Known risk carried forward

`flutter_web_auth_2` applies the Kotlin Gradle Plugin, which Flutter warns will fail to build
in a future version. It builds today. If it stops, the fallback is `url_launcher` plus
`app_links`, which research D3 already evaluated and rejected only on the grounds of extra
wiring.

### The file picker, finally — 2026-08-15

`file_selector` through the Storage Access Framework was the one path this feature shipped and
never ran on hardware. It was recorded above as "distinct code, and unexercised on device.
Covered by tests, not by hardware", and it stayed that way through feature 004's own pass, whose
throwaway-user trick could not help: `adb push` writes to user 0 whatever the foreground user is,
and copying across users is refused, so there was no way to put a PGN where the picker in a
secondary user could see it.

It was closed on the owner's own profile instead, with him choosing the file by hand — which is
also the right division of labour, since browsing his file picker means reading his files.

`study_multi_chapter.pgn` (study `9LjyYZ9N`, 33 chapters, **all 33 with a `[FEN]`**) was placed on
the device and picked. The prediction was written down before the button was pressed — 33
imported, 0 rejected — and the result was `t034-fixture · t034-fixture.pgn · 33 positions`. The
whole chain ran on a real device for the first time: `OPEN_DOCUMENT` with `*/*`, the returned
`XFile`, the parse, the collection, and the origin recorded as the file's own name. The
collection was deleted afterwards and both fixtures removed from the device.

**One thing worth keeping from the noise around it.** The first attempt used
`study_mixed_chapters.pgn`, which is study `55NSdxBQ` — the same study already in the library,
fetched over the network on 2026-08-14. It was refused as a duplicate. That is content-hash
duplicate detection (D13) recognising the same study arriving by a *different route*, file versus
fetch, which no test covers and which nobody had thought to check.

**And a warning for anyone driving this by `adb`.** Two things wasted time here and neither was a
defect: `uiautomator` writes `content-desc='...'` with **single** quotes when the value itself
contains double quotes, so a naive `content-desc="[^"]*"` grep silently drops exactly the
messages that quote a collection name; and the phone rotated to landscape mid-run, after which
every hard-coded portrait swipe went somewhere useless. Read bounds from the dump every time
rather than remembering them.

### The error contract on device — 2026-08-15

Run during feature 004's follow-up, on a release build of `main`, against the real service.

| Row | Result |
|---|---|
| Offline | *"Importing from Lichess needs a connection. Everything already imported still works offline."* — and it says the rest of the app is unaffected, which is the half that matters |
| Malformed address | Done in 003's own pass: *"That is not a Lichess study address…"*, with no request made |
| `404` / study gone | Importing `lichess.org/study/zzzzzzzz`: *"That study is not available to this account. It may have been deleted, or made private."* Library unchanged |
| `401` / revoked token | The owner revoked the app's token at `lichess.org/account/oauth/token`. The next request was refused, `onUnauthorized` cleared the credential, and the bar fell to `Not connected` on the next launch. **The message was wrong — see below** |
| Killed mid-fetch | App force-stopped during a fetch: library still exactly two collections, nothing partial (FR-019) |
| Cancelled login | Covered by test; a cancelled login is reported as nothing at all |
| `429` rate limited | **Not reproducible without abusing the service.** Inducing it means deliberately hammering Lichess, which this app is built not to do — requests are serialised and there is no retry loop precisely so the limit is never approached. The path is unit-tested against a fake client, and that is the most this can honestly be |
| Storage full | **Not attempted.** Filling a phone's storage to see one message is possible and grim; the path is unit-tested |

### What the 401 row found

With the token revoked, asking for *My studies* produced:

> That study is not public, so it needs a connected Lichess account. Connect one on the home
> screen.

The player named no study, and the cause was a revoked login rather than a private one. The 401
clears the credential mid-request, the account then reads as disconnected, `myStudiesProvider`
throws `NotLoggedInError`, and the picker rendered that error's wording — which was written for
someone who pasted a private address.

This is the **third** time this one message has leaked into a context it was not written for: the
first two were found in 004's device passes, on the import screen and on the picker's disconnected
state, and both were fixed by giving that context its own sentence. Neither fix reached this
branch, because nothing had ever driven a 401 through it.

Fixed with `messageForStudyListError`, which the picker now uses on both of its error paths:
anything in the my-studies context that is really "no account" gets the my-studies sentence, and
everything else keeps its own. The regression test reproduces the exact asymmetry — a credential
present, so the account reads connected and the list renders, while the list request is refused —
and was confirmed to fail with the old wording before the fix was kept.
