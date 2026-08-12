import 'package:dartchess/dartchess.dart';
import 'package:meta/meta.dart';

/// What the training phase is allowed to know about a position.
///
/// **This type is the leak barrier** (research D5). Principle I is the
/// requirement most likely to be violated accidentally, months later, by a
/// well-meaning change — and such a violation leaves every test green and the
/// app looking fine. Keeping the solution out of scope makes leaking code fail
/// to compile rather than fail to be noticed.
///
/// **Do not add a field derived from `TrainingPosition.solution` or
/// `TrainingPosition.metadata`, and do not give this type a reference back to
/// the position it came from.** Not the solution's length, not whether a
/// solution exists, not the theme, not the rating, not a title. That is the
/// entire purpose of this type; a field that "seems harmless" is how the
/// barrier gets dismantled.
@immutable
class TrainingProjection {
  const TrainingProjection({
    required this.positionId,
    required this.initialPosition,
    required this.indexInSession,
    required this.sessionLength,
  });

  /// Identifies the position so an attempt can be filed against it. Carries no
  /// information about the answer.
  final String positionId;

  /// The board to show.
  final Position initialPosition;

  /// Zero-based index within the session, for the plain "N of M" counter.
  final int indexInSession;

  /// Total positions in the session.
  final int sessionLength;

  /// The only fact the user is told (Constitution, Principle I).
  Side get sideToMove => initialPosition.turn;

  /// One-based, for display.
  int get displayNumber => indexInSession + 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainingProjection &&
          positionId == other.positionId &&
          initialPosition == other.initialPosition &&
          indexInSession == other.indexInSession &&
          sessionLength == other.sessionLength;

  @override
  int get hashCode =>
      Object.hash(positionId, initialPosition, indexInSession, sessionLength);

  @override
  String toString() =>
      'TrainingProjection($positionId, $displayNumber of $sessionLength)';
}
