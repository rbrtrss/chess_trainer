import 'package:chess_trainer/data/engine/evaluator.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// The evaluator every test in feature 005 uses.
///
/// No test can use the real one: `multistockfish` supports Android and iOS
/// only, and `flutter test` runs on the host VM (005 research D8). So this is
/// not a convenience — it is the only way any of this is testable at all, which
/// is why the interface exists.
///
/// It plays the engine's part honestly: it returns a *legal* line from the
/// position it is given, so callers that replay the moves into a tree are
/// exercised against something that actually replays.
class FakeEvaluator implements Evaluator {
  FakeEvaluator({
    this.plies = 4,
    this.score = const Centipawns(35),
    this.answersFor,
  });

  /// How many plies of "best line" to invent.
  final int plies;

  /// What to claim about the position.
  final Score score;

  /// When set, positions this returns false for get a null answer — the
  /// engine-could-not-say case (FR-010).
  final bool Function(Position position)? answersFor;

  /// Every position this was asked about, in order.
  ///
  /// Tests assert on this to prove the engine was **not** consulted where the
  /// contract says it must not be — a terminal position, or an entry that had
  /// an author's line.
  final List<Position> asked = [];

  /// Set to have [bestLine] throw, so callers can prove they do not let an
  /// engine failure escape as an exception.
  Object? failure;

  bool disposed = false;

  @override
  String get engineId => 'fake/1 depth $searchDepth';

  @override
  Future<EngineLine?> bestLine(Position position) async {
    asked.add(position);

    final failure = this.failure;
    if (failure != null) throw failure;

    if (answersFor != null && !answersFor!(position)) return null;

    // Walk the first legal move at each step, so the line is genuinely legal
    // from the position given rather than a plausible-looking fiction.
    final moves = <Move>[];
    var current = position;
    for (var i = 0; i < plies; i++) {
      // `legalMoves` maps *every* piece of the side to move, including ones
      // with nowhere to go, so the first key can carry an empty set. Taking
      // `keys.first` blindly throws on those positions — which the import
      // service catches, quietly turning a working fake into one that always
      // answers `none`. That is exactly how this was found.
      final from = current.legalMoves.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => entry.key)
          .firstOrNull;
      if (from == null) break;

      final to = current.legalMoves[from]!.first;
      if (to == null) break;
      final move = NormalMove(from: from, to: to);
      if (!current.isLegal(move)) break;
      moves.add(move);
      current = current.play(move);
    }

    if (moves.isEmpty) return null;

    return EngineLine(
      moves: IList(moves),
      evaluation: PositionEvaluation(
        score: score,
        depth: searchDepth,
        perspective: position.turn,
      ),
    );
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// An evaluator that fails the test if anything touches it.
///
/// The structural half of FR-019: after import, no engine work happens, so a
/// session that reaches for one is a defect. Modelled on the exploding Lichess
/// client that replaced feature 003's lost offline guarantee.
class ExplodingEvaluator implements Evaluator {
  ExplodingEvaluator(this.onContact);

  /// Called with the method name. Pass `fail` from a test.
  final Never Function(String method) onContact;

  @override
  String get engineId => onContact('engineId');

  @override
  Future<EngineLine?> bestLine(Position position) async =>
      onContact('bestLine');

  @override
  Future<void> dispose() async => onContact('dispose');
}
