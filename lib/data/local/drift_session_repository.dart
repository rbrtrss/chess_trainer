/// The Drift implementation of [SessionRepository].
///
/// The only file that maps between stored rows and domain values, and the last
/// one that knows SQLite is involved.
///
/// **Times**: everything is stored as UTC epoch milliseconds and handed back as
/// UTC [DateTime]s. Display converts to local time. Timestamps already recorded
/// are never rewritten, so adjusting the device clock cannot move a session
/// around in the history.
library;

import 'dart:convert';
import 'dart:math';

import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/session_record.dart';
import 'package:dartchess/dartchess.dart';
import 'package:drift/drift.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class DriftSessionRepository implements SessionRepository {
  DriftSessionRepository(this._db, {Random? random})
      : _random = random ?? Random();

  final AppDatabase _db;
  final Random _random;

  // --------------------------------------------------------------- sessions

  @override
  Future<StoredSession> start(
    IList<TrainingPosition> positions, {
    DateTime? now,
  }) async {
    if (positions.isEmpty) {
      throw ArgumentError('a session needs at least one position');
    }

    final startedAt = _stamp(now);
    final id = _newSessionId(startedAt);

    try {
      await _db.transaction(() async {
        // Checked here so the caller gets a legible error, and enforced by the
        // partial unique index below so it holds even if this check is skipped.
        final existing = await _inProgressRow();
        if (existing != null) {
          throw SessionAlreadyInProgressError(existing.id);
        }

        await _db.into(_db.sessions).insert(
              SessionsCompanion.insert(
                id: id,
                startedAt: startedAt.millisecondsSinceEpoch,
                status: SessionStatus.inProgress.stored,
                currentIndex: 0,
              ),
            );

        for (var ordinal = 0; ordinal < positions.length; ordinal++) {
          final position = positions[ordinal];
          await _db.into(_db.sessionPositions).insert(
                SessionPositionsCompanion.insert(
                  sessionId: id,
                  ordinal: ordinal,
                  positionId: position.id,
                  initialFen: position.initialPosition.fen,
                  // Snapshotted, not referenced: a later app update must not be
                  // able to rewrite a session the player already played
                  // (research D4).
                  solutionPgn: encodeTree(position.solution),
                  metadataJson: _encodeMetadata(position.metadata),
                ),
              );
        }
      });
    } on SessionAlreadyInProgressError {
      rethrow;
    } on Object catch (error) {
      if (_isOneInProgressViolation(error)) {
        throw SessionAlreadyInProgressError(null);
      }
      throw StorageWriteError('starting the session', error);
    }

    final snapshots = <PositionSnapshot>[
      for (var ordinal = 0; ordinal < positions.length; ordinal++)
        PositionSnapshot(
          positionId: positions[ordinal].id,
          ordinal: ordinal,
          initialPosition: positions[ordinal].initialPosition,
          solution: positions[ordinal].solution,
          metadata: positions[ordinal].metadata,
        ),
    ];

    return StoredSession(
      record: SessionRecord(
        id: id,
        startedAt: startedAt,
        status: SessionStatus.inProgress,
        positionIds: positions.map((position) => position.id).toIList(),
      ),
      positions: snapshots.lock,
    );
  }

  @override
  Future<StoredSession?> loadInProgress() async {
    // Unreadable stored data is treated as absent rather than as an error to
    // propagate: surfacing a database fault at launch turns a recoverable
    // annoyance into an app that will not start (FR-023, research D10).
    try {
      final row = await _inProgressRow();
      if (row == null) return null;
      return await _readSession(row);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> commitAttempt(String sessionId, Attempt attempt) async {
    // One transaction (FR-005, research D6). Without it, a process death
    // between the two writes resumes a session whose index has moved past a
    // position that has no attempt — and `allPositionsAttempted` can then never
    // become true, so review can never begin. That state is unrecoverable, and
    // it is produced by a one-line omission.
    //
    // The index moves *before* the attempt is written on purpose: it makes the
    // dangerous half the one that gets rolled back if anything below it fails,
    // rather than the harmless one.
    try {
      await _db.transaction(() async {
        final session = await _sessionRow(sessionId);
        if (session == null) {
          throw StateError('no session $sessionId to commit against');
        }

        final total = await _positionCount(sessionId);
        final alreadyCommitted = await _attemptCount(sessionId);
        final isLast = alreadyCommitted + 1 >= total;
        final committedAt = _stamp(attempt.committedAt);

        await (_db.update(_db.sessions)
              ..where((row) => row.id.equals(sessionId)))
            .write(
          SessionsCompanion(
            currentIndex: Value(
              isLast ? session.currentIndex : session.currentIndex + 1,
            ),
            status: Value(
              (isLast ? SessionStatus.complete : SessionStatus.inProgress)
                  .stored,
            ),
            endedAt: isLast
                ? Value(committedAt.millisecondsSinceEpoch)
                : const Value.absent(),
          ),
        );

        await _db.into(_db.attempts).insert(
              AttemptsCompanion.insert(
                sessionId: sessionId,
                positionId: attempt.positionId,
                treePgn: encodeTree(attempt.tree),
                durationMs: attempt.duration.inMilliseconds,
                committedAt: committedAt.millisecondsSinceEpoch,
              ),
            );
      });
    } on Object catch (error) {
      throw StorageWriteError('saving your analysis', error);
    }
  }

  @override
  Future<void> recordGrade(
    String sessionId,
    Grade grade, {
    DateTime? now,
  }) async {
    // One grade per position per session: re-grading overwrites in place and no
    // earlier grade is kept (FR-017).
    try {
      await _db.into(_db.grades).insertOnConflictUpdate(
            GradesCompanion.insert(
              sessionId: sessionId,
              positionId: grade.positionId,
              value: grade.value.name,
              gradedAt: _stamp(now).millisecondsSinceEpoch,
            ),
          );
    } on Object catch (error) {
      throw StorageWriteError('saving your grade', error);
    }
  }

  @override
  Future<void> abandon(String sessionId) async {
    // The record stays and the answers go. Feature 001 could only forfeit the
    // answers until the process died; this makes it permanent (FR-016).
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.attempts)
              ..where((row) => row.sessionId.equals(sessionId)))
            .go();
        await (_db.delete(_db.grades)
              ..where((row) => row.sessionId.equals(sessionId)))
            .go();
        await (_db.update(_db.sessions)
              ..where((row) => row.id.equals(sessionId)))
            .write(
          SessionsCompanion(
            status: Value(SessionStatus.abandoned.stored),
            endedAt: Value(_stamp(null).millisecondsSinceEpoch),
          ),
        );
      });
    } on Object catch (error) {
      throw StorageWriteError('ending the session', error);
    }
  }

  @override
  Future<void> discardInProgress() async {
    final row = await _inProgressRow();
    if (row == null) return;
    await abandon(row.id);
  }

  @override
  Future<IList<SessionRecord>> listSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    // Only the session rows and their position ids. Loading every snapshot to
    // draw a list would make opening the history proportional to a year of use
    // (SC-009), and the list shows none of it.
    final rows = await (_db.select(_db.sessions)
          ..where((row) =>
              row.status.equals(SessionStatus.inProgress.stored).not())
          ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
          ..limit(limit, offset: offset))
        .get();

    final records = <SessionRecord>[];
    for (final row in rows) {
      final status = SessionStatus.fromStored(row.status);
      // A row this app never wrote is skipped rather than crashing the list.
      if (status == null) continue;

      final positionRows = await (_db.select(_db.sessionPositions)
            ..where((p) => p.sessionId.equals(row.id))
            ..orderBy([(p) => OrderingTerm.asc(p.ordinal)]))
          .get();

      records.add(
        SessionRecord(
          id: row.id,
          startedAt: _fromStamp(row.startedAt),
          endedAt: row.endedAt == null ? null : _fromStamp(row.endedAt!),
          status: status,
          positionIds:
              positionRows.map((p) => p.positionId).toIList(),
          currentIndex: row.currentIndex,
        ),
      );
    }
    return records.lock;
  }

  @override
  Future<StoredSession?> loadSession(String id) async {
    final row = await _sessionRow(id);
    if (row == null) return null;
    try {
      // `_readSession` strips the solutions and metadata of an abandoned
      // session, so the answers are absent from what the caller holds rather
      // than merely hidden by the UI (FR-016).
      return await _readSession(row);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> deleteEverything() async {
    try {
      await _db.transaction(() async {
        await _db.delete(_db.attempts).go();
        await _db.delete(_db.grades).go();
        await _db.delete(_db.sessionPositions).go();
        await _db.delete(_db.sessions).go();
      });
    } on Object catch (error) {
      throw StorageWriteError('deleting your history', error);
    }
  }

  // ----------------------------------------------------------------- reads

  Future<SessionRow?> _sessionRow(String id) =>
      (_db.select(_db.sessions)..where((row) => row.id.equals(id)))
          .getSingleOrNull();

  Future<int> _positionCount(String sessionId) async {
    final rows = await (_db.select(_db.sessionPositions)
          ..where((row) => row.sessionId.equals(sessionId)))
        .get();
    return rows.length;
  }

  Future<int> _attemptCount(String sessionId) async {
    final rows = await (_db.select(_db.attempts)
          ..where((row) => row.sessionId.equals(sessionId)))
        .get();
    return rows.length;
  }

  Future<SessionRow?> _inProgressRow() => (_db.select(_db.sessions)
        ..where((row) => row.status.equals(SessionStatus.inProgress.stored)))
      .getSingleOrNull();

  /// Assembles a whole session from its rows.
  ///
  /// Throws rather than returning a half-built session when anything is
  /// unreadable; the callers decide what to do with that (a read reports the
  /// session as absent).
  Future<StoredSession> _readSession(SessionRow row) async {
    final status = SessionStatus.fromStored(row.status);
    if (status == null) {
      throw TreeDecodeError('unknown session status "${row.status}"');
    }

    final positionRows = await (_db.select(_db.sessionPositions)
          ..where((p) => p.sessionId.equals(row.id))
          ..orderBy([(p) => OrderingTerm.asc(p.ordinal)]))
        .get();

    // An abandoned session forfeits its answers permanently: the solutions and
    // metadata are stripped here, in the repository, so the UI never holds them
    // and cannot be tempted to render them (FR-016).
    final forfeited = status == SessionStatus.abandoned;

    final snapshots = <PositionSnapshot>[];
    for (final position in positionRows) {
      snapshots.add(
        PositionSnapshot(
          positionId: position.positionId,
          ordinal: position.ordinal,
          initialPosition: _parsePosition(position.initialFen),
          solution: forfeited ? null : decodeTree(position.solutionPgn),
          metadata:
              forfeited ? null : _decodeMetadata(position.metadataJson),
        ),
      );
    }

    final attemptRows = await (_db.select(_db.attempts)
          ..where((a) => a.sessionId.equals(row.id)))
        .get();
    final attempts = <String, Attempt>{
      for (final attempt in attemptRows)
        attempt.positionId: Attempt(
          positionId: attempt.positionId,
          tree: decodeTree(attempt.treePgn),
          duration: Duration(milliseconds: attempt.durationMs),
          committedAt: _fromStamp(attempt.committedAt),
        ),
    };

    final gradeRows = await (_db.select(_db.grades)
          ..where((g) => g.sessionId.equals(row.id)))
        .get();
    final grades = <String, Grade>{
      for (final grade in gradeRows)
        grade.positionId: Grade(
          positionId: grade.positionId,
          value: _parseGradeValue(grade.value),
        ),
    };

    return StoredSession(
      record: SessionRecord(
        id: row.id,
        startedAt: _fromStamp(row.startedAt),
        endedAt: row.endedAt == null ? null : _fromStamp(row.endedAt!),
        status: status,
        positionIds:
            snapshots.map((snapshot) => snapshot.positionId).toIList(),
        currentIndex: row.currentIndex,
      ),
      positions: snapshots.lock,
      attempts: attempts.lock,
      grades: grades.lock,
    );
  }

  // ------------------------------------------------------------- mapping

  /// A session id that sorts by time and cannot collide in one millisecond.
  String _newSessionId(DateTime startedAt) {
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '${startedAt.millisecondsSinceEpoch.toRadixString(16)}-$suffix';
  }

  /// UTC, truncated to the millisecond the column can hold, so a value written
  /// and read back is the value that was written.
  DateTime _stamp(DateTime? now) {
    final moment = (now ?? DateTime.now()).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      moment.millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  DateTime _fromStamp(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

  Position _parsePosition(String fen) {
    try {
      return Chess.fromSetup(Setup.parseFen(fen));
    } on Object catch (error) {
      throw TreeDecodeError('stored FEN "$fen" is not a position: $error');
    }
  }

  GradeValue _parseGradeValue(String stored) {
    for (final value in GradeValue.values) {
      if (value.name == stored) return value;
    }
    throw TreeDecodeError('unknown grade "$stored"');
  }

  String _encodeMetadata(PositionMetadata metadata) => jsonEncode({
        'title': metadata.title,
        'goal': metadata.goal,
        'themes': metadata.themes.unlock,
        'rating': metadata.rating,
        'source': metadata.source,
      });

  PositionMetadata _decodeMetadata(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on Object catch (error) {
      throw TreeDecodeError('stored metadata is not JSON: $error');
    }
    if (decoded is! Map<String, Object?>) {
      throw TreeDecodeError('stored metadata is not an object');
    }
    final themes = decoded['themes'];
    return PositionMetadata(
      title: decoded['title'] as String?,
      goal: decoded['goal'] as String?,
      themes: themes is List
          ? themes.whereType<String>().toIList()
          : const IList<String>.empty(),
      rating: decoded['rating'] as int?,
      source: decoded['source'] as String?,
    );
  }

  /// True when [error] is the partial unique index refusing a second live
  /// session, as opposed to any other write failure.
  bool _isOneInProgressViolation(Object error) =>
      error.toString().contains(oneSessionInProgressIndex) ||
      error.toString().contains('UNIQUE constraint failed: sessions.status');
}
