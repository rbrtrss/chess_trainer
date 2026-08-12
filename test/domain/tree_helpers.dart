import 'package:chess_trainer/domain/tree/move_node.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// Plays [san] at [at], failing loudly if it is not legal there — a typo in a
/// test fixture should not look like a domain bug.
TreeEdit playSan(VariationTree tree, MovePath at, String san) {
  final position = tree.positionAt(at);
  final move = position.parseSan(san);
  if (move == null) {
    throw ArgumentError('$san is not legal in ${position.fen}');
  }
  return tree.play(at, move);
}

/// A tree containing exactly one line, given as SAN.
VariationTree treeFromLine(List<String> sans, {Position? from}) {
  var tree = VariationTree.empty(from ?? Chess.initial);
  var path = MovePath.root;
  for (final san in sans) {
    final edit = playSan(tree, path, san);
    tree = edit.tree;
    path = edit.path;
  }
  return tree;
}

/// Adds [sans] as a line starting at [at].
VariationTree addLine(VariationTree tree, MovePath at, List<String> sans) {
  var current = tree;
  var path = at;
  for (final san in sans) {
    final edit = playSan(current, path, san);
    current = edit.tree;
    path = edit.path;
  }
  return current;
}

/// The path that follows the primary line down [plies] levels.
MovePath pathOfDepth(int plies) {
  var path = MovePath.root;
  for (var i = 0; i < plies; i++) {
    path = path.child(0);
  }
  return path;
}

List<String> sansOf(IList<MoveNode> nodes) =>
    nodes.map((node) => node.san).toList();
