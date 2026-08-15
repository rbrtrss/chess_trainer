# Research: Session Persistence

**Date**: 2026-08-12 | **Feature**: [spec.md](./spec.md)

Findings are from reading the package sources in `~/.pub-cache/hosted/pub.dev/drift-2.34.3`
and `drift_flutter-0.3.1`, and from the code feature 001 already shipped, rather than from
published documentation.

## Verified package facts

| API | Signature / behaviour |
|---|---|
| `driftDatabase({required String name, DriftNativeOptions? native})` | Returns `DatabaseConnection`. Resolves to `<app documents dir>/<name>.sqlite` via `path_provider`, and runs the database on a **background isolate** (`drift/isolate.dart`). |
| `NativeDatabase.memory()` | In-memory database. This is what lets every persistence test run under `flutter test` with no device. |
| `GeneratedDatabase.schemaVersion` / `MigrationStrategy(onCreate:, onUpgrade:)` | Drift's migration hooks, invoked from `db_base.dart`. |
| `drift_dev` + `build_runner` | Code generation. Produces `*.g.dart` next to the database definition. |

**Licensing** (the constitution requires this check before adopting anything): `drift`,
`drift_flutter` and `sqlite3_flutter_libs` are all MIT (Simon Binder); `path_provider` is
BSD-3-Clause. All are GPL-3.0 compatible. No new licence risk.

**A trap worth naming**: `sqlite3_flutter_libs` resolves to `0.6.0+eol`, and its changelog
reads "Deprecate this package… this version removes all code from this package." Since
`sqlite3` 3.x it is unnecessary; `drift_flutter` 0.3.0 moved to `sqlite3` 3.x and depends on
the EOL shim only to *stop* users pulling the old 0.5.x build scripts. **We must not add
`sqlite3_flutter_libs` to `pubspec.yaml`.** Following an older Drift setup guide would add
it and reintroduce the Flutter-specific build scripts the package exists to retire.

---

## D1. Storage engine

**Decision**: Drift over SQLite, via `drift_flutter`.

**Rationale**: The constitution names Drift in its Technology Constraints, so this is settled
rather than chosen. The facts that matter for the design are that queries run on a background
isolate (so no write blocks the UI thread) and that
`NativeDatabase.memory()` makes the whole data layer testable without a device, which keeps
this feature inside the constitution's "if a rule is hard to unit-test, it is in the wrong
layer" bar.

**Consequence**: code generation enters the project for the first time. See D8.

## D2. How a variation tree is stored

**Decision**: Trees are stored as **PGN text**, with a `[FEN]` header, using the
`toPgnNode` / `fromPgnNode` codec feature 001 already built.

**Rationale**: This is the strongest reuse available, and it is nearly free.

1. The code exists and is tested. `test/data/pgn_position_parser_test.dart` already asserts
   that a tree survives being written to PGN text and read back — that test *is* the
   serialisation test this feature would otherwise have to write.
2. A stored tree is self-describing. With the FEN in the header, a row can be replayed
   without knowing which bundled position it came from, which is what makes the
   "bundled positions changed under us" edge case survivable.
3. It is the same format feature 003 ingests, so the app has one tree interchange format in
   both directions instead of two.
4. It is legible in a database browser, which matters when diagnosing a report of lost work.

**Alternatives considered**:

- *A JSON schema for nodes* — rejected: a new format, a new parser, a new set of tests, all
  of it throwaway once the PGN path exists anyway.
- *Normalised move rows (a table of nodes with parent ids)* — rejected: it buys queryability
  into trees, and nothing in this feature or the next two queries into a tree. It would turn
  a value we already have into a join.

**Trade-off, accepted**: a tree cannot be searched with SQL. If some later feature needs
"find every attempt containing Nf3", it will need an index built for it. That is a concrete
problem to solve when it exists, not now.

## D3. When storage is written

**Decision**: Storage is written at **deliberate moments only** — starting a session,
committing an attempt, grading, abandoning. Nothing is written while the player is entering
moves.

**Rationale**: Clarification (2026-08-12) settled that uncommitted analysis is not stored: an
interruption costs the player the position they were in the middle of, and nothing else. That
removes the design's only high-frequency write path, and with it the performance risk that
would have come from writing after every move while the player is calculating.

What remains is a handful of writes per session, each tied to a user action that already
involves a screen transition, so there is no budget concern worth designing around.

**Consequence**: the app must not imply that work in progress is safe. FR-003 requires the
player to be told, on resuming, that the analysis they were part way through was not kept —
an empty board has to read as a known consequence rather than as lost work.

**Alternative considered and rejected by the user**: writing the working tree after every edit,
which would have preserved a half-built variation tree across a process kill at the cost of a
database write per move.

## D4. What a session record contains

**Decision**: A stored session **snapshots the solution and the metadata** of each position it
contains, rather than referring to the bundled asset.

**Rationale**: SC-005 requires that reopening a finished session shows *identical* review
content. Bundled positions are shipped inside the app and change when the app updates — a
corrected solution or a renamed chapter would silently rewrite history that the player has
already been shown and already graded against. Snapshotting makes a finished session an
immutable record of what actually happened, and it makes FR-024's dangling-reference case
disappear for completed sessions rather than needing to be handled.

