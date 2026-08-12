import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/position/training_projection.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// Where a session is in its life.
///
/// ```
///         start              commit (last position)          all graded
/// setup ────────► training ────────────────────────► review ────────────► complete
///                    │                                  │
///                    │ commit (not last) ──┐            │ next / previous ──┐
///                    │ ◄───────────────────┘            │ ◄─────────────────┘
///                    │
///                    └── abandon ──► abandoned   (no answers revealed)
/// ```
enum SessionPhase {
  setup,
  training,
  review,
  complete,
  abandoned;

  /// True where the user is still analysing and nothing may be revealed.
  bool get withholdsFeedback => this == setup || this == training;
}

/// An ordered set of positions and the state of progress through them.
///
/// Every transition returns a new session. The session owns the solutions; the
/// training layer is handed [projectionFor] and nothing else, which is what
/// keeps Principle I a matter of what is in scope rather than a matter of care.
@immutable
class TrainingSession {
  const TrainingSession({
    required this.positions,
    required this.attempts,
    required this.phase,
    required this.currentIndex,
    this.grades = const IMap.empty(),
  });

  /// A session waiting to be started.
  const TrainingSession.setup(this.positions)
      : attempts = const IMap.empty(),
        grades = const IMap.empty(),
        phase = SessionPhase.setup,
        currentIndex = 0;

  /// A session ready to train on [positions].
  ///
  /// Throws [StateError] when there is nothing to train on — an empty session
  /// has no meaningful review and no meaningful end.
  factory TrainingSession.start(IList<TrainingPosition> positions) {
    if (positions.isEmpty) {
      throw StateError('a session needs at least one position');
    }
    return TrainingSession(
      positions: positions,
      attempts: const IMap.empty(),
      phase: SessionPhase.training,
      currentIndex: 0,
    );
  }

  /// Fixed when the session starts.
  final IList<TrainingPosition> positions;

  /// Committed analyses, by position id.
  final IMap<String, Attempt> attempts;

  /// Self-grades, by position id. Empty until review.
  final IMap<String, Grade> grades;

  final SessionPhase phase;

  /// The position being trained, or reviewed, depending on [phase].
  final int currentIndex;

  int get length => positions.length;

  TrainingPosition get currentPosition => positions[currentIndex];

  TrainingPosition positionAt(int index) => positions[index];

  Attempt? attemptFor(String positionId) => attempts[positionId];

  Grade? gradeFor(String positionId) => grades[positionId];

  bool get allPositionsAttempted =>
      positions.every((position) => attempts.containsKey(position.id));

  bool get allPositionsGraded =>
      positions.every((position) => grades.containsKey(position.id));

  bool get isLastPosition => currentIndex == positions.length - 1;

  /// Leaves setup and begins training.
  TrainingSession start() {
    if (phase != SessionPhase.setup) {
      throw StateError('a session can only be started from setup, not $phase');
    }
    if (positions.isEmpty) {
      throw StateError('a session needs at least one position');
    }
    return _copyWith(phase: SessionPhase.training);
  }

  /// **The only way the training phase may read a position** (research D5).
  ///
  /// Returns a [TrainingProjection], which has no path to the solution or the
  /// metadata. Nothing in the training layer should ever need [positionAt].
  TrainingProjection projectionFor(int index) {
    if (index < 0 || index >= positions.length) {
      throw RangeError.index(index, positions, 'index',
          'no position $index in a session of ${positions.length}');
    }
    final position = positions[index];
    return TrainingProjection(
      positionId: position.id,
      initialPosition: position.initialPosition,
      indexInSession: index,
      sessionLength: positions.length,
    );
  }

  /// Records [attempt] and moves on.
  ///
  /// Advances to the next position, or enters review when this was the last one
  /// (FR-016, FR-018). There is no intervening state and nothing is revealed on
  /// the way.
  TrainingSession commitAttempt(Attempt attempt) {
    if (phase != SessionPhase.training) {
      throw StateError('attempts can only be committed while training, not in $phase');
    }
    if (!positions.any((position) => position.id == attempt.positionId)) {
      throw StateError(
          '${attempt.positionId} is not a position in this session');
    }
    if (attempts.containsKey(attempt.positionId)) {
      throw StateError(
          '${attempt.positionId} has already been committed and is immutable');
    }

    final committed = attempts.add(attempt.positionId, attempt);
    final everythingAttempted =
        positions.every((position) => committed.containsKey(position.id));

    return _copyWith(
      attempts: committed,
      phase: everythingAttempted ? SessionPhase.review : SessionPhase.training,
      currentIndex: everythingAttempted ? 0 : currentIndex + 1,
    );
  }

  /// Records the user's own assessment of a reviewed position (FR-026).
  ///
  /// Re-grading replaces the previous value: a user who changes their mind
  /// after stepping through the solution again is doing exactly what review is
  /// for. The session becomes [SessionPhase.complete] once every position has
  /// been graded, but grading never gates navigation (FR-028).
  TrainingSession recordGrade(Grade grade) {
    if (phase != SessionPhase.review && phase != SessionPhase.complete) {
      throw StateError('grades can only be recorded during review, not in $phase');
    }
    if (!positions.any((position) => position.id == grade.positionId)) {
      throw StateError('${grade.positionId} is not a position in this session');
    }

    final recorded = grades.add(grade.positionId, grade);
    final everythingGraded =
        positions.every((position) => recorded.containsKey(position.id));

    return _copyWith(
      grades: recorded,
      phase: everythingGraded ? SessionPhase.complete : SessionPhase.review,
    );
  }

  /// Moves to another position in review.
  ///
  /// Free in both directions and not gated on having graded anything (FR-028).
  TrainingSession goToReviewPosition(int index) {
    if (phase != SessionPhase.review && phase != SessionPhase.complete) {
      throw StateError('review navigation is not available in $phase');
    }
    if (index < 0 || index >= positions.length) {
      throw RangeError.index(index, positions, 'index');
    }
    return _copyWith(currentIndex: index);
  }

  /// Ends the session without revealing anything (FR-019).
  ///
  /// Terminal, and deliberately lossy: the attempts are dropped along with the
  /// session. Keeping them would create a stash of analyses with answers
  /// attached that some later screen could be tempted to show, and the whole
  /// point of abandoning is that the answers are forfeited.
  TrainingSession abandon() => TrainingSession(
        positions: positions,
        attempts: const IMap.empty(),
        grades: const IMap.empty(),
        phase: SessionPhase.abandoned,
        currentIndex: 0,
      );

  TrainingSession _copyWith({
    IList<TrainingPosition>? positions,
    IMap<String, Attempt>? attempts,
    IMap<String, Grade>? grades,
    SessionPhase? phase,
    int? currentIndex,
  }) =>
      TrainingSession(
        positions: positions ?? this.positions,
        attempts: attempts ?? this.attempts,
        grades: grades ?? this.grades,
        phase: phase ?? this.phase,
        currentIndex: currentIndex ?? this.currentIndex,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainingSession &&
          positions == other.positions &&
          attempts == other.attempts &&
          grades == other.grades &&
          phase == other.phase &&
          currentIndex == other.currentIndex;

  @override
  int get hashCode =>
      Object.hash(positions, attempts, grades, phase, currentIndex);

  @override
  String toString() =>
      'TrainingSession($phase, ${currentIndex + 1} of ${positions.length})';
}
