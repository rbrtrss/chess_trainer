import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// Everything known about a position to be trained.
///
/// The training phase never sees one of these. It is given a
/// [TrainingProjection] instead, which is how the solution stays out of reach
/// of the code that draws the board.
@immutable
class TrainingPosition {
  const TrainingPosition({
    required this.id,
    required this.initialPosition,
    required this.solution,
    this.metadata = PositionMetadata.empty,
  });

  /// Stable identifier — the bundled asset's basename for now.
  final String id;

  /// Where training starts.
  final Position initialPosition;

  /// The intended answer. Its `primaryLine` is the main line.
  final VariationTree solution;

  /// Withheld during training (FR-003), revealed at review (FR-025).
  final PositionMetadata metadata;

  /// The one fact disclosed during training.
  Side get sideToMove => initialPosition.turn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainingPosition &&
          id == other.id &&
          initialPosition == other.initialPosition &&
          solution == other.solution &&
          metadata == other.metadata;

  @override
  int get hashCode => Object.hash(id, initialPosition, solution, metadata);

  @override
  String toString() => 'TrainingPosition($id)';
}

/// The evidence about a position that must not be rendered during training.
///
/// It is one importable type rather than five loose fields on [TrainingPosition]
/// precisely so that "everything that must be hidden" is a thing you can point
/// at, instead of a list somebody has to remember.
@immutable
class PositionMetadata {
  const PositionMetadata({
    this.title,
    this.goal,
    this.themes = const IList.empty(),
    this.rating,
    this.source,
  });

  static const PositionMetadata empty = PositionMetadata();

  /// "Chapter 3: Winning the Opposition" tells the user the answer.
  final String? title;

  /// Win, draw, hold — knowing which is a large hint.
  final String? goal;

  /// Puzzle themes: "fork", "back rank mate".
  final IList<String> themes;

  /// Difficulty.
  final int? rating;

  /// Where the position came from.
  final String? source;

  bool get isEmpty =>
      title == null &&
      goal == null &&
      themes.isEmpty &&
      rating == null &&
      source == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionMetadata &&
          title == other.title &&
          goal == other.goal &&
          themes == other.themes &&
          rating == other.rating &&
          source == other.source;

  @override
  int get hashCode => Object.hash(title, goal, themes, rating, source);

  @override
  String toString() => 'PositionMetadata(${title ?? 'untitled'})';
}
