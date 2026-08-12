import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// The address of a node in a [VariationTree]: the list of child indices
/// followed from the root (research D3).
///
/// The empty path is the root — the starting position itself, before any move.
///
/// Paths are positional, so they are invalidated by `promote` and `delete`,
/// which renumber siblings. Holders of a path recompute it after any structural
/// edit; the trees here are small enough that this is cheaper than maintaining
/// stable node identity.
@immutable
class MovePath {
  const MovePath(this.indices);

  /// The starting position, before any move.
  static const MovePath root = MovePath(IList.empty());

  /// Child indices from the root, outermost first.
  final IList<int> indices;

  /// The path to the [index]th child of the node this path addresses.
  MovePath child(int index) => MovePath(indices.add(index));

  /// The path to the parent node, or null at the root.
  MovePath? get parent =>
      isRoot ? null : MovePath(indices.sublist(0, indices.length - 1));

  bool get isRoot => indices.isEmpty;

  /// Number of plies from the root — i.e. the ply this path addresses.
  int get length => indices.length;

  /// The index this node occupies among its siblings, or null at the root.
  int? get lastIndex => isRoot ? null : indices.last;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovePath && indices == other.indices;

  @override
  int get hashCode => indices.hashCode;

  /// Readable in test failure output, which is half the point of this type.
  @override
  String toString() => 'MovePath(${indices.join('.')})';
}
