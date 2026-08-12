import 'package:chess_trainer/data/bundled_position_source.dart';
import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/position/training_projection.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The positions shipped with the app.
final bundledPositionsProvider =
    FutureProvider<IList<TrainingPosition>>((ref) async {
  const source = BundledPositionSource();
  return source.loadAll();
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
  @override
  TrainingSession? build() => null;

  /// Starts a session over the first [length] bundled positions.
  void start(IList<TrainingPosition> positions, {int? length}) {
    final selected = length == null || length >= positions.length
        ? positions
        : positions.sublist(0, length);
    state = TrainingSession.start(selected);
  }

  /// Commits [tree] as the attempt for the current position and moves on.
  ///
  /// Advancing happens inside the session, in one step, so there is nowhere for
  /// an interstitial result screen to appear (FR-016).
  void commit(VariationTree tree, {required Duration duration, DateTime? now}) {
    final session = _require();
    state = session.commitAttempt(
      Attempt(
        positionId: session.currentPosition.id,
        tree: tree,
        duration: duration,
        committedAt: now ?? DateTime.now(),
      ),
    );
  }

  /// Records the user's own assessment of the position under review (FR-026).
  void recordGrade(Grade grade) {
    state = _require().recordGrade(grade);
  }

  /// Moves to another position in review (FR-028).
  void goToReviewPosition(int index) {
    state = _require().goToReviewPosition(index);
  }

  /// Ends the session without revealing anything (FR-019).
  void abandon() {
    state = _require().abandon();
  }

  /// Clears the session and returns to setup.
  void reset() {
    state = null;
  }

  TrainingSession _require() {
    final session = state;
    if (session == null) {
      throw StateError('there is no session in progress');
    }
    return session;
  }
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
