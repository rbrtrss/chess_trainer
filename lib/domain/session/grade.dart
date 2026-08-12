import 'package:meta/meta.dart';

/// The user's own assessment of one reviewed position.
///
/// These four bands match SM-2's grade bands, so the spaced-repetition feature
/// can consume them without a migration. Nothing in this feature interprets
/// them: they are recorded, not scored.
enum GradeValue {
  failed,
  hard,
  good,
  easy;

  String get label => switch (this) {
        GradeValue.failed => 'Missed it',
        GradeValue.hard => 'Hard',
        GradeValue.good => 'Good',
        GradeValue.easy => 'Easy',
      };
}

/// The authoritative record of how a position went (FR-027).
///
/// Authoritative over the match indicator, which is a measurement of one line
/// against one line and cannot see the thinking that produced it.
@immutable
class Grade {
  const Grade({required this.positionId, required this.value});

  final String positionId;
  final GradeValue value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Grade &&
          positionId == other.positionId &&
          value == other.value;

  @override
  int get hashCode => Object.hash(positionId, value);

  @override
  String toString() => 'Grade($positionId, ${value.name})';
}
