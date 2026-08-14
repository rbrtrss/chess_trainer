import 'package:chess_trainer/data/bundled_position_source.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_session_repository.dart';
import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/position/training_projection.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/session_record.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// The positions shipped with the app.
final bundledPositionsProvider =
    FutureProvider<IList<TrainingPosition>>((ref) async {
  const source = BundledPositionSource();
  return source.loadAll();
});

/// The database, opened once for the app's lifetime and closed with it.
///
/// Providers live in `lib/ui/` by this project's convention, which is what
/// keeps `lib/data/` free of Flutter and Riverpod imports (Constitution IV).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// How the app stores sessions.
///
/// Tests override this with a repository over `AppDatabase.memory()`, which is
/// how the whole persistence path is exercised with no device attached.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return DriftSessionRepository(ref.watch(appDatabaseProvider));
});

/// The unfinished session waiting to be resumed, if there is one (FR-006).
///
/// Null both when there is nothing to resume and when the stored data cannot be
/// read: unreadable data is treated as absent, so a corrupt row costs the
/// player a session rather than the ability to open the app (FR-023).
final resumeCandidateProvider = FutureProvider<StoredSession?>((ref) async {
  return ref.watch(sessionRepositoryProvider).loadInProgress();
});

/// Past sessions, newest first, up to `limit` of them (FR-013).
///
/// Pageable rather than exhaustive: a history of hundreds must not be loaded to
/// draw the first screenful of it (SC-009).
final sessionHistoryProvider =
    FutureProvider.family<IList<SessionRecord>, int>((ref, limit) async {
  return ref.watch(sessionRepositoryProvider).listSessions(limit: limit);
});

/// One past session, whole, for reopening its review (FR-014).
///
/// Null for an unknown id and for unreadable data. For an abandoned session the
/// snapshots come back with no solution and no metadata — the answers are
/// absent from this value, not hidden by whatever renders it (FR-016).
final pastSessionProvider =
    FutureProvider.family<StoredSession?, String>((ref, id) async {
  return ref.watch(sessionRepositoryProvider).loadSession(id);
});

/// The session in progress, or null when there is none.
final sessionControllerProvider =
    NotifierProvider<SessionController, TrainingSession?>(
  SessionController.new,
);

/// Owns the session and is the only thing that talks to it.
///
/// Note what this class does *not* expose: there is no `currentSolution`, no
/// `isCorrect`, no accessor that hands a `TrainingPosition` to a training
/// widget. Training reads [currentProjectionProvider]; review reads the session
/// directly, and only ever from review screens.
class SessionController extends Notifier<TrainingSession?> {
  /// The stored session the live one belongs to, or null when nothing is
  /// stored — which is only true before the first `start` or `resume`.
  String? _storedId;

  String? get storedSessionId => _storedId;

  @override
  TrainingSession? build() => null;

  SessionRepository get _repository => ref.read(sessionRepositoryProvider);

  /// Starts a session over the first [length] bundled positions.
  ///
  /// The session is stored before it appears on screen, so a session that
  /// cannot be stored never starts — the player is told instead of being let
  /// believe their work is safe (FR-024). The caller is expected to have
  /// warned and discarded any unfinished session first (FR-010).
  Future<void> start(IList<TrainingPosition> positions, {int? length}) async {
    final selected = length == null || length >= positions.length
        ? positions
        : positions.sublist(0, length);

    final stored = await _repository.start(selected);
    _storedId = stored.id;
    state = TrainingSession.start(selected);
  }

  /// Rebuilds a live session from what was stored (FR-007).
  ///
  /// The position the player was part way through comes back with an empty
  /// board, because nothing was stored for it (FR-003, research D3). That is a
  /// decision, not an omission, and the resume prompt says so.
  void resume(StoredSession stored) {
    _storedId = stored.id;
    state = resumedSessionFrom(stored);
  }

  /// Commits [tree] as the attempt for the current position and moves on.
  ///
  /// Advancing happens inside the session, in one step, so there is nowhere for
  /// an interstitial result screen to appear (FR-016).
  ///
  /// The attempt is stored *before* the live session moves on, so an
  /// interruption can cost the player the position they are on but never one
  /// they have committed (FR-002, FR-005). A failed write throws rather than
  /// advancing, and the screen tells the player (FR-024).
  Future<void> commit(
    VariationTree tree, {
    required Duration duration,
    DateTime? now,
  }) async {
    final session = _require();
    final attempt = Attempt(
      positionId: session.currentPosition.id,
      tree: tree,
      duration: duration,
      committedAt: now ?? DateTime.now(),
    );

    await _store((id) => _repository.commitAttempt(id, attempt));
    state = session.commitAttempt(attempt);
  }

  /// Records the user's own assessment of the position under review (FR-026).
  Future<void> recordGrade(Grade grade) async {
    await _store((id) => _repository.recordGrade(id, grade));
    state = _require().recordGrade(grade);
  }

  /// Moves to another position in review (FR-028).
  void goToReviewPosition(int index) {
    state = _require().goToReviewPosition(index);
  }

  /// Ends the session without revealing anything (FR-019).
  ///
  /// The stored session is marked abandoned and its attempts and grades are
  /// deleted, so the answers are forfeited permanently rather than until the
  /// process dies (FR-016).
  Future<void> abandon() async {
    await _store(_repository.abandon);
    state = _require().abandon();
  }

  /// Clears the session and returns to setup.
  ///
  /// Storage is untouched: a finished session stays in the history.
  void reset() {
    _storedId = null;
    state = null;
  }

  /// Points this controller at an already-stored session.
  ///
  /// For the past-review controller, whose session is not the live one: grades
  /// recorded while reading a past review must be written against **that**
  /// session (FR-017), not against whatever is in progress.
  @protected
  void adoptStoredSession(String id) {
    _storedId = id;
  }

  /// Runs a write against the stored session, if there is one.
  ///
  /// There is no stored session only in tests that drive the controller
  /// directly; the app always starts or resumes through storage first.
  Future<void> _store(Future<void> Function(String id) write) async {
    final id = _storedId;
    if (id == null) return;
    await write(id);
  }

  TrainingSession _require() {
    final session = state;
    if (session == null) {
      throw StateError('there is no session in progress');
    }
    return session;
  }
}

/// Turns what was stored back into a live session (FR-007).
///
/// Separate from [SessionController.resume] so the guard test can pump a
/// resumed session through exactly the same conversion the app uses, and get a
/// widget tree with nothing test-shaped in it to compare against a fresh one
/// (SC-003).
TrainingSession resumedSessionFrom(StoredSession stored) {
  final positions = stored.positions
      .map((snapshot) => snapshot.toTrainingPosition())
      .toIList();
  if (positions.isEmpty) {
    throw StateError('a stored session with no positions cannot be resumed');
  }

  final everythingAttempted =
      positions.every((position) => stored.attempts.containsKey(position.id));

  return TrainingSession(
    positions: positions,
    attempts: stored.attempts,
    grades: stored.grades,
    // A session whose positions were all committed before the interruption
    // resumes into review, which is where it was.
    phase: everythingAttempted ? SessionPhase.review : SessionPhase.training,
    currentIndex: everythingAttempted
        ? 0
        : stored.record.currentIndex.clamp(0, positions.length - 1),
  );
}

/// What the training layer is allowed to see of the current position.
///
/// Null outside the training phase — during review there is no projection,
/// because review is where the whole position becomes readable.
final currentProjectionProvider = Provider<TrainingProjection?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session == null || session.phase != SessionPhase.training) return null;
  return session.projectionFor(session.currentIndex);
});
