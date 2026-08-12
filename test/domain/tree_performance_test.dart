import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tree_helpers.dart';

/// SC-006: board interaction stays responsive with an analysis of at least 40
/// moves across at least 8 branches.
///
/// This does not measure frames — it measures the domain operations a frame
/// waits on. Positions are recomputed by replaying from the root (research D2)
/// rather than cached, and that decision is only defensible while replay stays
/// far inside a frame budget. If it stops being, this test is where it shows.
void main() {
  /// A tree of roughly 40 moves spread over 8-plus branches, in the shape a
  /// user actually produces: a main line with alternatives hung off it.
  VariationTree buildLargeTree() {
    var tree = treeFromLine([
      'e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4',
      'Nf6', 'O-O', 'Be7', 'Re1', 'b5', 'Bb3', 'd6',
    ]);

    // Alternatives at eight different points along the main line.
    tree = addLine(tree, MovePath.root, ['d4', 'd5', 'c4', 'e6']);
    tree = addLine(tree, pathOfDepth(1), ['c5', 'Nf3', 'd6']);
    tree = addLine(tree, pathOfDepth(2), ['Nc3', 'Nf6']);
    tree = addLine(tree, pathOfDepth(3), ['Nf6', 'Nxe5']);
    tree = addLine(tree, pathOfDepth(4), ['Bc4', 'Bc5', 'c3']);
    tree = addLine(tree, pathOfDepth(5), ['Nd4', 'Nxd4']);
    tree = addLine(tree, pathOfDepth(6), ['Bxc6', 'dxc6']);
    tree = addLine(tree, pathOfDepth(7), ['b5', 'Bb3']);
    tree = addLine(tree, pathOfDepth(8), ['d3', 'b5']);
    tree = addLine(tree, pathOfDepth(10), ['d4', 'exd4']);
    tree = addLine(tree, pathOfDepth(11), ['O-O', 'c3']);
    tree = addLine(tree, pathOfDepth(12), ['c3', 'Bb7']);

    return tree;
  }

  test('the fixture really is 40-plus moves across 8-plus branches', () {
    final tree = buildLargeTree();

    expect(tree.nodeCount, greaterThanOrEqualTo(40));
    expect(_branchPoints(tree, MovePath.root), greaterThanOrEqualTo(8));
  });

  test('reading the deepest position stays far inside a frame', () {
    final tree = buildLargeTree();
    final deepest = pathOfDepth(14);

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      tree.positionAt(deepest);
    }
    stopwatch.stop();

    final perCall = stopwatch.elapsedMicroseconds / 100;
    expect(perCall, lessThan(2000),
        reason: 'replaying to the deepest node took ${perCall}us, which is a '
            'large share of a 16ms frame');
  });

  test('playing a move into a large tree stays inside a frame', () {
    final tree = buildLargeTree();
    final at = pathOfDepth(9);
    final move = tree.positionAt(at).parseSan('d6')!;

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      tree.play(at, move);
    }
    stopwatch.stop();

    final perCall = stopwatch.elapsedMicroseconds / 100;
    expect(perCall, lessThan(4000),
        reason: 'a move took ${perCall}us — the board waits on this');
  });

  test('the whole-tree reads a frame needs stay inside a frame', () {
    final tree = buildLargeTree();

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      tree.nodeCount;
      tree.depth;
      tree.primaryLine;
      tree.legalMovesAt(MovePath.root);
    }
    stopwatch.stop();

    final perFrame = stopwatch.elapsedMicroseconds / 100;
    expect(perFrame, lessThan(8000),
        reason: 'one frame of tree reads took ${perFrame}us of a 16ms budget');
  });

  test('promotion and deletion on a large tree are cheap', () {
    final tree = buildLargeTree();
    final branch = pathOfDepth(5).child(1);

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      tree.promote(branch);
      tree.delete(branch);
    }
    stopwatch.stop();

    final perPair = stopwatch.elapsedMicroseconds / 100;
    expect(perPair, lessThan(4000), reason: 'structural edits took ${perPair}us');
  });
}

int _branchPoints(VariationTree tree, MovePath path) {
  final children = tree.childrenAt(path);
  var count = children.length > 1 ? 1 : 0;
  for (var i = 0; i < children.length; i++) {
    count += _branchPoints(tree, path.child(i));
  }
  return count;
}
