/// The stored schema.
///
/// Seven tables: four described in
/// `specs/002-session-persistence/data-model.md`, and three added by feature
/// 003 and described in `specs/003-position-import/data-model.md`.
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

// ---------------------------------------------------------------------------
// Feature 003: the library. Content stops being three files in the asset
// bundle and becomes something the player owns, imports, and deletes.
// ---------------------------------------------------------------------------

/// A named group of positions produced by one import.
@DataClassName('CollectionRow')
@TableIndex(name: 'collections_by_content', columns: {#contentHash})
class Collections extends Table {
  TextColumn get id => text()();

  /// Player-supplied and deliberately **not** unique (FR-009).
  TextColumn get name => text()();

  /// `bundled` / `file` / `lichess` — see `CollectionOrigin`.
  TextColumn get originKind => text()();

  /// The file name, or the study id. Null for the bundled samples.
  TextColumn get originRef => text().nullable()();

  /// The study's name at the time it was fetched. Null otherwise.
  TextColumn get originLabel => text().nullable()();

  IntColumn get importedAt => integer()();

  /// SHA-256 of the source text, for duplicate detection (003 research D13).
  ///
  /// It answers the question actually being asked — "have I already imported
  /// *this*?" — rather than a proxy like the file name or the study id, and so
  /// it catches the case that happens: the same study exported twice under two
  /// different names.
  TextColumn get contentHash => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One trainable position belonging to one collection.
///
/// **Nothing in the training layer queries this table by collection.** A
/// session is handed positions; it never learns which collection they came
/// from, because that is provenance and provenance is evidence (FR-026).
@DataClassName('PositionRow')
@TableIndex(name: 'positions_by_collection', columns: {#collectionId})
class Positions extends Table {
  TextColumn get id => text()();

  TextColumn get collectionId =>
      text().references(Collections, #id, onDelete: KeyAction.cascade)();

  /// Order within the collection, as the source had it.
  IntColumn get ordinal => integer()();

  /// Never null: an entry with no `[FEN]` is rejected at import rather than
  /// stored with a guessed starting position (003 research D10).
  TextColumn get initialFen => text()();

  /// The whole solution tree, comments and NAGs included, as PGN (002 D2).
  TextColumn get solutionPgn => text()();

  /// The typed fields *and* the full header bag (003 D11).
  TextColumn get metadataJson => text()();

  /// Where [solutionPgn] came from: `author`, `engine` or `none` (005 FR-007).
  ///
  /// Every row written before schema v3 is an `author` row, and the migration
  /// sets them so: before feature 005 a position could only be stored if its
  /// source had moves.
  TextColumn get solutionSource =>
      text().withDefault(const Constant('author'))();

  /// What the engine said about the starting position, or null.
  ///
  /// Null for every authored position — where an author said what they
  /// intended, the engine is not consulted (005 FR-011) — and for a position
  /// whose evaluation could not be produced.
  TextColumn get evaluationJson => text().nullable()();

  /// Which engine and search budget produced [evaluationJson], or null.
  ///
  /// So that a position imported by one build is not silently compared with one
  /// imported by another (005 research D5). The same instinct as recording the
  /// depth on the evaluation itself, one level up.
  TextColumn get engineId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small facts about the installation that are not about a session.
///
/// One key so far: `samples_seeded`. It exists so that deleting the bundled
/// sample collection is permanent (FR-033). Seeding "when the collection table
/// is empty" would resurrect the samples for a player who had deliberately
/// cleared everything — an app arguing with its user about what it should
/// contain.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
