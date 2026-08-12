import 'package:chess_trainer/data/bundled_position_source.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pgn_position_parser_test.dart' show expectEveryNodeLegal;

/// The bundled positions are hand-authored, so they are exactly the kind of
/// content that can be subtly wrong — an illegal move in a variation, a FEN
/// that does not match the line. This test is the check that they are sound.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const source = BundledPositionSource();

  test('every bundled PGN parses into a usable position', () async {
    final positions = await source.loadAll();

    expect(positions, isNotEmpty);
    for (final position in positions) {
      expect(position.id, isNotEmpty);
      expect(position.solution.isEmpty, isFalse,
          reason: '${position.id} has no solution');
      expectEveryNodeLegal(position.solution);
    }
  });

  test('the sample set spans a tactic, a quiet choice and an endgame', () async {
    final positions = await source.loadAll();

    expect(positions.length, greaterThanOrEqualTo(3));
    expect(
      positions.map((position) => position.id).toList(),
      containsAll(<String>['001-tactic', '002-positional', '003-endgame']),
    );
  });

  test('each position carries metadata and at least one annotated move',
      () async {
    final positions = await source.loadAll();

    for (final position in positions) {
      expect(position.metadata.isEmpty, isFalse,
          reason: '${position.id} has no metadata to reveal at review');
      expect(position.metadata.title, isNotNull);

      final annotated = position.solution.primaryLine
          .any((node) => node.comments.isNotEmpty);
      expect(annotated, isTrue,
          reason: '${position.id} has no notes for FR-022 to display');
    }
  });

  test('each position offers a real branch to explore at review', () async {
    final positions = await source.loadAll();

    for (final position in positions) {
      final hasBranch = _anyBranch(position.solution, MovePath.root);
      expect(hasBranch, isTrue,
          reason: '${position.id} records no alternative line');
    }
  });
}

bool _anyBranch(VariationTree tree, MovePath path) {
  final children = tree.childrenAt(path);
  if (children.length > 1) return true;
  for (var i = 0; i < children.length; i++) {
    if (_anyBranch(tree, path.child(i))) return true;
  }
  return false;
}
