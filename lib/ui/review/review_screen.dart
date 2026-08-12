import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/ui/review/grade_buttons.dart';
import 'package:chess_trainer/ui/review/match_indicator.dart';
import 'package:chess_trainer/ui/review/review_controller.dart';
import 'package:chess_trainer/ui/review/tree_comparison_view.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The review phase.
///
/// Everything withheld during training becomes readable here, and only here:
/// the solution, the author's notes, the title, the theme, the rating
/// (FR-025). The screen is deliberately busy in a way the training screen must
/// never be.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final position = ref.watch(reviewedPositionProvider);
    final attempt = ref.watch(reviewedAttemptTreeProvider);
    final comparison = ref.watch(comparisonProvider);
    final cursor = ref.watch(reviewCursorProvider);

    if (session == null ||
        position == null ||
        attempt == null ||
        comparison == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final tree =
        cursor.side == ReviewSide.attempt ? attempt : position.solution;
    final boardPosition = tree.positionAt(cursor.path);
    final lastMove = tree.nodeAt(cursor.path)?.move;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Review ${session.currentIndex + 1} of ${session.length}',
          key: const Key('review-progress'),
        ),
        leading: IconButton(
          key: const Key('review-previous'),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous position',
          // Free movement between positions, in both directions, whether or not
          // anything has been graded (FR-028).
          onPressed: session.currentIndex == 0
              ? null
              : () => ref
                  .read(sessionControllerProvider.notifier)
                  .goToReviewPosition(session.currentIndex - 1),
        ),
        actions: [
          IconButton(
            key: const Key('review-next'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next position',
            onPressed: session.currentIndex == session.length - 1
                ? null
                : () => ref
                    .read(sessionControllerProvider.notifier)
                    .goToReviewPosition(session.currentIndex + 1),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            LayoutBuilder(
              builder: (context, constraints) => StaticChessboard(
                size: constraints.maxWidth,
                orientation: position.sideToMove,
                fen: boardPosition.fen,
                lastMove: lastMove,
                settings: const StaticChessboardSettings(
                  enableCoordinates: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _StepControls(tree: tree),
            const SizedBox(height: 12),
            MatchIndicator(comparison: comparison),
            const SizedBox(height: 12),
            TreeComparisonView(
              attempt: attempt,
              solution: position.solution,
              comparison: comparison,
              cursor: cursor,
              onSelect: (side, path) =>
                  ref.read(reviewCursorProvider.notifier).select(side, path),
            ),
            const SizedBox(height: 12),
            _MetadataPanel(metadata: position.metadata, id: position.id),
            const SizedBox(height: 16),
            GradeButtons(
              selected: session.gradeFor(position.id)?.value,
              onGrade: (value) => ref
                  .read(sessionControllerProvider.notifier)
                  .recordGrade(Grade(positionId: position.id, value: value)),
            ),
            const SizedBox(height: 16),
            if (session.phase == SessionPhase.complete)
              FilledButton(
                key: const Key('finish-review'),
                onPressed: () =>
                    ref.read(sessionControllerProvider.notifier).reset(),
                child: const Text('Finish'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Steps through whichever line the cursor is in, so the two panes can be read
/// against each other one ply at a time (SC-004).
class _StepControls extends ConsumerWidget {
  const _StepControls({required this.tree});

  final VariationTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursor = ref.watch(reviewCursorProvider);
    final notifier = ref.read(reviewCursorProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('review-reset'),
          icon: const Icon(Icons.replay),
          tooltip: 'Back to the start',
          onPressed: cursor.path.isRoot ? null : notifier.reset,
        ),
        IconButton(
          key: const Key('review-step-back'),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Back one move',
          onPressed: cursor.path.isRoot ? null : notifier.stepBackward,
        ),
        IconButton(
          key: const Key('review-step-forward'),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Forward one move',
          onPressed: tree.childrenAt(cursor.path).isEmpty
              ? null
              : () => notifier.stepForward(tree),
        ),
      ],
    );
  }
}

/// Everything FR-003 withheld during training, revealed (FR-025).
class _MetadataPanel extends StatelessWidget {
  const _MetadataPanel({required this.metadata, required this.id});

  final PositionMetadata metadata;
  final String id;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (metadata.title != null) ('Title', metadata.title!),
      if (metadata.goal != null) ('Goal', metadata.goal!),
      if (metadata.themes.isNotEmpty) ('Themes', metadata.themes.join(', ')),
      if (metadata.rating != null) ('Rating', '${metadata.rating}'),
      if (metadata.source != null) ('Source', metadata.source!),
    ];

    return Container(
      key: const Key('metadata-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            Text('No details were recorded for $id.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$label: ',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(value)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
