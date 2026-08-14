import 'dart:math';

import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_session_repository.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/session_record.dart';
import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/tree_helpers.dart';

/// A repository over an in-memory database, torn down with the test.
///
/// The whole data layer is exercised this way, with no device attached, which
/// is what keeps the constitution's "if a rule is hard to unit-test, it is in
/// the wrong layer" bar satisfiable for persistence.
class RepositoryHarness {
  RepositoryHarness._(this.db, this.repository);

  factory RepositoryHarness.create() {
    final db = AppDatabase.memory();
    // A fixed seed so a failing test can be re-run with the same ids.
    final repository = DriftSessionRepository(db, random: Random(20260812));
    addTearDown(db.close);
    return RepositoryHarness._(db, repository);
  }

  final AppDatabase db;
  final DriftSessionRepository repository;

  /// Raw rows, for the tests that must bypass application logic — proving a
  /// database constraint holds, or corrupting stored data on purpose.
  Future<List<SessionRow>> rawSessions() => db.select(db.sessions).get();

  Future<List<AttemptRow>> rawAttempts() => db.select(db.attempts).get();

  Future<List<GradeRow>> rawGrades() => db.select(db.grades).get();

  Future<List<SessionPositionRow>> rawPositions() =>
      db.select(db.sessionPositions).get();

  /// Writes a session row directly, so a test can try to create the state the
  /// application refuses to create.
  Future<void> insertRawSession({
    required String id,
    required String status,
    int startedAt = 0,
    int currentIndex = 0,
  }) =>
      db.into(db.sessions).insert(
            SessionsCompanion.insert(
              id: id,
              startedAt: startedAt,
              status: status,
              currentIndex: currentIndex,
            ),
          );

  /// Replaces a stored column value, for the corrupt-data tests.
  Future<void> corrupt(String sql) => db.customStatement(sql);
}

/// Positions with rich solutions and metadata, so that anything storage drops
/// or leaks has something conspicuous to drop or leak.
IList<TrainingPosition> samplePositions({int count = 3}) {
  final all = <TrainingPosition>[
    parseTrainingPosition('''
[Title "Philidor's Legacy"]
[Goal "White to play and force mate"]
[Themes "smothered mate, double check, queen sacrifice"]
[Rating "1500"]
[Source "Classic study"]
[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]

1. Nh6+! {Double check.} Kh8 2. Qg8+!! (2. Qf7 {too slow}) 2... Rxg8 3. Nf7#
''', id: 'sample-tactic'),
    parseTrainingPosition('''
[Title "The quiet move"]
[Goal "Black to play and hold"]
[Themes "prophylaxis"]
[Rating "1800"]
[Source "Personal game"]
[FEN "r1bq1rk1/pp2ppbp/2np1np1/8/2BNP3/2N1B3/PPP2PPP/R2Q1RK1 b - - 0 1"]

1... Ng4 {Hitting the bishop before White consolidates.} 2. Bg5 (2. Bf4 Bxd4) 2... h6
''', id: 'sample-positional'),
    parseTrainingPosition('''
[Title "Opposition"]
[Goal "White to play and win"]
[Themes "king and pawn, opposition"]
[Rating "1400"]
[Source "Endgame manual"]
[FEN "8/8/4k3/8/8/4K3/4P3/8 w - - 0 1"]

1. Kd4 Kd6 2. e4 (2. e3 Ke6) 2... Ke6 3. e5
''', id: 'sample-endgame'),
  ];

  if (count <= all.length) return all.take(count).toIList();

  // Beyond the authored three, clone with fresh ids — enough for the tests that
  // need a longer session than there is authored content for.
  final extended = [...all];
  var next = 0;
  while (extended.length < count) {
    final source = all[next % all.length];
    extended.add(
      TrainingPosition(
        id: '${source.id}-${extended.length}',
        initialPosition: source.initialPosition,
        solution: source.solution,
        metadata: source.metadata,
      ),
    );
    next++;
  }
  return extended.toIList();
}

