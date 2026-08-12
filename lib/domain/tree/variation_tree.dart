import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/tree/move_node.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// An immutable tree of variations rooted at a starting position.
///
/// The same type serves both the intended solution of a training position and
/// the analysis a user enters, which is what makes comparing them at review a
/// walk over two values of one shape rather than a translation.
///
/// Every operation returns a new tree. Nothing here mutates, which is what
/// makes a committed [Attempt] genuinely frozen (FR-015).
@immutable
class VariationTree {
  const VariationTree({
    required this.initialPosition,
    this.children = const IList.empty(),
  });

  /// An empty tree from [position] — a valid committed attempt, meaning
  /// "I have no idea".
  const VariationTree.empty(Position position)
      : this(initialPosition: position);

  /// The position being analysed. Move 1 is played from here.
  final Position initialPosition;

  /// First moves. `children.first` is the primary line (FR-012).
  final IList<MoveNode> children;

  bool get isEmpty => children.isEmpty;

  bool get isNotEmpty => children.isNotEmpty;

  /// The line reached by always taking the first child — what FR-021 and
  /// FR-023 measure, and the only line [compareToSolution] ever inspects.
  IList<MoveNode> get primaryLine {
    final line = <MoveNode>[];
    var siblings = children;
    while (siblings.isNotEmpty) {
      final node = siblings.first;
      line.add(node);
      siblings = node.children;
    }
    return line.lock;
  }

  int get nodeCount =>
      children.fold(0, (sum, child) => sum + child.nodeCount);

  /// Longest line in plies.
  int get depth => children.fold(
        0,
        (deepest, child) {
          final childDepth = child.depth;
          return childDepth > deepest ? childDepth : deepest;
        },
      );

  /// The node at [path], or null for the root, which holds no move.
  ///
  /// Throws [InvalidPathError] when [path] addresses a node that is not there.
  MoveNode? nodeAt(MovePath path) {
    MoveNode? node;
    var siblings = children;
    for (final index in path.indices) {
      if (index < 0 || index >= siblings.length) {
        throw InvalidPathError(path.toString(), 'no child at index $index');
      }
      node = siblings[index];
      siblings = node.children;
    }
    return node;
  }

  /// The children of the node at [path] — the first moves when [path] is root.
  IList<MoveNode> childrenAt(MovePath path) =>
      path.isRoot ? children : nodeAt(path)!.children;

  /// The position reached at [path], replayed from [initialPosition] (D2).
  Position positionAt(MovePath path) {
    var position = initialPosition;
    var siblings = children;
    for (final index in path.indices) {
      if (index < 0 || index >= siblings.length) {
        throw InvalidPathError(path.toString(), 'no child at index $index');
      }
      final node = siblings[index];
      position = position.playUnchecked(node.move);
      siblings = node.children;
    }
    return position;
  }

  /// Every legal move at [path], promotions expanded.
  IList<Move> legalMovesAt(MovePath path) {
    final position = positionAt(path);
    final moves = <Move>[];
    for (final entry in position.legalMoves.entries) {
      final from = entry.key;
      final isPawn = position.board.pawns.has(from);
      for (final to in entry.value.squares) {
        if (isPawn && SquareSet.backranks.has(to)) {
          for (final role in const [
            Role.queen,
            Role.rook,
            Role.bishop,
            Role.knight,
          ]) {
            moves.add(NormalMove(from: from, to: to, promotion: role));
          }
        } else {
          moves.add(NormalMove(from: from, to: to));
        }
      }
    }
    return moves.lock;
  }

  /// True when no move can be added at [path] because the game has ended there.
  ///
  /// A caller may use this to stop offering moves; it must not say why, since
  /// "mate" is a word the training phase may not put on screen.
  bool isTerminalAt(MovePath path) => positionAt(path).isGameOver;

