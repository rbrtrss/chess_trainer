import 'package:chess_trainer/domain/attempt/comparison.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/ui/review/review_controller.dart';
import 'package:flutter/material.dart';

/// The user's analysis beside the solution, both navigable (FR-020).
///
/// The two panes are the same widget with different trees, which is the payoff
/// of using one tree type for both: comparing them is looking at two of the
/// same thing rather than translating between two shapes.
class TreeComparisonView extends StatelessWidget {
  const TreeComparisonView({
    super.key,
    required this.attempt,
    required this.solution,
    required this.comparison,
    required this.cursor,
    required this.onSelect,
  });

  final VariationTree attempt;
  final VariationTree solution;
  final ComparisonResult comparison;
  final ReviewCursor cursor;
  final void Function(ReviewSide, MovePath) onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _TreePane(
            key: const Key('attempt-pane'),
            title: 'What you played',
            tree: attempt,
            side: ReviewSide.attempt,
            cursor: cursor,
            // The ply the two lines part company at, marked in both panes so
            // the eye lands on the same row (SC-004).
            divergencePly: comparison.divergence?.ply,
            emptyMessage: 'You committed without entering a move.',
            onSelect: onSelect,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TreePane(
            key: const Key('solution-pane'),
            title: 'The solution',
            tree: solution,
            side: ReviewSide.solution,
            cursor: cursor,
            divergencePly: comparison.divergence?.ply,
            emptyMessage: 'No solution was recorded.',
            onSelect: onSelect,
          ),
        ),
      ],
    );
  }
}

class _TreePane extends StatelessWidget {
  const _TreePane({
    super.key,
    required this.title,
    required this.tree,
    required this.side,
    required this.cursor,
    required this.divergencePly,
    required this.emptyMessage,
    required this.onSelect,
  });

  final String title;
  final VariationTree tree;
  final ReviewSide side;
  final ReviewCursor cursor;
  final int? divergencePly;
  final String emptyMessage;
  final void Function(ReviewSide, MovePath) onSelect;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    _collect(context, MovePath.root, 0, true, rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(emptyMessage,
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          ...rows,
      ],
    );
  }

  /// Emits a row per node, depth first.
  ///
  /// [onPrimaryLine] tracks whether this node is still on the tree's main line,
  /// because the divergence marker belongs only there: the comparison never
  /// looked at anything else, so marking a branch with it would be asserting
  /// something the app does not know (FR-024).
  void _collect(
    BuildContext context,
    MovePath path,
    int indent,
    bool onPrimaryLine,
    List<Widget> into,
  ) {
    final children = tree.childrenAt(path);
    for (var i = 0; i < children.length; i++) {
      final childPath = path.child(i);
      final node = children[i];
      final childPrimary = onPrimaryLine && i == 0;
      final childIndent = i == 0 ? indent : indent + 1;
      final isDivergence =
          childPrimary && divergencePly == childPath.length;

      into.add(
        _ReviewMoveRow(
          key: Key('${side.name}-node-${childPath.indices.join('.')}'),
          san: node.san,
          ply: childPath.length,
          indent: childIndent,
          selected: cursor.side == side && cursor.path == childPath,
          isDivergence: isDivergence,
          comments: node.comments.unlock,
          onTap: () => onSelect(side, childPath),
        ),
      );

      _collect(context, childPath, childIndent, childPrimary, into);
    }
  }
}

class _ReviewMoveRow extends StatelessWidget {
  const _ReviewMoveRow({
    super.key,
    required this.san,
    required this.ply,
    required this.indent,
    required this.selected,
    required this.isDivergence,
    required this.comments,
    required this.onTap,
  });

  final String san;
  final int ply;
  final int indent;
  final bool selected;
  final bool isDivergence;
  final List<String> comments;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moveNumber = (ply + 1) ~/ 2;
    final label =
        ply.isOdd ? '$moveNumber. $san' : '$moveNumber... $san';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(4.0 + indent * 12, 3, 4, 3),
        color: selected ? theme.colorScheme.surfaceContainerHighest : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isDivergence)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.call_split,
                        size: 14, color: theme.colorScheme.primary),
                  ),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
            // The author's notes, at the move they belong to (FR-022).
            for (final comment in comments)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2, right: 4),
                child: Text(
                  comment,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
