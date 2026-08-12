import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:meta/meta.dart';

/// One user's committed analysis of one position.
///
/// Immutable by construction, which is the whole of FR-015: a committed
/// analysis cannot be edited because there is nothing here to edit. The tree it
/// holds is a value, so continuing to work on the editor's tree after
/// committing cannot reach backwards into this.
@immutable
class Attempt {
  const Attempt({
    required this.positionId,
    required this.tree,
    required this.duration,
    required this.committedAt,
  });

  final String positionId;

  /// The analysis, frozen at commit.
  final VariationTree tree;

  /// Time spent on this position.
  final Duration duration;

  final DateTime committedAt;

  bool get isEmpty => tree.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attempt &&
          positionId == other.positionId &&
          tree == other.tree &&
          duration == other.duration &&
          committedAt == other.committedAt;

  @override
  int get hashCode => Object.hash(positionId, tree, duration, committedAt);

  @override
  String toString() =>
      'Attempt($positionId, ${tree.nodeCount} nodes, ${duration.inSeconds}s)';
}
