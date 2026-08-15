/// What an engine determined about a position, and where a solution came from.
///
/// Pure Dart. No engine type, no UCI string, no process handle reaches this
/// layer — the engine lives behind `lib/data/engine/` and the constitution's
/// Principle III now says so in as many words.
///
/// **None of this may reach a training screen.** It is a solution, and a
/// solution is evidence; `TrainingProjection` does not carry it and
/// `test/domain/layering_test.dart` forbids the training directory from naming
/// any of these types (005 FR-020).
library;

import 'package:dartchess/dartchess.dart';
import 'package:meta/meta.dart';

/// What standard an attempt is measured against.
enum SolutionSource {
  /// The source PGN contained moves. Everything behaves as it did before
  /// feature 005.
  author,

  /// The source declared a position and no moves, and the line stored is an
  /// engine's (005 FR-007).
  engine,

  /// The source declared a position and no moves, and no evaluation could be
  /// produced. The solution tree is empty.
  ///
  /// **A state, not an error** (005 FR-010). The position stays trainable; the
  /// review says plainly that there is no evaluation rather than showing a
  /// blank pane.
  none,
}

/// An engine's assessment of a position.
///
/// Named `PositionEvaluation` rather than `Evaluation` because `flutter_test`
/// exports an `Evaluation` of its own, from its accessibility guidelines, and
/// every test that touched both would otherwise need a `hide`. A one-time
/// rename is cheaper than that tax on every file, and this name reads better at
/// the call site anyway.
///
/// Sealed because "+1.4" and "mate in 3" are different kinds of claim and a
/// single number cannot carry the second. A mate score crammed into centipawns
/// is the sort of thing that reads as 327.68 pawns at review.
@immutable
sealed class Score {
  const Score();
}

/// A positional assessment in centipawns, from [PositionEvaluation.perspective].
final class Centipawns extends Score {
  const Centipawns(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Centipawns && value == other.value;

  @override
  int get hashCode => Object.hash(Centipawns, value);

  @override
  String toString() => 'Centipawns($value)';
}

/// A forced mate in [plies], from [PositionEvaluation.perspective].
///
/// Negative when the side evaluated is the one being mated.
final class MateIn extends Score {
  const MateIn(this.plies);

  final int plies;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MateIn && plies == other.plies;

  @override
  int get hashCode => Object.hash(MateIn, plies);

  @override
  String toString() => 'MateIn($plies)';
}

/// What the engine said about a position, and the instrument it said it with.
@immutable
class PositionEvaluation {
  const PositionEvaluation({
    required this.score,
    required this.depth,
    required this.perspective,
  });

  final Score score;

  /// The search depth this came from.
  ///
  /// Recorded for the same reason a scientist records their instrument: a
  /// depth-20 line and a depth-8 line are different claims, and a position
  /// imported by an old build should not be silently compared with one imported
  /// by a new one (005 research D5).
  final int depth;

  /// Whose advantage [score] describes.
  ///
  /// Stored explicitly rather than implied by the side to move, because a value
  /// read back in a year should not need a convention to interpret.
  final Side perspective;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionEvaluation &&
          score == other.score &&
          depth == other.depth &&
          perspective == other.perspective;

  @override
  int get hashCode => Object.hash(score, depth, perspective);

  @override
  String toString() => 'PositionEvaluation($score at depth $depth for $perspective)';
}
