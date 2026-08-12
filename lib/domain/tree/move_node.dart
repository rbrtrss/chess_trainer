import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// One move, and the alternatives considered after it.
///
/// A node holds no position. Positions are recomputed by replaying from the
/// root (research D2), which keeps nodes small, value-comparable, and free of a
/// second source of truth that could disagree with the move list.
///
/// [san] is the node's identity: two nodes are the same continuation when their
/// SAN matches. This matters because a castling move has two legal UCI
/// representations but only one SAN.
@immutable
class MoveNode {
  const MoveNode({
    required this.move,
    required this.san,
    this.children = const IList.empty(),
    this.comments = const IList.empty(),
    this.nags = const IList.empty(),
  });

  /// The move itself.
  final Move move;

  /// SAN of [move] in the *parent's* position.
  final String san;

  /// Continuations. `children.first` is the primary line (FR-012).
  ///
  /// No two children share a [san]: replaying a recorded move navigates into it
  /// rather than duplicating it (FR-008).
  final IList<MoveNode> children;

  /// Review-only prose from the solution's PGN (FR-022). Always empty on a node
  /// the user entered — the user is not annotating anything.
  final IList<String> comments;

  /// Review-only annotation glyphs. Always empty on a user-entered node.
  final IList<int> nags;

  MoveNode copyWith({
    IList<MoveNode>? children,
    IList<String>? comments,
    IList<int>? nags,
  }) =>
      MoveNode(
        move: move,
        san: san,
        children: children ?? this.children,
        comments: comments ?? this.comments,
        nags: nags ?? this.nags,
      );

  /// Index of the child continuing with [san], or -1.
  int indexOfChildSan(String san) =>
      children.indexWhere((child) => child.san == san);

  /// This node and its whole subtree.
  int get nodeCount =>
      1 + children.fold(0, (sum, child) => sum + child.nodeCount);

  /// Longest chain of moves from here, counting this node.
  int get depth =>
      1 +
      children.fold(0, (deepest, child) {
        final childDepth = child.depth;
        return childDepth > deepest ? childDepth : deepest;
      });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveNode &&
          move == other.move &&
          san == other.san &&
          children == other.children &&
          comments == other.comments &&
          nags == other.nags;

  @override
  int get hashCode => Object.hash(move, san, children, comments, nags);

  @override
  String toString() =>
      'MoveNode($san${children.isEmpty ? '' : ', ${children.length} children'})';
}
