/// The storage surface the rest of the app codes against.
///
/// See `specs/002-session-persistence/contracts/storage-api.md`. The UI never
/// sees Drift: this interface lives in `lib/data/` while its implementation
/// lives in `lib/data/local/`, as the constitution's layering section requires.
library;

import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/session_record.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// Everything the app stores about sessions.
///
/// Implementations must satisfy the invariants in the contract; the in-memory
/// implementation used by widget tests is held to the same ones.
abstract interface class SessionRepository {
  /// The unfinished session, if there is one (FR-006).
  ///
  /// Returns null when there is none, and **also** when stored data is
  /// unreadable — a corrupt row is treated as absent rather than as an error to
  /// propagate (FR-023, research D10).
  Future<StoredSession?> loadInProgress();

  /// Begins a session, snapshotting the solution and metadata of every position
  /// it contains (research D4).
  ///
  /// Throws [SessionAlreadyInProgressError] if one is already unfinished; the
  /// caller is expected to have warned and discarded first (FR-010).
  Future<StoredSession> start(
    IList<TrainingPosition> positions, {
    DateTime? now,
  });

  /// Commits an attempt and advances, in **one transaction** (FR-005,
  /// research D6): writes the attempt, moves the index, and marks the session
  /// complete when it was the last position.
  Future<void> commitAttempt(String sessionId, Attempt attempt);

  /// Records the player's grade for a position within a session (FR-017).
  ///
  /// Overwrites any grade already recorded for that position in that session;
  /// no earlier grade is kept.
  Future<void> recordGrade(String sessionId, Grade grade, {DateTime? now});

  /// Ends a session without revealing anything (FR-016).
  ///
  /// Deletes attempts and grades and keeps the session row as
  /// [SessionStatus.abandoned]. The snapshot rows stay, but no solution, note
  /// or metadata from an abandoned session is ever handed back out again.
  Future<void> abandon(String sessionId);

  /// Discards an unfinished session so a new one can start (FR-011).
  ///
  /// The same effect as [abandon]; separate so the caller's intent is legible,
  /// and because the player is warned in the same terms either way.
  Future<void> discardInProgress();

  /// Past sessions, newest first (FR-013).
  Future<IList<SessionRecord>> listSessions({int limit, int offset});

  /// Everything needed to re-render a past review from the snapshot (FR-014).
  ///
  /// Returns null for an unknown id. For an abandoned session, returns a record
  /// whose solutions and metadata are **absent** rather than merely hidden by
  /// the UI (FR-016).
  Future<StoredSession?> loadSession(String id);

  /// Removes every stored session, attempt and grade (FR-018).
  Future<void> deleteEverything();
}

/// A session as stored: the record, its position snapshots, its attempts and
/// its grades.
///
/// There is no stored analysis-in-progress. An interruption costs the player
/// the position they were part way through, by decision rather than by
/// omission (FR-003, research D3) — which is why the app has to say so.
@immutable
class StoredSession {
  const StoredSession({
    required this.record,
    required this.positions,
    this.attempts = const IMap.empty(),
    this.grades = const IMap.empty(),
  });

  final SessionRecord record;

  /// In session order.
  final IList<PositionSnapshot> positions;

  /// Committed analyses, by position id.
  final IMap<String, Attempt> attempts;

  /// Self-grades, by position id.
  final IMap<String, Grade> grades;

  String get id => record.id;

  /// True when [positions] carry no solution — an abandoned session.
  bool get answersForfeited =>
      positions.isNotEmpty && positions.every((p) => p.solution == null);

  /// The snapshot for [positionId], or null if this session never held it.
  PositionSnapshot? snapshotFor(String positionId) {
    for (final snapshot in positions) {
      if (snapshot.positionId == positionId) return snapshot;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredSession &&
          record == other.record &&
          positions == other.positions &&
          attempts == other.attempts &&
          grades == other.grades;

  @override
  int get hashCode => Object.hash(record, positions, attempts, grades);

  @override
  String toString() =>
      'StoredSession(${record.id}, ${positions.length} positions, '
      '${attempts.length} attempts)';
}

/// What the player was actually shown, frozen at the time (research D4).
@immutable
class PositionSnapshot {
  const PositionSnapshot({
    required this.positionId,
    required this.ordinal,
    required this.initialPosition,
    this.solution,
    this.metadata,
  });

  final String positionId;

  final int ordinal;

  final Position initialPosition;

  /// Null for an abandoned session: the answers are gone, not hidden.
  final VariationTree? solution;

  /// Null for an abandoned session, for the same reason.
  final PositionMetadata? metadata;

  /// Rebuilds the position as it was presented, for review and for resumption.
  ///
  /// Throws [StateError] when the answers were forfeited — an abandoned
  /// session has no position to rebuild, which is the point.
  TrainingPosition toTrainingPosition() {
    final solution = this.solution;
    if (solution == null) {
      throw StateError(
        'the answers for $positionId were forfeited when its session was '
        'abandoned; there is nothing to rebuild',
      );
    }
    return TrainingPosition(
      id: positionId,
      initialPosition: initialPosition,
      solution: solution,
      metadata: metadata ?? PositionMetadata.empty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionSnapshot &&
          positionId == other.positionId &&
          ordinal == other.ordinal &&
          initialPosition == other.initialPosition &&
          solution == other.solution &&
          metadata == other.metadata;

  @override
  int get hashCode =>
      Object.hash(positionId, ordinal, initialPosition, solution, metadata);

  @override
  String toString() => 'PositionSnapshot($positionId at $ordinal)';
}

// There is deliberately no history repository. A cross-session view of how a
// position has gone before is out of scope: "you failed this one twice" is
// evidence about the position on screen, and the safest way to keep it off the
// training screen is for nothing to be able to ask for it. The grades stored
// against each session are what a later scheduling feature will read.
