import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tree_helpers.dart';

/// Invariants 1-3 from contracts/domain-api.md — the branching behaviour the
/// whole feature rests on.
void main() {
  group('invariant 1: replaying a recorded move navigates, never duplicates', () {
    test('playing the same move twice from the root yields one child', () {
      final first = playSan(VariationTree.empty(Chess.initial), MovePath.root, 'e4');
      final second = first.tree.play(
        MovePath.root,
        first.tree.positionAt(MovePath.root).parseSan('e4')!,
      );

      expect(second.tree.nodeCount, first.tree.nodeCount);
      expect(second.tree.children.length, 1);
      expect(second.path, MovePath.root.child(0));
      expect(second.createdBranch, isFalse);
      expect(second.tree, first.tree, reason: 'the tree is returned unchanged');
    });

    test('re-entering an existing move mid-line navigates into it', () {
      final tree = treeFromLine(['e4', 'e5', 'Nf3']);
      final atE5 = MovePath.root.child(0).child(0);

      final edit = tree.play(atE5, tree.positionAt(atE5).parseSan('Nf3')!);

      expect(edit.tree.nodeCount, 3, reason: 'no new node');
      expect(edit.path, atE5.child(0));
      expect(edit.createdBranch, isFalse);
    });

    test('castling entered as king-to-g1 matches castling entered as king-takes-rook',
        () {
      var tree = treeFromLine(['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5']);
      final beforeCastle = pathOfDepth(6);

      final asKingTakesRook = NormalMove(from: Square.e1, to: Square.h1);
      final asTwoSquares = NormalMove(from: Square.e1, to: Square.g1);

      final firstEdit = tree.play(beforeCastle, asKingTakesRook);
      tree = firstEdit.tree;
      final secondEdit = tree.play(beforeCastle, asTwoSquares);

      expect(tree.nodeAt(firstEdit.path)!.san, 'O-O');
      expect(secondEdit.tree.nodeCount, tree.nodeCount,
          reason: 'the two spellings are one node');
      expect(secondEdit.path, firstEdit.path);
      expect(secondEdit.createdBranch, isFalse);
    });
  });

  group('invariant 2: branching leaves the original subtree intact', () {
    test('a different move at an existing node creates a sibling', () {
      // Story 1 scenario 3: play a line, step back two plies, play something else.
      final original = treeFromLine(['e4', 'e5', 'Nf3', 'Nc6']);
      final stepBackTwo = pathOfDepth(2);

      final edit = original.play(
        stepBackTwo,
        original.positionAt(stepBackTwo).parseSan('Bc4')!,
      );
      final branched = edit.tree;

      expect(edit.createdBranch, isTrue);
      expect(edit.path, stepBackTwo.child(1));
      expect(branched.childrenAt(stepBackTwo).length, 2);

      // The original continuation is untouched, and still primary.
      expect(branched.childrenAt(stepBackTwo).first.san, 'Nf3');
      expect(branched.childrenAt(stepBackTwo).first.children.first.san, 'Nc6');
      expect(sansOf(branched.primaryLine), ['e4', 'e5', 'Nf3', 'Nc6']);
      expect(branched.nodeCount, 5);
    });

    test('the tree the branch came from is itself unchanged', () {
      final original = treeFromLine(['e4', 'e5', 'Nf3', 'Nc6']);
      final stepBackTwo = pathOfDepth(2);

      original.play(
        stepBackTwo,
        original.positionAt(stepBackTwo).parseSan('Bc4')!,
      );

      expect(original.nodeCount, 4, reason: 'play returns a new tree, never mutates');
      expect(original.childrenAt(stepBackTwo).length, 1);
    });

    test('branching deep in a subtree leaves siblings above it alone', () {
      var tree = treeFromLine(['e4', 'e5', 'Nf3']);
      tree = tree.play(MovePath.root, tree.initialPosition.parseSan('d4')!).tree;

      final afterNf3 = pathOfDepth(3);
      tree = tree.play(afterNf3, tree.positionAt(afterNf3).parseSan('Nc6')!).tree;
      tree = tree.play(afterNf3, tree.positionAt(afterNf3).parseSan('d6')!).tree;

      expect(tree.children.length, 2, reason: 'e4 and d4 both still first moves');
      expect(tree.children[1].san, 'd4');
      expect(tree.children[1].children, isEmpty);
      expect(sansOf(tree.childrenAt(afterNf3)), ['Nc6', 'd6']);
    });
  });

  group('invariant 3: promote changes ordering only', () {
    test('promoting a sibling makes it primary and keeps every node', () {
      var tree = treeFromLine(['e4', 'e5']);
      tree = tree.play(MovePath.root, tree.initialPosition.parseSan('d4')!).tree;
      final d4Path = MovePath.root.child(1);
      tree = tree.play(d4Path, tree.positionAt(d4Path).parseSan('d5')!).tree;

      final before = tree.nodeCount;
      final promoted = tree.promote(d4Path);

      expect(promoted.nodeCount, before);
      expect(sansOf(promoted.children), ['d4', 'e4']);
      expect(sansOf(promoted.primaryLine), ['d4', 'd5']);
      // Both lines survive, with their subtrees.
      expect(promoted.children[1].children.first.san, 'e5');
    });

    test('promoting the first child is a no-op', () {
      final tree = treeFromLine(['e4', 'e5']);
      expect(tree.promote(MovePath.root.child(0)), tree);
    });

    test('promoting deep in the tree reorders only that parent', () {
      var tree = treeFromLine(['e4', 'e5', 'Nf3']);
      final afterE5 = pathOfDepth(2);
      tree = tree.play(afterE5, tree.positionAt(afterE5).parseSan('Bc4')!).tree;

      final promoted = tree.promote(afterE5.child(1));

      expect(sansOf(promoted.childrenAt(afterE5)), ['Bc4', 'Nf3']);
      expect(promoted.children.first.san, 'e4', reason: 'the root order is untouched');
      expect(promoted.nodeCount, tree.nodeCount);
    });

    test('promoting the root is rejected', () {
      final tree = treeFromLine(['e4']);
      expect(() => tree.promote(MovePath.root), throwsA(isA<Error>()));
    });
  });

  group('delete removes the node and its subtree (FR-011)', () {
    test('deleting a branch leaves the primary line alone', () {
      var tree = treeFromLine(['e4', 'e5', 'Nf3']);
      tree = tree.play(MovePath.root, tree.initialPosition.parseSan('d4')!).tree;

      final pruned = tree.delete(MovePath.root.child(1));

      expect(pruned.children.length, 1);
      expect(sansOf(pruned.primaryLine), ['e4', 'e5', 'Nf3']);
    });

    test('deleting a node removes everything below it', () {
      final tree = treeFromLine(['e4', 'e5', 'Nf3', 'Nc6']);
      // Delete Nf3, the third ply — Nc6 hangs below it and must go too.
      final pruned = tree.delete(pathOfDepth(3));

      expect(pruned.nodeCount, 2);
      expect(sansOf(pruned.primaryLine), ['e4', 'e5']);
    });
  });
}
