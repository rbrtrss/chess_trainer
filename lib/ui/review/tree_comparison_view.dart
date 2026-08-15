import 'package:chess_trainer/domain/attempt/comparison.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:dartchess/dartchess.dart';
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
    this.solutionSource = SolutionSource.author,
    this.evaluation,
  });

  final VariationTree attempt;
  final VariationTree solution;

  /// Where [solution] came from (005 FR-012, FR-015).
  ///
  /// Two positions can look identical here while one is measured against a
  /// human's intention and the other against a machine's preference, and the
  /// player is entitled to know which — an engine's first choice is often not
  /// what a person would call the point of the position.
  final SolutionSource solutionSource;

  /// What the engine made of the starting position, when an engine judged it.
  final PositionEvaluation? evaluation;
  final ComparisonResult comparison;
  final ReviewCursor cursor;
  final void Function(ReviewSide, MovePath) onSelect;

  /// What an empty solution pane says, which is now two different situations.
  ///
  /// Until feature 005 there was one: the source recorded no line. Now there is
  /// also a position whose author gave none *and* whose engine could not
  /// answer, and telling a player "none was recorded" for that would be false —
  /// one was wanted and could not be produced (005 FR-010, research D6).
  String get _emptySolutionMessage => switch (solutionSource) {
        SolutionSource.none =>
          'No solution could be worked out for this position.',
        SolutionSource.author || SolutionSource.engine =>
          'No solution was recorded.',
      };

  /// How the engine's assessment reads, in words rather than as a raw number.
  ///
  /// FR-013 asks for terms the player can act on. "+1.4" means something to a
  /// strong player and nothing to everyone else, so the number is given a
  /// sentence around it.
  String _assessment(PositionEvaluation evaluation) {
    final mover = evaluation.perspective == Side.white ? 'White' : 'Black';
    return switch (evaluation.score) {
      MateIn(:final plies) when plies > 0 =>
        '$mover has a forced mate in ${(plies / 2).ceil()}.',
      MateIn(:final plies) =>
        '$mover is being mated in ${(plies.abs() / 2).ceil()}.',
      Centipawns(:final value) when value.abs() < 50 => 'The position is level.',
      Centipawns(:final value) =>
        '${value > 0 ? mover : (mover == 'White' ? 'Black' : 'White')} is '
            'better by about ${(value.abs() / 100).toStringAsFixed(1)} of a '
            'pawn.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final evaluation = this.evaluation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shown only where an engine supplied the line. An authored position
        // reviews exactly as it did before this feature (FR-015).
        if (solutionSource == SolutionSource.engine && evaluation != null) ...[
          Text(
            'No solution was recorded here, so this line is an engine\'s best '
            'try at depth ${evaluation.depth}, not the author\'s intention. '
            '${_assessment(evaluation)}',
            key: const Key('engine-provenance'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        _panes(context),
      ],
    );
  }

  Widget _panes(BuildContext context) {
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
            emptyMessage: _emptySolutionMessage,
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