The cost is duplication of a few kilobytes per session, which is not a consideration.

**Consequence, stated plainly**: if a bundled solution is later corrected, old history keeps
the old solution. That is the correct behaviour — it is what the player was shown and judged
against — but it must not surprise anyone reading the data later.

**Principle I note**: snapshotting means solution text now sits in the same database as an
in-progress session. It is stored in its own table, and nothing in the training layer queries
it. See D5.

## D5. Preventing the new leaks structurally

Persistence opened two ways to violate Principle I that feature 001 could not have. One is
closed by a type that already exists; the other was removed from the feature.

**Decision (FR-008, resumed sessions)**: nothing changes. The training screen already consumes
only `TrainingProjection`, which has no path to a solution or to metadata. Resumption restores
the *session*, and the training layer keeps reading the same projection it always did. The
leak barrier built in feature 001 covers this for free — which is the payoff of having built
it as a type rather than as a habit.

**Decision (the player's own history)**: there is nothing to guard, because there is nothing
to show. Clarification (2026-08-12) removed cross-session history from this feature entirely:
grades are stored against the session that gave them, and nothing aggregates them by position.

**Rationale**: this was the one genuinely new leak surface persistence introduced — "you failed
this one twice" is evidence about the position in front of the player, and it is the most
tempting thing to put on a training screen because it looks like helpful context. Removing the
display removes the risk rather than managing it.

**What is kept anyway**: FR-019 states the negative requirement, and the layering test gains a
rule that no file under `lib/ui/training/` may read grade data. Both are nearly free, and they
exist so that the storage this feature *does* create cannot quietly grow a display later. The
feature that adds scheduling will need this guard on its first day.

**Second layer**: the widget guard from feature 001 (`renderSnapshot` / `boardSnapshot` in
`test/ui/no_feedback_guard_test.dart`) is reused to assert that a *resumed* training screen
renders identically to a fresh one at the same point.

## D6. Atomicity of a commit

**Decision**: Committing an attempt — storing the tree, clearing the working analysis, and
advancing the position index — happens in **one transaction**.

**Rationale**: FR-005 says a position is either committed or not, never partly so. Without a
transaction, a process death between the two writes resumes a session whose stored index has
moved past a position that has no attempt, and the session can then never enter review because
`allPositionsAttempted` is false forever. That is an unrecoverable state produced by a
one-line omission, which is exactly the kind of thing to decide once, here.

## D7. One session in progress

**Decision**: At most one session row may have status `inProgress`, enforced by a **partial
unique index** in the schema, not only by application logic.

**Rationale**: FR-010 makes "resume" a question with one answer. If two in-progress rows can
exist, the resume prompt becomes ambiguous and the bug is invisible until it happens to a
user. A database constraint turns it into a write failure at the moment of the mistake.

## D8. Generated code and the build

**Decision**: Generated Drift code stays **out of version control**, and the codegen step is
documented as part of the build.

**Rationale**: `.gitignore` already excludes `*.g.dart` and `*.drift.dart` — that decision was
made when the repository was bootstrapped, and generated files are derived artefacts that
produce noisy diffs and merge conflicts.

**Consequence, which must be written down because it will bite otherwise**: after this feature,
`flutter test` and `flutter build` **fail on a fresh clone** until `dart run build_runner build`
has been run. That step belongs in the README and in this feature's quickstart. It is the first
time this project has had a build step beyond `pub get`.

**Alternative considered**: committing the generated files. Rejected for the diff noise, but it
is a reasonable thing to revisit if the codegen step ever causes a wasted debugging session.

## D9. Migrations

**Decision**: `schemaVersion = 1` with `onCreate`, plus drift's schema-snapshot tooling wired
up from the start so that version 2 has something to migrate *from*.

**Rationale**: FR-026 requires stored data to survive an app update, and the update that breaks
it is always the one where nobody thought about migration. Establishing the harness while there
is nothing to migrate is cheap; retrofitting it after real user data exists is not.

## D10. Missing or unreadable stored data

**Decision**: Unreadable stored data is treated as **absent**, not as an error to propagate.
The app opens to the setup screen with no resumable session, and says so.

**Rationale**: FR-024. The alternative — surfacing a database error at launch — turns a
recoverable annoyance into an app that will not start. The one thing that must *not* happen is
silently continuing while the player believes their work is safe, which is why FR-025 requires
a failed write to be reported even though a failed read is swallowed.

## Open items carried from the spec

- **SC-009** (opening with two hundred sessions in under two seconds) cannot be validated
  against real history yet. The plan is to seed a synthetic history in a test rather than wait
  for a year of use.
- **Retention** is the one assumption still unconfirmed: history is kept indefinitely, with a
  manual delete-everything and no pruning. It was judged low impact — a session is a few small
  trees — and SC-009 bounds the performance consequence. The other assumptions were settled by
  the clarification session of 2026-08-12 and are recorded in the spec.
