/// The stored schema.
///
/// Four tables, described in `specs/002-session-persistence/data-model.md`.
/// Nothing outside `lib/data/local/` refers to any of this: the rest of the app
/// codes against `SessionRepository`, and no other file learns that SQLite
/// exists (Constitution IV).
///
/// Times are stored as UTC epoch milliseconds and converted to local time only
/// for display, so adjusting the device clock cannot move a session around in
/// the history.
library;

import 'package:drift/drift.dart';

/// One training session, live or finished.
///
/// At most one row may have `status = 'in_progress'`, enforced by a partial
/// unique index created in `database.dart` rather than by application logic
/// alone (FR-010, research D7): if two live sessions could exist, "resume"
/// would be a question with two answers and the bug would stay invisible until
/// it happened to a user.
///
/// The index is declared here rather than created by hand in a migration so it
/// is part of the schema drift knows about: it is then dumped into
/// `drift_schemas/`, and the migration test validates it like any other part of
/// the schema.
@DataClassName('SessionRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX one_session_in_progress '
  "ON sessions(status) WHERE status = 'in_progress';",
)
class Sessions extends Table {
  TextColumn get id => text()();

  IntColumn get startedAt => integer()();

  /// Null while in progress.
  IntColumn get endedAt => integer().nullable()();

  /// `in_progress` / `complete` / `abandoned` — see `SessionStatus.stored`.
  TextColumn get status => text()();

  /// Which position the player is on. Meaningless once the session is finished.
  IntColumn get currentIndex => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What the player was actually shown, frozen at the time (research D4).
///
/// A session carries its own copy of each position's solution and metadata
/// rather than referring to the bundled asset, because bundled content changes
/// when the app updates and a grade is a judgement against the answer the
/// player was shown (FR-015).
///
/// **Nothing in the training layer queries this table.** It exists for review
/// and for history.
@DataClassName('SessionPositionRow')
class SessionPositions extends Table {
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// Position order within the session.
  IntColumn get ordinal => integer()();

  /// The bundled position's identifier.
  TextColumn get positionId => text()();

  TextColumn get initialFen => text()();

  /// Snapshotted solution, with its comments and NAGs, as PGN (research D2).
  TextColumn get solutionPgn => text()();

  /// Snapshotted title, goal, themes, rating and source, as JSON.
  TextColumn get metadataJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId, ordinal};
}

/// A committed analysis of one position within one session.
///
/// Rows here are written once and never updated: feature 001's rule that a
/// committed analysis cannot be edited becomes a storage property too.
@DataClassName('AttemptRow')
class Attempts extends Table {
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  TextColumn get positionId => text()();

  /// The committed analysis, PGN with a `[FEN]` header (research D2).
  TextColumn get treePgn => text()();

  IntColumn get durationMs => integer()();

  IntColumn get committedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId, positionId};
}

/// The player's self-assessment of one position within one session.
///
/// One grade per position per session: re-grading from a past review overwrites
/// the row in place and no earlier grade is retained (FR-017). Nothing
/// aggregates these across sessions — that is the scheduling feature's job, and
/// its display is the one thing that would put evidence about a position in
/// front of a player who is still calculating.
@DataClassName('GradeRow')
class Grades extends Table {
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  TextColumn get positionId => text()();

  /// `failed` / `hard` / `good` / `easy` — the name of a `GradeValue`.
  TextColumn get value => text()();

  /// Rewritten when the grade is changed.
  IntColumn get gradedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId, positionId};
}
