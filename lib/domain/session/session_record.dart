import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// What a stored session's life has come to.
///
/// Deliberately coarser than [SessionPhase], which has `setup`, `training` and
/// `review` besides. Those are phases of a *live* session — which screen is
/// open — and are not worth persisting. What survives a restart is "this
/// session is unfinished", not where the player had got to on screen.
enum SessionStatus {
  inProgress,
  complete,
  abandoned;

  /// The stored spelling. Written into the `status` column, and matched by the
  /// partial unique index that keeps at most one session in progress, so the
  /// two must not drift apart.
  String get stored => switch (this) {
        SessionStatus.inProgress => 'in_progress',
        SessionStatus.complete => 'complete',
        SessionStatus.abandoned => 'abandoned',
      };

  /// The inverse of [stored], or null for a value this app never wrote.
  ///
  /// Null rather than throwing: an unreadable row is treated as absent
  /// (FR-023), and that decision is easier to honour if parsing says "no"
  /// instead of exploding.
  static SessionStatus? fromStored(String value) => switch (value) {
        'in_progress' => SessionStatus.inProgress,
        'complete' => SessionStatus.complete,
        'abandoned' => SessionStatus.abandoned,
        _ => null,
      };

  /// Only an unfinished session may be offered for resumption (FR-009).
  bool get isResumable => this == SessionStatus.inProgress;
}

/// A session that has been persisted — the unit the history list is made of.
///
/// It carries no attempts and no grades: the list shows when a session happened
/// and how big it was, and loading every stored tree to draw a list would make
/// opening the history proportional to a year of use (SC-009).
@immutable
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.positionIds,
    this.endedAt,
    this.currentIndex = 0,
  });

  /// Stable identifier for the session.
  final String id;

  final DateTime startedAt;

  /// Null while in progress.
  final DateTime? endedAt;

  final SessionStatus status;

  /// The positions this session contained, in session order.
  final IList<String> positionIds;

  /// Which position the player was on.
  ///
  /// Meaningless once the session is finished, and carried here because
  /// resuming has to land on the same position and the same place in the count
  /// (FR-004, FR-007). The contract's type sketch omits it; the `sessions` row
  /// has always had it.
  final int currentIndex;

  int get length => positionIds.length;

  bool get isResumable => status.isResumable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionRecord &&
          id == other.id &&
          startedAt == other.startedAt &&
          endedAt == other.endedAt &&
          status == other.status &&
          positionIds == other.positionIds &&
          currentIndex == other.currentIndex;

  @override
  int get hashCode =>
      Object.hash(id, startedAt, endedAt, status, positionIds, currentIndex);

  @override
  String toString() =>
      'SessionRecord($id, ${status.name}, ${positionIds.length} positions)';
}
