import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/ui/training/analysis_editor_state.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

/// The path that follows the primary line down [plies] levels.
MovePath pathAt(int plies) {
  var path = MovePath.root;
  for (var i = 0; i < plies; i++) {
    path = path.child(0);
  }
  return path;
}

/// The branching behaviour the constitution requires widget tests for:
/// rewinding and playing an alternative move must create a sibling branch while
/// leaving the original line intact — and must do it silently.
void main() {
  final position = parseTrainingPosition(
    '[FEN "${Chess.initial.fen}"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5',
    id: 'branching',
  );
  final onePosition = IList([position]);

  /// The editor's state, read out of the widget tree under test.
  AnalysisEditorState editorState(WidgetTester tester) {
    final element = tester.element(find.byType(MaterialApp));
    return ProviderScope.containerOf(element).read(analysisEditorProvider);
  }

  testWidgets('a move played on the board is recorded in the tree',
      (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    await playSanOnBoard(tester, 'e4');

    expect(editorState(tester).tree.nodeCount, 1);
    expect(editorState(tester).tree.primaryLine.first.san, 'e4');
    expect(find.text('1. e4'), findsOneWidget);
  });

  testWidgets('the user plays for both colours in turn', (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    await playSanOnBoard(tester, 'e4');
    expect(currentBoardPosition(tester).turn, Side.black);

    await playSanOnBoard(tester, 'e5');
    expect(currentBoardPosition(tester).turn, Side.white);
    expect(editorState(tester).tree.nodeCount, 2);
  });

  testWidgets('the turn indicator follows the board, not the starting position',
      (tester) async {
    // SC-005: the user has to work out that entering the opponent's reply is
    // expected. A label stuck on "White to move" while the board waits for
    // Black would teach exactly the wrong thing.
    await pumpTrainingScreen(tester, positions: onePosition);

    expect(
        tester.widget<Text>(find.byKey(const Key('turn-indicator'))).data,
        'White to move');

    await playSanOnBoard(tester, 'e4');
    expect(
        tester.widget<Text>(find.byKey(const Key('turn-indicator'))).data,
        'Black to move');

    // And it follows navigation backwards too.
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Text>(find.byKey(const Key('turn-indicator'))).data,
        'White to move');
  });

  testWidgets('stepping back and playing a different move creates a branch',
      (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    for (final san in ['e4', 'e5', 'Nf3', 'Nc6']) {
      await playSanOnBoard(tester, san);
    }

    // Step back two plies, as the quickstart describes.
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();

    await playSanOnBoard(tester, 'Bc4');

    final tree = editorState(tester).tree;
    expect(tree.nodeCount, 5, reason: 'the new move is added, nothing replaced');
    // The original continuation survives and is still the primary line.
    expect(tree.primaryLine.map((node) => node.san).toList(),
        ['e4', 'e5', 'Nf3', 'Nc6']);
    expect(find.text('2. Bc4'), findsOneWidget);
    expect(find.text('2. Nf3'), findsOneWidget);
  });

  testWidgets('branching is silent — nothing announces it', (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    for (final san in ['e4', 'e5']) {
      await playSanOnBoard(tester, san);
    }
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();

    await playSanOnBoard(tester, 'c5');

    // No dialog, no snack bar, no banner, no tooltip popped up to tell the user
    // something happened (FR-009).
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(editorState(tester).tree.childrenAt(pathAt(1)).length, 2);
  });

  testWidgets('replaying a recorded move navigates instead of duplicating',
      (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    for (final san in ['e4', 'e5', 'Nf3']) {
      await playSanOnBoard(tester, san);
    }

    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();

    // Play e5 again — the move already recorded here.
    await playSanOnBoard(tester, 'e5');

    final state = editorState(tester);
    expect(state.tree.nodeCount, 3, reason: 'no duplicate sibling');
    expect(state.cursor.length, 2, reason: 'the cursor moved into the line');
    expect(state.tree.childrenAt(pathAt(1)).length, 1);
  });

  testWidgets('the reset control returns to the starting position',
      (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    for (final san in ['e4', 'e5']) {
      await playSanOnBoard(tester, san);
    }
    await tester.tap(find.byKey(const Key('editor-reset')));
    await tester.pumpAndSettle();

    expect(editorState(tester).cursor.isRoot, isTrue);
    expect(currentBoardPosition(tester), Chess.initial);
    // The analysis itself is untouched by navigating.
    expect(editorState(tester).tree.nodeCount, 2);
  });

  testWidgets('a branch can be promoted to the primary line', (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    await playSanOnBoard(tester, 'e4');
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    await playSanOnBoard(tester, 'd4');

    await tester.tap(find.byKey(const Key('promote-branch')));
    await tester.pumpAndSettle();

    final tree = editorState(tester).tree;
    expect(tree.primaryLine.first.san, 'd4');
    expect(tree.nodeCount, 2, reason: 'promotion moves nodes, never drops them');
  });

  testWidgets('a branch can be deleted', (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);

    await playSanOnBoard(tester, 'e4');
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    await playSanOnBoard(tester, 'd4');

    await tester.tap(find.byKey(const Key('delete-branch')));
    await tester.pumpAndSettle();

    final tree = editorState(tester).tree;
    expect(tree.nodeCount, 1);
    expect(tree.primaryLine.first.san, 'e4');
  });

  testWidgets('promote and delete are unavailable where there is no branch',
      (tester) async {
    await pumpTrainingScreen(tester, positions: onePosition);
    await playSanOnBoard(tester, 'e4');

    final promote =
        tester.widget<TextButton>(find.byKey(const Key('promote-branch')));
    final delete =
        tester.widget<TextButton>(find.byKey(const Key('delete-branch')));

    expect(promote.onPressed, isNull);
    expect(delete.onPressed, isNull);
  });

  testWidgets('a line that reaches checkmate accepts no further moves',
      (tester) async {
    final mateInOne = parseTrainingPosition(
      '[FEN "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"]\n\n1. Ra8#',
      id: 'terminal',
    );
    await pumpTrainingScreen(tester, positions: IList([mateInOne]));

    await playSanOnBoard(tester, 'Ra8#');

    final state = editorState(tester);
    expect(state.isTerminal, isTrue);
    expect(state.tree.legalMovesAt(state.cursor), isEmpty);
    // And the app says nothing about it.
    expect(find.textContaining('mate', findRichText: true), findsNothing);
    expect(find.textContaining('Mate', findRichText: true), findsNothing);
    expect(find.textContaining('check', findRichText: true), findsNothing);
  });
}
