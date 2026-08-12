import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/ui/review/review_screen.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:chess_trainer/ui/session/session_setup_screen.dart';
import 'package:chess_trainer/ui/training/training_screen.dart';
import 'package:chessground/chessground.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

/// A five-position session, end to end: no correctness information appears at
/// any point, committing advances with no result screen in between, and review
/// begins only after the fifth commit.
void main() {
  /// Five distinct positions with rich metadata, so a leak has somewhere to
  /// show up.
  IList<TrainingPosition> fivePositions() => IList(
        List.generate(
          5,
          (i) => parseTrainingPosition('''
[Title "Secret title $i"]
[Goal "White to play and win"]
[Themes "fork, pin"]
[Rating "${1000 + i}"]

1. e4 e5 2. Nf3
''', id: 'position-$i'),
        ),
      );

  Future<void> pumpFlow(WidgetTester tester, IList<TrainingPosition> positions) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Start from a fresh element tree so a second pump in one test does not
    // reuse the first session's providers.
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bundledPositionsProvider.overrideWith((ref) async => positions),
        ],
        child: const MaterialApp(home: SessionFlow()),
      ),
    );
    await tester.pumpAndSettle();
  }

  TrainingSession sessionOf(WidgetTester tester) {
    final element = tester.element(find.byType(MaterialApp));
    return ProviderScope.containerOf(element).read(sessionControllerProvider)!;
  }

  Future<void> startSession(WidgetTester tester, int length) async {
    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();
  }

  Future<void> commit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('commit-attempt')));
    await tester.pumpAndSettle();
  }

  testWidgets('a session runs from setup through training into review',
      (tester) async {
    await pumpFlow(tester, fivePositions());

    expect(find.byType(SessionSetupScreen), findsOneWidget);

    // The slider defaults to 3; drag it to the maximum.
    await tester.drag(
        find.byKey(const Key('session-length-slider')), const Offset(500, 0));
    await tester.pumpAndSettle();
    await startSession(tester, 5);

    expect(find.byType(TrainingScreen), findsOneWidget);
    expect(sessionOf(tester).length, 5);
  });

  testWidgets('committing advances straight to the next position (FR-016)',
      (tester) async {
    await pumpFlow(tester, fivePositions());
    await startSession(tester, 3);

    expect(find.text('1 of 3'), findsOneWidget);

    await commit(tester);

    // The next position is on screen and nothing appeared in between: no
    // result screen, no dialog, no banner, no score.
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.byType(TrainingScreen), findsOneWidget);
    expect(find.byType(ReviewScreen), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(sessionOf(tester).phase, SessionPhase.training);
  });

  testWidgets('review begins only after the final commit (FR-018)',
      (tester) async {
    await pumpFlow(tester, fivePositions());
    await startSession(tester, 3);

    await commit(tester);
    expect(find.byType(ReviewScreen), findsNothing);
    await commit(tester);
    expect(find.byType(ReviewScreen), findsNothing,
        reason: 'two of three committed — review must still be out of reach');

    await commit(tester);

    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(sessionOf(tester).phase, SessionPhase.review);
  });

  testWidgets('the analysis is fresh on each position, not carried over',
      (tester) async {
    await pumpFlow(tester, fivePositions());
    await startSession(tester, 3);

    await playSanOnBoard(tester, 'e4');
    expect(find.text('1. e4'), findsOneWidget);

    await commit(tester);

    expect(find.text('1. e4'), findsNothing);
    expect(find.byKey(const Key('tree-empty-hint')), findsOneWidget);
  });

  testWidgets('no correctness information appears anywhere across the session',
      (tester) async {
    await pumpFlow(tester, fivePositions());
    await startSession(tester, 3);

    for (var i = 0; i < 3; i++) {
      // One position gets the solution's move, one gets a poor move, one gets
      // nothing at all.
      if (i == 0) await playSanOnBoard(tester, 'e4');
      if (i == 1) await playSanOnBoard(tester, 'h4');

      for (final leak in <String>[
        'Secret title',
        'White to play and win',
        'fork',
        'pin',
        '100',
        'correct',
        'wrong',
        'right',
        'score',
      ]) {
        expect(find.textContaining(leak, findRichText: true), findsNothing,
            reason: '"$leak" appeared at position ${i + 1}');
      }

      // The board never carries an annotation or a shape.
      final board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.annotations, isEmpty);
      expect(board.shapes, isEmpty);

      await commit(tester);
    }

    // Only now.
    expect(find.byType(ReviewScreen), findsOneWidget);
  });

  testWidgets('the progress counter is identical whatever was played (SC-001)',
      (tester) async {
    // A session where every answer is the solution's move.
    await pumpFlow(tester, fivePositions());
    await startSession(tester, 3);
    await playSanOnBoard(tester, 'e4');
    await commit(tester);
    final afterGood = tester.widget<Text>(find.byKey(const Key('session-progress')));

    // The same session where every answer is a poor move.
    await pumpFlow(tester, fivePositions());
    await startSession(tester, 3);
    await playSanOnBoard(tester, 'h4');
    await commit(tester);
    final afterBad = tester.widget<Text>(find.byKey(const Key('session-progress')));

    expect(afterBad.data, afterGood.data);
    expect(afterBad.style, afterGood.style);
    expect(afterBad.key, afterGood.key);
  });

  testWidgets('committing with nothing entered is accepted (FR-014)',
      (tester) async {
    await pumpFlow(tester, fivePositions());
    await startSession(tester, 3);

    final button =
        tester.widget<FilledButton>(find.byKey(const Key('commit-attempt')));
    expect(button.onPressed, isNotNull,
        reason: 'an empty analysis is a valid answer, not an error');

    await commit(tester);

    expect(sessionOf(tester).attemptFor('position-0')!.tree.isEmpty, isTrue);
  });

  group('abandoning (FR-019)', () {
    testWidgets('warns that no answers will be shown', (tester) async {
      await pumpFlow(tester, fivePositions());
      await startSession(tester, 3);
      await commit(tester);

      await tester.tap(find.byKey(const Key('abandon-session')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('abandon-warning')), findsOneWidget);
      expect(find.textContaining('no answers will be shown'), findsOneWidget);
    });

    testWidgets('cancelling leaves the session exactly where it was',
        (tester) async {
      await pumpFlow(tester, fivePositions());
      await startSession(tester, 3);
      await commit(tester);

      await tester.tap(find.byKey(const Key('abandon-session')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('abandon-cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(sessionOf(tester).phase, SessionPhase.training);
    });

    testWidgets('confirming ends the session and reveals nothing',
        (tester) async {
      await pumpFlow(tester, fivePositions());
      await startSession(tester, 3);
      await commit(tester);

      await tester.tap(find.byKey(const Key('abandon-session')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('abandon-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.byType(TrainingScreen), findsNothing);
      expect(find.byType(SessionSetupScreen), findsOneWidget);
      expect(sessionOf(tester).phase, SessionPhase.abandoned);
      expect(find.textContaining('Secret title'), findsNothing);
    });
  });
}