/// A committed analysis with a branch in it, so storage has structure to lose.
///
/// [committedAt] is truncated to the millisecond the column holds, so a value
/// written and read back compares equal.
Attempt sampleAttempt(
  TrainingPosition position, {
  Duration duration = const Duration(minutes: 2),
  DateTime? committedAt,
}) {
  final tree = _branchingAnalysisFor(position);
  final moment = (committedAt ?? DateTime.utc(2026, 8, 12, 10, 30)).toUtc();
  return Attempt(
    positionId: position.id,
    tree: tree,
    duration: duration,
    committedAt: DateTime.fromMillisecondsSinceEpoch(
      moment.millisecondsSinceEpoch,
      isUtc: true,
    ),
  );
}

/// Two plies of the solution, then an alternative first move — the shape a
/// player produces when they consider something and reject it.
VariationTree _branchingAnalysisFor(TrainingPosition position) {
  final solution = position.solution;
  var tree = VariationTree.empty(position.initialPosition);

  final mainline = solution.primaryLine.take(3).toList();
  for (var i = 0; i < mainline.length; i++) {
    tree = tree.play(pathOfDepth(i), mainline[i].move).tree;
  }

  // An alternative to the first move, if there is a second legal one.
  final alternatives = tree.legalMovesAt(pathOfDepth(0));
  for (final move in alternatives) {
    final position = tree.positionAt(pathOfDepth(0));
    final san = position.makeSan(move).$2;
    if (tree.children.any((child) => child.san == san)) continue;
    tree = tree.play(pathOfDepth(0), move).tree;
    break;
  }

  return tree;
}

/// A repository over an in-memory database, for a widget test's
/// `sessionRepositoryProvider` override.
///
/// Widget tests run against the *real* repository implementation, just over a
/// database that lives for the length of the test — so the invariants the
/// storage tests enforce are the ones the widgets are exercised against, rather
/// than a stub's approximation of them.
///
/// Riverpod 3 keeps `Override` internal, so the override itself is written out
/// at each call site:
///
/// ```dart
/// sessionRepositoryProvider.overrideWithValue(inMemorySessionRepository())
/// ```
DriftSessionRepository inMemorySessionRepository([RepositoryHarness? harness]) =>
    (harness ?? RepositoryHarness.create()).repository;

/// A repository whose writes fail, for the paths that must admit a failure
/// rather than let the player believe their work was stored (FR-024).
///
/// It delegates its reads, so a session can be set up normally and then made
/// unwritable — which is the shape of the real failure: a device that fills up
/// part way through a session.
class FailingWriteRepository implements SessionRepository {
  FailingWriteRepository(this._delegate, {this.failWrites = true});

  final SessionRepository _delegate;

  bool failWrites;

  Never _fail(String operation) =>
      throw StorageWriteError(operation, 'the disk is full');

  @override
  Future<StoredSession?> loadInProgress() => _delegate.loadInProgress();

  @override
  Future<StoredSession?> loadSession(String id) => _delegate.loadSession(id);

  @override
  Future<IList<SessionRecord>> listSessions({int limit = 50, int offset = 0}) =>
      _delegate.listSessions(limit: limit, offset: offset);

  @override
  Future<StoredSession> start(
    IList<TrainingPosition> positions, {
    DateTime? now,
  }) {
    if (failWrites) _fail('starting the session');
    return _delegate.start(positions, now: now);
  }

  @override
  Future<void> commitAttempt(String sessionId, Attempt attempt) {
    if (failWrites) _fail('saving your analysis');
    return _delegate.commitAttempt(sessionId, attempt);
  }

  @override
  Future<void> recordGrade(String sessionId, Grade grade, {DateTime? now}) {
    if (failWrites) _fail('saving your grade');
    return _delegate.recordGrade(sessionId, grade, now: now);
  }

  @override
  Future<void> abandon(String sessionId) {
    if (failWrites) _fail('ending the session');
    return _delegate.abandon(sessionId);
  }

  @override
  Future<void> discardInProgress() {
    if (failWrites) _fail('discarding the unfinished session');
    return _delegate.discardInProgress();
  }

  @override
  Future<void> deleteEverything() {
    if (failWrites) _fail('deleting your history');
    return _delegate.deleteEverything();
  }
}
