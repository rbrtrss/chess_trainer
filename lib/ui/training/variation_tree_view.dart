import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/ui/training/analysis_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The analysis as entered, with every branch visible and every node tappable
/// (FR-010).
///
/// Branches are indented rather than announced. Nothing here distinguishes a
/// move that matches the solution from one that does not, because nothing here
/// can: the widget is given a tree and a cursor and knows of no solution.
class VariationTreeView extends ConsumerWidget {
  const VariationTreeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(analysisEditorProvider);
    final notifier = ref.read(analysisEditorProvider.notifier);

    if (editor.tree.isEmpty) {
      return const Center(
        child: Text(
          'Play a move for either side to begin.',
          key: Key('tree-empty-hint'),
          style: TextStyle(fontSize: 13),
        ),
      );
    }

    final rows = <Widget>[];
    _collect(
      tree: editor.tree,
      path: MovePath.root,
      indent: 0,
      cursor: editor.cursor,
      onTap: notifier.goTo,
      into: rows,
      context: context,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BranchActions(
          enabled: editor.cursorIsOnBranch,
          onPromote: notifier.promoteCurrent,
          onDelete: notifier.deleteCurrent,
        ),
        Expanded(
          child: ListView(
            key: const Key('variation-tree'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: rows,
          ),
        ),
      ],
    );
  }

  /// Walks the tree depth-first, emitting one row per node.
  ///
  /// Every sibling after the first is indented one step, so a branch reads as a
  /// branch without anything having to say so.
  static void _collect({
    required VariationTree tree,
    required MovePath path,
    required int indent,
    required MovePath cursor,
    required void Function(MovePath) onTap,
    required List<Widget> into,
    required BuildContext context,
  }) {
    final children = tree.childrenAt(path);
    for (var i = 0; i < children.length; i++) {
      final childPath = path.child(i);
      final node = children[i];
      final childIndent = i == 0 ? indent : indent + 1;

      into.add(
        _MoveRow(
          key: Key('tree-node-${childPath.indices.join('.')}'),
          san: node.san,
          ply: childPath.length,
          indent: childIndent,
          selected: childPath == cursor,
          onTap: () => onTap(childPath),
        ),
      );

      _collect(
        tree: tree,
        path: childPath,
        indent: childIndent,
        cursor: cursor,
        onTap: onTap,
        into: into,
        context: context,
      );
    }
  }
}

/// One move in the tree. Identical for every move there is.
class _MoveRow extends StatelessWidget {
  const _MoveRow({
    super.key,
    required this.san,
    required this.ply,
    required this.indent,
    required this.selected,
    required this.onTap,
  });

  final String san;
  final int ply;
  final int indent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final moveNumber = (ply + 1) ~/ 2;
    final isWhiteMove = ply.isOdd;
    final label = isWhiteMove ? '$moveNumber. $san' : '$moveNumber... $san';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8.0 + indent * 16, 4, 8, 4),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            // Selection marks where the cursor is. It is the only thing a row's
            // appearance ever depends on.
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Promote and delete, for the branch the cursor is on (FR-011, FR-013).
class _BranchActions extends StatelessWidget {
  const _BranchActions({
    required this.enabled,
    required this.onPromote,
    required this.onDelete,
  });

  final bool enabled;
  final VoidCallback onPromote;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          key: const Key('promote-branch'),
          onPressed: enabled ? onPromote : null,
          icon: const Icon(Icons.vertical_align_top, size: 18),
          label: const Text('Make main'),
        ),
        TextButton.icon(
          key: const Key('delete-branch'),
          onPressed: enabled ? onDelete : null,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete'),
        ),
      ],
    );
  }
}
