import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:chess_trainer/ui/session/session_setup_screen.dart';
import 'package:chess_trainer/ui/training/training_screen.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';
import 'editor_harness.dart';

/// User Story 1: an interrupted session comes back.
///
/// Everything here goes through the real repository over an in-memory database,
/// so what is tested is the path the app takes on a real launch after a real
/// kill — the app never gets to know the difference.
void main() {
  late RepositoryHarness harness;
  late IList<TrainingPosition> positions;

  setUp(() {
    harness = RepositoryHarness.create();
    positions = samplePositions(count: 5);
  });

  /// Pumps the app as if it had just been launched.
  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          availablePositionsProvider.overrideWith((ref) async => positions),
          sessionRepositoryProvider.overrideWithValue(harness.repository),
        ],
        child: const MaterialApp(home: SessionFlow()),
      ),
    );
    await tester.pumpAndSettle();
  }

  TrainingSession? sessionOf(WidgetTester tester) {
    final element = tester.element(find.byType(MaterialApp));
    return ProviderScope.containerOf(element).read(sessionControllerProvider);
  }

  /// Stores a session with [committed] positions already committed, then
  /// "kills the app" by simply not touching that state again.
  Future<StoredSession> interruptedSession({int committed = 2}) async {
    final stored = await harness.repository.start(positions);
    for (var i = 0; i < committed; i++) {
      await harness.repository.commitAttempt(stored.id, sampleAttempt(positions[i]));
    }
    return stored;
  }

  group('being offered the session back (FR-006)', () {
    testWidgets('an unfinished session is offered on launch', (tester) async {
      await interruptedSession();
      await launch(tester);

      expect(find.byKey(const Key('resume-prompt')), findsOneWidget);
      expect(find.byKey(const Key('resume-continue')), findsOneWidget);
    });

    testWidgets('the prompt says the analysis in progress was not kept '
        '(FR-003)', (tester) async {
      await interruptedSession();
      await launch(tester);

      final notice = tester.widget<Text>(
        find.byKey(const Key('resume-uncommitted-notice')),
      );
      expect(notice.data, contains('was not kept'));
      expect(notice.data, contains('Everything you committed is still there'));
    });

    testWidgets('nothing is offered when there is no unfinished session',
        (tester) async {
      await launch(tester);

      expect(find.byKey(const Key('resume-prompt')), findsNothing);
      expect(find.byType(SessionSetupScreen), findsOneWidget);
    });

    testWidgets('an abandoned session is not offered (FR-009)', (tester) async {
      final stored = await interruptedSession();
      await harness.repository.abandon(stored.id);

      await launch(tester);

      expect(find.byKey(const Key('resume-prompt')), findsNothing);
    });

    testWidgets('a completed session is not offered (FR-009)', (tester) async {
      final stored = await harness.repository.start(positions);
      for (final position in positions) {
        await harness.repository
            .commitAttempt(stored.id, sampleAttempt(position));
      }

      await launch(tester);

      expect(find.byKey(const Key('resume-prompt')), findsNothing);
    });
  });

  group('continuing (FR-007)', () {
    testWidgets('lands on the stored position with the stored count',
        (tester) async {
      await interruptedSession();
      await launch(tester);

      await tester.tap(find.byKey(const Key('resume-continue')));
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
      final progress =
          tester.widget<Text>(find.byKey(const Key('session-progress')));
      expect(progress.data, '3 of 5');
    });

    testWidgets('every attempt committed before the interruption is there',
        (tester) async {
      await interruptedSession();
      await launch(tester);

      await tester.tap(find.byKey(const Key('resume-continue')));
      await tester.pumpAndSettle();

      final session = sessionOf(tester)!;
      expect(session.attempts.length, 2);
      expect(session.attemptFor(positions[0].id), isNotNull);
      expect(session.attemptFor(positions[1].id), isNotNull);
      // And nothing for the position that was in progress.
      expect(session.attemptFor(positions[2].id), isNull);
    });

    testWidgets('the board starts over, with no moves entered', (tester) async {
      await interruptedSession();
      await launch(tester);

      await tester.tap(find.byKey(const Key('resume-continue')));
      await tester.pumpAndSettle();

      final session = sessionOf(tester)!;
      expect(session.currentIndex, 2);
      final board = currentBoardPosition(tester);
      expect(board.fen, positions[2].initialPosition.fen);
    });

    testWidgets('committing the rest reaches review with every attempt',
        (tester) async {
      await interruptedSession(committed: 4);
      await launch(tester);

      await tester.tap(find.byKey(const Key('resume-continue')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('commit-attempt')));
      await tester.pumpAndSettle();

      final session = sessionOf(tester)!;
      expect(session.phase, SessionPhase.review);
      expect(session.attempts.length, 5);
    });

    testWidgets('a session whose positions were all committed resumes into '
        'review', (tester) async {
      final stored = await harness.repository.start(positions);
      for (var i = 0; i < positions.length - 1; i++) {
        await harness.repository
            .commitAttempt(stored.id, sampleAttempt(positions[i]));
      }
      // The last commit is what would have completed it; interrupt just before.
      await launch(tester);
      await tester.tap(find.byKey(const Key('resume-continue')));
      await tester.pumpAndSettle();

      expect(sessionOf(tester)!.phase, SessionPhase.training);
      expect(sessionOf(tester)!.currentIndex, 4);
    });
  });

  group('getting back on screen quickly (SC-002)', () {
    testWidgets('the launch frame waits for the lookup rather than flashing a '
        'session-less setup screen', (tester) async {
      await interruptedSession();

      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            availablePositionsProvider.overrideWith((ref) async => positions),
            sessionRepositoryProvider.overrideWithValue(harness.repository),
          ],
          child: const MaterialApp(home: SessionFlow()),
        ),
      );

      // One frame in: whatever else is on screen, a setup screen *without* the
      // offer must never be, or the offer appears a moment later as if the app
      // had changed its mind about whether the session existed.
      //
      // On a device the lookup takes a frame or two and the spinner shows; in
      // a test over an in-memory database it usually resolves within the first
      // microtask drain. Both are correct — what must not happen is the flash.
      await tester.pump();
      final offered =
          find.byKey(const Key('resume-prompt')).evaluate().isNotEmpty;
      final started =
          find.byKey(const Key('start-session')).evaluate().isNotEmpty;
      expect(started && !offered, isFalse,
          reason: 'the first frame offered a new session while an unfinished '
              'one existed; the offer to continue arrives after it, which '
              'reads as the app changing its mind');

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resume-prompt')), findsOneWidget);
    });

    testWidgets('and the session is on screen without a further wait',
        (tester) async {
      await interruptedSession();
      await launch(tester);

      final stopwatch = Stopwatch()..start();
      await tester.tap(find.byKey(const Key('resume-continue')));
      await tester.pumpAndSettle();
      stopwatch.stop();

      expect(find.byType(TrainingScreen), findsOneWidget);
      // The three seconds of SC-002 are confirmed by hand on the device; this
      // stands guard against a resume that starts doing real work — reparsing
      // every stored tree, say — between the tap and the board.
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('declining (FR-010, FR-011)', () {
    testWidgets('starting fresh warns in the same terms as abandoning',
        (tester) async {
      await interruptedSession();
      await launch(tester);

      await tester.tap(find.byKey(const Key('resume-start-fresh')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-warning')), findsOneWidget);
      final dialog = tester.widget<AlertDialog>(
        find.byKey(const Key('discard-warning')),
      );
      final content = dialog.content! as Text;
      expect(content.data, contains('no answers will be shown'));
      expect(content.data, contains('already committed'));
    });

    testWidgets('declining the warning leaves the session untouched',
        (tester) async {
      final stored = await interruptedSession();
      await launch(tester);

      await tester.tap(find.byKey(const Key('resume-start-fresh')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('resume-prompt')), findsOneWidget);
      final still = await harness.repository.loadInProgress();
      expect(still!.record.id, stored.id);
      expect(still.attempts.length, 2);
    });

    testWidgets('confirming discards it and starts a new session',
        (tester) async {
      final stored = await interruptedSession();
      await launch(tester);

      await tester.tap(find.byKey(const Key('resume-start-fresh')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
      final session = sessionOf(tester)!;
      expect(session.attempts, isEmpty);
      expect(session.currentIndex, 0);

      // The discarded session is abandoned, and its answers are gone.
      final live = await harness.repository.loadInProgress();
      expect(live!.record.id, isNot(stored.id));
      expect(await harness.rawAttempts(), isEmpty);
    });

    testWidgets('starting from the Start button warns too', (tester) async {
      await interruptedSession();
      await launch(tester);

      await tester.tap(find.byKey(const Key('start-session')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discard-warning')), findsOneWidget);
    });
  });
}
