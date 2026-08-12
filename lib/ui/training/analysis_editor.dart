import 'package:chess_trainer/ui/training/analysis_editor_state.dart';
import 'package:chess_trainer/ui/training/variation_tree_view.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The board, the navigation controls, and the tree of what has been entered.
///
/// Everything here is uniform with respect to the solution, because nothing
/// here has access to a solution. There is one styling for a move, one sound,
/// one animation, and one shape of feedback for every input: none.
class AnalysisEditor extends ConsumerStatefulWidget {
  const AnalysisEditor({super.key, required this.orientation});

  /// The board is drawn from the point of view of the side to move (FR-002).
  final Side orientation;

  @override
  ConsumerState<AnalysisEditor> createState() => _AnalysisEditorState();
}

class _AnalysisEditorState extends ConsumerState<AnalysisEditor> {
  ChessboardController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  GameData _gameDataFor(AnalysisEditorState editor) => GameData(
        fen: editor.position.fen,
        // Both colours are played by the same person: that is the exercise.
        playerSide: editor.isTerminal ? PlayerSide.none : PlayerSide.both,
        sideToMove: editor.position.turn,
        validMoves: editor.validMoves,
        lastMove: editor.lastMove,
        // Deliberately null. A check highlight is a board highlight that varies
        // with what is on the board, and the guard test for Principle I asserts
        // that two different moves produce identical widget trees apart from
        // the pieces. Leaving it out costs the user nothing they cannot see and
        // removes a channel that would otherwise have to be argued about.
        kingSquareInCheck: null,
      );

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(analysisEditorProvider);
    final game = _gameDataFor(editor);

    final controller = _controller ??= ChessboardController(game: game);
    controller.updatePosition(game);

    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Chessboard(
              size: boardSize,
              controller: controller,
              orientation: widget.orientation,
              settings: const ChessboardSettings(
                enableCoordinates: true,
                // One duration for every move, matching or not.
                animationDuration: Duration(milliseconds: 150),
                showLastMove: true,
                showValidMoves: true,
                // The promotion chooser must offer all four pieces plainly and
                // hint at none of them (spec edge case), so auto-queening is
                // off: the user decides.
                autoQueenPromotion: false,
              ),
              onMove: (move, {bool? viaDragAndDrop}) {
                ref.read(analysisEditorProvider.notifier).play(move);
              },
              // The two parameters through which solution knowledge could reach
              // the board. They stay empty for the whole training phase.
              shapes: const {},
              annotations: const {},
            ),
            const SizedBox(height: 8),
            const _NavigationControls(),
            const SizedBox(height: 8),
            const Expanded(child: VariationTreeView()),
          ],
        );
      },
    );
  }
}

/// Step back, step forward, and return to the start (FR-006).
///
/// The controls are always present and always styled the same. They are
/// disabled only at the ends of the tree, which is a fact about where the
/// cursor is and not about whether anything is right.
class _NavigationControls extends ConsumerWidget {
  const _NavigationControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(analysisEditorProvider);
    final notifier = ref.read(analysisEditorProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('editor-reset'),
          onPressed: editor.isAtStart ? null : notifier.reset,
          icon: const Icon(Icons.replay),
          tooltip: 'Back to the start',
        ),
        IconButton(
          key: const Key('editor-back'),
          onPressed: editor.isAtStart ? null : notifier.stepBackward,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Back one move',
        ),
        IconButton(
          key: const Key('editor-forward'),
          onPressed: editor.canGoForward ? notifier.stepForward : null,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Forward one move',
        ),
      ],
    );
  }
}
