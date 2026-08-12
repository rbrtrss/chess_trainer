import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

/// Invariant 7 — the leak barrier (research D5).
///
/// The test is deliberately not "check that the projection has five fields".
/// It builds two positions that differ *only* in their solution and metadata
/// and asserts their projections are indistinguishable. Any future field
/// derived from either — the solution's length, its first move, the theme, a
/// "has hint" flag — makes the two projections differ and fails this test. That
/// is the property worth defending, not the current field list.
void main() {
  const richPgn = '''
[Title "Mate in three by smothering"]
[Goal "White to play and mate"]
[Themes "smothered mate, sacrifice"]
[Rating "2100"]
[Source "A famous study"]
[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]

1. Nh6+ {Double check.} Kh8 2. Qg8+ (2. Nf7+ Kg8) 2... Rxg8 3. Nf7#
''';

  late TrainingPosition rich;
  late TrainingPosition bare;

  setUp(() {
    rich = parseTrainingPosition(richPgn, id: 'shared-id');
    bare = TrainingPosition(
      id: rich.id,
      initialPosition: rich.initialPosition,
      // A different, trivial solution and no metadata at all.
      solution: VariationTree.empty(rich.initialPosition)
          .play(MovePath.root, rich.initialPosition.parseSan('Kh1')!)
          .tree,
      metadata: PositionMetadata.empty,
    );
  });

  test('positions differing only in solution and metadata project identically',
      () {
    final richSession = TrainingSession.start(IList([rich]));
    final bareSession = TrainingSession.start(IList([bare]));

    expect(richSession.projectionFor(0), bareSession.projectionFor(0));
    expect(
      richSession.projectionFor(0).hashCode,
      bareSession.projectionFor(0).hashCode,
    );
  });

  test('the projection carries the board, the turn and the counter, and no more',
      () {
    final session = TrainingSession.start(IList([rich]));
    final projection = session.projectionFor(0);

    expect(projection.positionId, 'shared-id');
    expect(projection.initialPosition, rich.initialPosition);
    expect(projection.sideToMove, Side.white);
    expect(projection.indexInSession, 0);
    expect(projection.sessionLength, 1);
    expect(projection.displayNumber, 1);
  });

  test('no metadata string is reachable through the projection', () {
    final session = TrainingSession.start(IList([rich]));
    final rendered = session.projectionFor(0).toString();

    for (final leak in <String>[
      'Mate in three by smothering',
      'White to play and mate',
      'smothered mate',
      '2100',
      'A famous study',
      'Nh6',
      'mate',
    ]) {
      expect(rendered.toLowerCase(), isNot(contains(leak.toLowerCase())),
          reason: '"$leak" must not be reachable from the training layer');
    }
  });

  test('a projection is equal only to one describing the same board and counter',
      () {
    final two = TrainingSession.start(IList([rich, bare.copyWithId('other')]));

    expect(two.projectionFor(0), isNot(two.projectionFor(1)));
    expect(two.projectionFor(0).sessionLength, 2);
    expect(two.projectionFor(1).indexInSession, 1);
  });

  test('projectionFor rejects an index outside the session', () {
    final session = TrainingSession.start(IList([rich]));

    expect(() => session.projectionFor(1), throwsA(isA<RangeError>()));
    expect(() => session.projectionFor(-1), throwsA(isA<RangeError>()));
  });
}

extension on TrainingPosition {
  TrainingPosition copyWithId(String id) => TrainingPosition(
        id: id,
        initialPosition: initialPosition,
        solution: solution,
        metadata: metadata,
      );
}
