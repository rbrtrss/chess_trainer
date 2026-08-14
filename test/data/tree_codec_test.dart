import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/tree/move_node.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/tree_helpers.dart';

/// Invariant 9: a tree survives storage unchanged.
///
/// Storage keeps trees as PGN text rather than as a bespoke schema (research
/// D2), so this test is the one that stands between a committed analysis and a
/// silent loss of a branch. What must survive is not only the moves but the
/// *shape*: which sibling is primary at every branch point is what `primaryLine`
/// reads, and review's divergence measurement reads that.
void main() {
  group('encodeTree / decodeTree', () {
    test('a wide, deep tree survives the round trip unchanged', () {
      final tree = _bigBranchingTree();

      // The invariant's floor: at least 40 moves across at least 8 branches.
      expect(tree.nodeCount, greaterThanOrEqualTo(40));
      expect(_branchPointCount(tree), greaterThanOrEqualTo(8));

      expect(decodeTree(encodeTree(tree)), tree);
    });

    test('branch ordering survives, so the primary line is still primary', () {
      final tree = _bigBranchingTree();
      final decoded = decodeTree(encodeTree(tree));

      expect(sansOf(decoded.primaryLine), sansOf(tree.primaryLine));

      // And promoting an alternative round trips to the promoted order, not
      // back to the original one.
      final promoted = tree.promote(MovePath.root.child(1));
      final promotedDecoded = decodeTree(encodeTree(promoted));
      expect(sansOf(promotedDecoded.primaryLine), sansOf(promoted.primaryLine));
      expect(promotedDecoded, promoted);
      expect(promotedDecoded, isNot(tree));
    });

    test('comments and NAGs on a snapshotted solution survive', () {
      // A solution parsed from authored PGN is the case that carries prose and
      // glyphs; a user-entered tree never does.
      final position = parseTrainingPosition('''
[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]

1. Nh6+! {Double check, so the king must move.} Kh8 2. Qg8+!! {The point.}
(2. Qf7 {throws the win away}) 2... Rxg8 3. Nf7# {Smothered.}
''', id: 'annotated');

      final decoded = decodeTree(encodeTree(position.solution));

      expect(decoded, position.solution);

      final first = decoded.children.first;
      expect(first.comments, isNotEmpty);
      expect(first.nags, isNotEmpty);
    });

    test('an empty tree round trips as an empty tree', () {
      final empty = VariationTree.empty(Chess.initial);
      final decoded = decodeTree(encodeTree(empty));

      expect(decoded.isEmpty, isTrue);
      expect(decoded, empty);
    });

    test('the initial position is carried in the text, not assumed', () {
      final endgame = Chess.fromSetup(
        Setup.parseFen('8/8/4k3/8/8/4K3/4P3/8 w - - 0 1'),
      );
      final tree = treeFromLine(const ['Kd4', 'Kd6', 'e4'], from: endgame);

      final pgn = encodeTree(tree);
      expect(pgn, contains('[FEN "8/8/4k3/8/8/4K3/4P3/8 w - - 0 1"]'));
      expect(decodeTree(pgn).initialPosition.fen, endgame.fen);
    });
  });

  group('decodeTree rejects what it cannot replay', () {
    test('text with no [FEN] header', () {
      expect(
        () => decodeTree('1. e4 e5 2. Nf3'),
        throwsA(isA<TreeDecodeError>()),
      );
    });

    test('an invalid [FEN] header', () {
      expect(
        () => decodeTree('[FEN "not a position"]\n\n1. e4'),
        throwsA(isA<TreeDecodeError>()),
      );
    });

    test('a move that is illegal in the position it is played from', () {
      expect(
        () => decodeTree(
          '[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]\n\n1. e4',
        ),
        throwsA(isA<TreeDecodeError>()),
      );
    });

    test('a truncated row', () {
      expect(
        () => decodeTree('[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPP'),
        throwsA(isA<TreeDecodeError>()),
      );
    });

    test('an empty string', () {
      expect(() => decodeTree(''), throwsA(isA<TreeDecodeError>()));
    });
  });
}

/// A tree of at least 40 moves across at least 8 branch points, built the way a
/// player builds one: a main line, then alternatives rewound to at various
/// depths, some of them nested.
VariationTree _bigBranchingTree() {
  var tree = treeFromLine(const [
    'e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6', 'O-O', 'Be7',
    'Re1', 'b5', 'Bb3', 'd6', 'c3', 'O-O', 'h3', 'Na5', 'Bc2', 'c5',
  ]);

  // Alternatives at eight different points along that line, each played by
  // whichever side is to move there.
  tree = addLine(tree, MovePath.root, const ['d4', 'd5', 'c4', 'e6']);
  tree = addLine(tree, pathOfDepth(1), const ['c5', 'Nf3', 'd6']);
  tree = addLine(tree, pathOfDepth(2), const ['Nc3', 'Nf6', 'Bc4']);
  tree = addLine(tree, pathOfDepth(4), const ['Bc4', 'Bc5', 'b4']);
  tree = addLine(tree, pathOfDepth(6), const ['Bxc6', 'dxc6', 'O-O']);
  tree = addLine(tree, pathOfDepth(8), const ['d3', 'b5', 'Bb3']);
  tree = addLine(tree, pathOfDepth(10), const ['d4', 'exd4', 'e5']);
  tree = addLine(tree, pathOfDepth(12), const ['c3', 'd6', 'd4']);
  // One nested inside an alternative, so the shape is not a fan of lines off
  // the main one.
  tree = addLine(tree, MovePath.root.child(1).child(0), const ['Nf3', 'Nf6']);

  return tree;
}

/// Nodes with more than one child — the places where storage could silently
/// reorder or drop a line.
int _branchPointCount(VariationTree tree) {
  var count = tree.children.length > 1 ? 1 : 0;
  void walk(MoveNode node) {
    if (node.children.length > 1) count++;
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final child in tree.children) {
    walk(child);
  }
  return count;
}