  /// Records [move] at [at].
  ///
  /// When that move is already recorded there, the tree is returned unchanged
  /// and the returned path addresses the existing child (FR-008). Otherwise the
  /// move is appended as a new sibling, leaving every existing continuation
  /// intact (FR-007).
  ///
  /// Throws [IllegalMoveError] if [move] is not legal at [at]. The UI cannot
  /// provoke this: the board is only ever given legal destinations (D6).
  TreeEdit play(MovePath at, Move move) {
    final position = positionAt(at);
    if (!position.isLegal(move)) {
      throw IllegalMoveError(move.uci, position.fen);
    }
    // Castling has two legal UCI spellings; store the king-takes-rook form so
    // the same castle entered two ways is one node.
    final normalized =
        move is NormalMove ? position.normalizeMove(move) : move;
    final san = position.makeSan(normalized).$2;

    final siblings = childrenAt(at);
    final existing = siblings.indexWhere((node) => node.san == san);
    if (existing >= 0) {
      return TreeEdit(
        tree: this,
        path: at.child(existing),
        createdBranch: false,
      );
    }

    final node = MoveNode(move: normalized, san: san);
    return TreeEdit(
      tree: _withChildrenAt(at, siblings.add(node)),
      path: at.child(siblings.length),
      // A first move from a node continues a line; a second one forks it.
      createdBranch: siblings.isNotEmpty,
    );
  }

  /// Makes the node at [path] its parent's first child, and so the primary line
  /// from that point on (FR-013).
  ///
  /// Only ordering changes: the same nodes remain, with the same subtrees.
  VariationTree promote(MovePath path) {
    if (path.isRoot) {
      throw InvalidPathError(path.toString(), 'the root cannot be promoted');
    }
    final parent = path.parent!;
    final siblings = childrenAt(parent);
    final index = path.lastIndex!;
    if (index < 0 || index >= siblings.length) {
      throw InvalidPathError(path.toString(), 'no child at index $index');
    }
    if (index == 0) return this;
    final promoted = siblings[index];
    final reordered = siblings.removeAt(index).insert(0, promoted);
    return _withChildrenAt(parent, reordered);
  }

  /// Removes the node at [path] and everything below it (FR-011).
  VariationTree delete(MovePath path) {
    if (path.isRoot) {
      throw InvalidPathError(path.toString(), 'the root cannot be deleted');
    }
    final parent = path.parent!;
    final siblings = childrenAt(parent);
    final index = path.lastIndex!;
    if (index < 0 || index >= siblings.length) {
      throw InvalidPathError(path.toString(), 'no child at index $index');
    }
    return _withChildrenAt(parent, siblings.removeAt(index));
  }

  /// Replaces the children of the node at [path], rebuilding the spine above it.
  VariationTree _withChildrenAt(MovePath path, IList<MoveNode> newChildren) =>
      VariationTree(
        initialPosition: initialPosition,
        children: _rebuild(children, path.indices, 0, newChildren),
      );

  static IList<MoveNode> _rebuild(
    IList<MoveNode> siblings,
    IList<int> indices,
    int depth,
    IList<MoveNode> newChildren,
  ) {
    if (depth == indices.length) return newChildren;
    final index = indices[depth];
    final node = siblings[index];
    return siblings.put(
      index,
      node.copyWith(
        children: _rebuild(node.children, indices, depth + 1, newChildren),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VariationTree &&
          initialPosition == other.initialPosition &&
          children == other.children;

  @override
  int get hashCode => Object.hash(initialPosition, children);

  @override
  String toString() =>
      'VariationTree(${initialPosition.fen}, $nodeCount nodes)';
}

/// The outcome of [VariationTree.play]: the resulting tree and where the cursor
/// belongs.
@immutable
class TreeEdit {
  const TreeEdit({
    required this.tree,
    required this.path,
    required this.createdBranch,
  });

  /// The tree after the edit — the same instance when the move already existed.
  final VariationTree tree;

  /// Where the cursor should now sit: the new node, or the existing one.
  final MovePath path;

  /// Whether this move forked an existing line.
  ///
  /// **For tests only. This MUST NOT reach the UI.** Branching is required to
  /// happen without confirmation, announcement, or any other interruption
  /// (FR-009); a widget that reads this field is a widget that is about to
  /// announce something.
  @visibleForTesting
  final bool createdBranch;

  @override
  String toString() => 'TreeEdit($path, createdBranch: $createdBranch)';
}
