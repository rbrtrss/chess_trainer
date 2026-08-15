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
///
/// Feature 003 changed what this type *means*. Until imports existed, every
/// string that could reach a screen was written by us and reviewed, so naming
/// five fields was enough. Imported content carries text written by someone
/// else, including headers we have never heard of, and a five-field allowlist
/// silently drops them — safe for Principle I today, and wrong the first time
/// somebody wants a sixth field shown at review, because the default flips back
/// to allow-by-omission.
///
/// [headers] inverts that: **everything** the entry carried is captured, and
/// withholding becomes a property of where this type can be reached from rather
/// than a list somebody maintains. Nothing here is reachable from
/// [TrainingProjection], which is why adding a field to *that* type remains the
/// one thing this design forbids.
///
/// The first real study we tried proved the point — `[StudyName]` and
/// `[ChapterName]` are what Lichess writes, and `[ChapterName]` is literally
/// the "Chapter 3: Winning the Opposition" case the constitution names. Neither
/// was in the five fields (003 research D11).
@immutable
class PositionMetadata {
  const PositionMetadata({
    this.title,
    this.goal,
    this.themes = const IList.empty(),
    this.rating,
    this.source,
    this.headers = const IMap.empty(),
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

  /// Every header the entry carried, verbatim, keyed by PGN tag name.
  ///
  /// Includes the tags the typed fields above are derived from, and every tag
  /// this app has never heard of. Unlike the typed fields it keeps `?`, PGN's
  /// "unknown": a review that shows `[Date "?"]` is being honest about what the
  /// file said, whereas a training screen shows none of this at all.
  final IMap<String, String> headers;

  bool get isEmpty =>
      title == null &&
      goal == null &&
      themes.isEmpty &&
      rating == null &&
      source == null &&
      headers.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionMetadata &&
          title == other.title &&
          goal == other.goal &&
          themes == other.themes &&
          rating == other.rating &&
          source == other.source &&
          headers == other.headers;

  @override
  int get hashCode =>
      Object.hash(title, goal, themes, rating, source, headers);

  @override
  String toString() => 'PositionMetadata(${title ?? 'untitled'})';
}
