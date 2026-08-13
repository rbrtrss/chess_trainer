# Implementation Plan: Session Persistence

**Branch**: `002-session-persistence` | **Date**: 2026-08-12 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-session-persistence/spec.md`

## Summary

Make what the training loop commits durable: an interrupted session resumes at the right
position with every committed attempt intact, and finished sessions stay readable afterwards.
Content still comes from the bundled set and nothing goes over a network.

The approach rests on four decisions from [research.md](./research.md):

- **Trees are stored as PGN text** using the codec feature 001 already built and round-trip
  tested. No new serialisation format, and the stored row is self-describing.
- **Only committed attempts are stored.** Clarification settled that an interruption costs the
  player the position they were part way through, which removes the design's only
  high-frequency write path — and with it its main performance risk.
- **A session snapshots the solutions and metadata it used**, so reopening history shows what
  the player was actually shown even after an app update changes the bundled content.
- **The new leak surface is closed by removal.** Resumption needs no new barrier — the
  training layer still sees only `TrainingProjection` — and cross-session history, the one
  genuinely new way to leak, was taken out of the feature rather than guarded.

## Technical Context

**Language/Version**: Dart 3.13.0 (bundled with Flutter 3.47.0)

**Primary Dependencies**: existing — `chessground` ^10.1.1, `dartchess` ^0.13.1,
`flutter_riverpod` ^3.0.3, `fast_immutable_collections` ^11.0.4. New — `drift` ^2.34.3,
`drift_flutter` ^0.3.1, with `drift_dev` ^2.34.5 and `build_runner` ^2.16.0 as dev
dependencies. **Not** `sqlite3_flutter_libs`: it is end-of-life and arrives transitively as a
no-op (research, "Verified package facts").

**Storage**: SQLite on the device via Drift, at `<app documents>/chess_trainer.sqlite`. Local
only; nothing is sent anywhere.

**Testing**: `flutter test`. Persistence is tested against `NativeDatabase.memory()`, so the
whole data layer runs with no device attached.

**Target Platform**: Android (phone). Verified on a physical device over `adb`.

**Project Type**: Mobile app, single Flutter module.

**Performance Goals**: resume on screen within 3 s of launch (SC-002); app usable within 2 s
with 200 stored sessions (SC-009). Nothing is written while the player is entering moves, so
feature 001's SC-006 is untouched by this feature.

**Constraints**: Fully offline (FR-022). Domain layer keeps zero Flutter imports. Stored data
survives an app update (FR-025).

**Scale/Scope**: one user, hundreds of sessions, each a handful of positions with move trees
bounded by feature 001's SC-006. Roughly 2 new screens.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | How this design satisfies it |
|---|---|---|
| **I. Delayed feedback (non-negotiable)** | PASS | *Resumption*: the training screen still consumes only `TrainingProjection`, so a resumed session cannot show more than a fresh one — the barrier built in 001 covers this with no new work (D5), asserted by a widget guard reusing 001's `renderSnapshot`. *History*: "you failed this one twice" is evidence about the position, and clarification removed cross-session history from the feature, so the surface does not exist. FR-019 states the negative requirement anyway and `layering_test.dart` gains a rule that no file under `lib/ui/training/` reads grade data, so the surface cannot quietly reappear. Snapshot solutions live in their own table that no training query touches (D4). |
| **II. Offline-first** | PASS | No network code exists in this feature either. The release manifest still declares no `INTERNET` permission, so the shipped app remains incapable of network access. |
| **III. Delegated chess correctness** | PASS | Trees are serialised through dartchess's PGN writer via the codec from 001. No hand-rolled parsing or move handling is introduced (D2). |
| **IV. Layering** | PASS | `lib/domain/` gains pure record types and stays Flutter-free. Drift, the schema and the generated code live entirely in `lib/data/`, exposed to the UI as repository interfaces. `lib/ui/` depends inward. |
| **V. Testing floor** | PASS | The floor's named units are unchanged and still covered. This feature adds: repository round-trip tests, an atomic-commit test, a resume-fidelity test, a migration harness, and the Principle I guards above — all runnable with `NativeDatabase.memory()` and no device. |
| **Licensing** | PASS | `drift`, `drift_flutter` MIT; `path_provider` BSD-3-Clause; `sqlite3` MIT. All GPL-3.0 compatible. Checked before adoption as the constitution requires. |
| **No secrets** | PASS | No credentials in this feature. The database holds only the player's own analyses and grades, on their own device. |
| **Complexity justified** | PASS with one recorded judgement | Drift is mandated by the constitution rather than chosen. The one genuine call — snapshotting solutions into the session record instead of referencing bundled assets — is recorded in Complexity Tracking. |

**Post-design re-check (after Phase 1)**: still PASS. The design added no network surface and
no dependency beyond those listed. It did add **code generation** to the build for the first
time (D8), which is a real change to how the project is built rather than to what it does —
recorded in the structure notes and the quickstart rather than as a violation.

## Project Structure

### Documentation (this feature)

```text
specs/002-session-persistence/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — decisions D1–D10
├── data-model.md        # Phase 1 — entities, schema, state
├── quickstart.md        # Phase 1 — how to run and validate
├── contracts/
│   └── storage-api.md   # Phase 1 — repository surface and invariants
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 — created by /speckit-tasks, not here
```

### Source Code (repository root)

Additions and changes to the structure feature 001 established.

```text
lib/
├── domain/                              # pure Dart — no Flutter imports
│   ├── session/
│   │   ├── training_session.dart        # existing
│   │   ├── grade.dart                   # existing
│   │   └── session_record.dart          # NEW — a stored session and its status
│   └── ...                              # tree/, position/, attempt/ unchanged
├── data/
│   ├── pgn_position_parser.dart         # existing — reused as the tree codec
│   ├── bundled_position_source.dart     # existing
│   ├── session_repository.dart          # NEW — the interface the UI codes against
│   └── local/
│       ├── database.dart                # NEW — @DriftDatabase, schemaVersion, migrations
│       ├── database.g.dart              # GENERATED, not committed
│       ├── tables.dart                  # NEW — table definitions
│       └── drift_session_repository.dart
└── ui/
    ├── session/
    │   ├── session_controller.dart      # CHANGED — writes through the repository
    │   ├── session_setup_screen.dart    # CHANGED — resume prompt, discard warning
    │   └── resume_prompt.dart           # NEW
    ├── training/                        # UNCHANGED — and must stay history-free
    └── history/
        ├── history_screen.dart          # NEW — list of past sessions
        └── past_review_screen.dart      # NEW — reopen a finished session's review

