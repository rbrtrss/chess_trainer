import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tree_helpers.dart';

void main() {
  group('MovePath', () {
    test('the root is empty and has no parent', () {
      expect(MovePath.root.isRoot, isTrue);
      expect(MovePath.root.length, 0);
      expect(MovePath.root.parent, isNull);
      expect(MovePath.root.lastIndex, isNull);
    });

    test('child and parent are inverses', () {
      final path = MovePath.root.child(0).child(2);
      expect(path.length, 2);
      expect(path.lastIndex, 2);
      expect(path.parent, MovePath.root.child(0));
    });

    test('has value equality and a readable toString', () {
      expect(MovePath.root.child(1).child(0), MovePath.root.child(1).child(0));
      expect(MovePath.root.child(1).child(0).hashCode,
          MovePath.root.child(1).child(0).hashCode);
      expect(MovePath.root.child(1).child(0).toString(), 'MovePath(1.0)');
    });
  });

  group('reading a tree', () {
    test('an empty tree is empty at every accessor', () {
      final tree = VariationTree.empty(Chess.initial);
      expect(tree.isEmpty, isTrue);
      expect(tree.nodeCount, 0);
      expect(tree.depth, 0);
      expect(tree.primaryLine, isEmpty);
      expect(tree.nodeAt(MovePath.root), isNull);
      expect(tree.positionAt(MovePath.root), Chess.initial);
    });

    test('positionAt replays from the initial position', () {
      final tree = treeFromLine(['e4', 'e5', 'Nf3']);

      expect(tree.positionAt(MovePath.root), Chess.initial);
      expect(tree.positionAt(pathOfDepth(1)).turn, Side.black);
      expect(tree.positionAt(pathOfDepth(3)).turn, Side.black);
      expect(
        tree.positionAt(pathOfDepth(3)).fen,
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
      );
    });

    test('positionAt walks into a branch, not the primary line', () {
      var tree = treeFromLine(['e4', 'e5']);
      tree = tree.play(MovePath.root, tree.initialPosition.parseSan('d4')!).tree;

      expect(tree.positionAt(MovePath.root.child(1)).fen,
          'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1');
    });

    test('nodeAt addresses nodes on any branch', () {
      var tree = treeFromLine(['e4', 'e5']);
      tree = tree.play(MovePath.root, tree.initialPosition.parseSan('d4')!).tree;

      expect(tree.nodeAt(MovePath.root.child(0))!.san, 'e4');
      expect(tree.nodeAt(MovePath.root.child(1))!.san, 'd4');
      expect(tree.nodeAt(pathOfDepth(2))!.san, 'e5');
    });

    test('nodeCount and depth count the whole tree and the longest line', () {
      var tree = treeFromLine(['e4', 'e5', 'Nf3', 'Nc6']);
      tree = addLine(tree, pathOfDepth(2), ['Bc4']);

      expect(tree.nodeCount, 5);
      expect(tree.depth, 4);
    });

    test('primaryLine follows first children only', () {
      var tree = treeFromLine(['e4', 'e5', 'Nf3']);
      tree = addLine(tree, pathOfDepth(2), ['Bc4', 'Bc5', 'Qh5']);

      expect(sansOf(tree.primaryLine), ['e4', 'e5', 'Nf3']);
    });

    test('childrenAt returns the first moves at the root', () {
      final tree = treeFromLine(['e4']);
      expect(tree.childrenAt(MovePath.root), tree.children);
    });
  });

  group('legalMovesAt', () {
    test('gives 20 moves in the initial position', () {
      final tree = VariationTree.empty(Chess.initial);
      expect(tree.legalMovesAt(MovePath.root).length, 20);
    });

    test('expands promotions into four moves', () {
      final position = Chess.fromSetup(Setup.parseFen('8/P6k/8/8/8/8/7K/8 w - - 0 1'));
      final tree = VariationTree.empty(position);
      final moves = tree.legalMovesAt(MovePath.root);
      final promotions = moves
          .where((move) => move is NormalMove && move.from == Square.a7)
          .toList();

      expect(promotions.length, 4);
      expect(
        promotions.map((move) => (move as NormalMove).promotion).toSet(),
        {Role.queen, Role.rook, Role.bishop, Role.knight},
      );
    });

    test('is empty at a checkmate', () {
      final tree = treeFromLine(['f3', 'e5', 'g4', 'Qh4#']);
      expect(tree.legalMovesAt(pathOfDepth(4)), isEmpty);
      expect(tree.isTerminalAt(pathOfDepth(4)), isTrue);
      expect(tree.isTerminalAt(pathOfDepth(3)), isFalse);
    });
  });

  group('errors', () {
    test('a stale path throws InvalidPathError', () {
      var tree = treeFromLine(['e4', 'e5']);
      tree = tree.play(MovePath.root, tree.initialPosition.parseSan('d4')!).tree;
      final staleCursor = MovePath.root.child(1);

      final pruned = tree.delete(staleCursor);

      expect(() => pruned.nodeAt(staleCursor), throwsA(isA<InvalidPathError>()));
      expect(() => pruned.positionAt(staleCursor), throwsA(isA<InvalidPathError>()));
    });

    test('an illegal move throws IllegalMoveError', () {
      final tree = VariationTree.empty(Chess.initial);
      expect(
        () => tree.play(MovePath.root, NormalMove(from: Square.e2, to: Square.e5)),
        throwsA(isA<IllegalMoveError>()),
      );
    });

    test('deleting the root is rejected', () {
      final tree = treeFromLine(['e4']);
      expect(() => tree.delete(MovePath.root), throwsA(isA<InvalidPathError>()));
    });
  });

  group('value equality', () {
    test('two trees built the same way are equal', () {
      expect(treeFromLine(['e4', 'e5']), treeFromLine(['e4', 'e5']));
      expect(treeFromLine(['e4', 'e5']).hashCode,
          treeFromLine(['e4', 'e5']).hashCode);
    });

    test('trees differing only in branch order are not equal', () {
      var withE4First = treeFromLine(['e4']);
      withE4First =
          withE4First.play(MovePath.root, Chess.initial.parseSan('d4')!).tree;
      final withD4First = withE4First.promote(MovePath.root.child(1));

      expect(withD4First, isNot(withE4First));
    });
  });
}