test/
├── domain/
│   └── layering_test.dart               # CHANGED — new rule: training reads no grade data
├── data/
│   ├── session_repository_test.dart     # NEW — round trip, atomicity, one-in-progress
│   ├── tree_codec_test.dart             # NEW — trees survive storage
│   └── migration_test.dart              # NEW — v1 harness for the version that follows
└── ui/
    ├── no_feedback_guard_test.dart      # CHANGED — resumed screen == fresh screen
    ├── resume_test.dart                 # NEW
    └── history_screen_test.dart         # NEW
```

**Structure Decision**: Unchanged from feature 001 — one Flutter module, the constitution's
three layers as top-level directories. Drift is confined to `lib/data/local/`, so the rest of
the app talks to repository interfaces and no other file learns that SQLite exists. The one
structural novelty is generated code (`*.g.dart`), which is gitignored and therefore makes
`dart run build_runner build` a prerequisite of `flutter test` on a fresh clone.

## Implementation sequence

Ordered so the riskiest work is proven first and each step leaves the app runnable.

1. **Schema and codec** — Drift dependencies, `database.dart`, tables, and the tree ⇄ PGN
   codec. Round-trip tests against an in-memory database. *No UI yet; this is the piece
   everything rests on.*
2. **Session repository** — write and read an in-progress session, atomic commit, the
   one-in-progress constraint. Unit tests for invariants 1–5 of the contract.
3. **Resume** — wire `SessionController` to the repository, add the resume prompt, the discard
   warning, and the notice that an analysis in progress was not kept. **First device
   checkpoint:** kill the app mid-session with `adb shell am force-stop` and confirm the
   committed attempts come back and the session lands on the right position.
4. **Principle I guards** — the layering rule and the resumed-vs-fresh widget comparison.
   Done here, before history exists, so the rule is in place before the temptation is.
5. **History of sessions** — retention of finished sessions, the list, and reopening a past
   review from the snapshot.
6. **Migration harness** — schema snapshot tooling and a test that survives a version bump.
7. **End-to-end pass on device** — the quickstart scenarios, including an app update over an
   existing install and a full offline run.

Steps 1, 2 and 6 need no device and can proceed regardless of whether a phone is connected.

## Complexity Tracking

No constitution violations require justification. One judgement call is recorded here for
visibility.

| Decision | Why needed | Simpler alternative rejected because |
|---|---|---|
| A session snapshots the solutions and metadata it used, rather than referencing the bundled position by id | SC-005 requires a reopened session to show *identical* review content, and bundled content changes when the app updates | Referencing by id lets an app update silently rewrite history the player has already been shown and graded against, and leaves dangling references to handle when a position is removed |

## Known risks

- **Losing the position in progress is a deliberate cost, and it will be felt.** Clarification
  chose not to store uncommitted analysis, so an interruption during a long calculation loses
  it. The mitigation is honesty rather than engineering: FR-003 requires the player to be told,
  so an empty board reads as a known consequence rather than as a bug. If it turns out to sting
  in practice, storing the working tree is a contained change to one repository method.
- **Code generation is a new failure mode.** A fresh clone that skips `build_runner` fails to
  compile with errors that point at the generated file rather than at the missing step. The
  quickstart and README must say so plainly.
- **History is still the most tempting place to break Principle I**, even though this feature
  does not display any. The grades are stored, so the data is there; every instinct from every
  other training app says to put "last seen 3 days ago, graded Hard" on the training screen.
  The layering rule exists because that change will look like an improvement to whoever makes
  it, and the scheduling feature will arrive with a reason to want it.
- **Retention is the one assumption still unconfirmed.** History is kept indefinitely with a
  manual delete-everything and no pruning; SC-009 bounds the consequence. Everything else was
  settled by the clarification session of 2026-08-12.
