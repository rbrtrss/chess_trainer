import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/ui/history/history_screen.dart';
import 'package:chess_trainer/ui/review/review_screen.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';

/// Scrolls the review page until [key] is on screen.
Future<void> scrollTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

/// User Story 2: a finished session can be found again and read.
void main() {
  late RepositoryHarness harness;
  late IList<TrainingPosition> positions;

  setUp(() {
    harness = RepositoryHarness.create();
    positions = samplePositions(count: 2);
  });

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(harness.repository),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A completed session, graded, exactly as finishing one leaves it.
  Future<StoredSession> completedSession({DateTime? at}) async {
    final stored = await harness.repository.start(positions, now: at);
    for (final position in positions) {
      await harness.repository.commitAttempt(stored.id, sampleAttempt(position));
    }
    for (final position in positions) {
      await harness.repository.recordGrade(
        stored.id,
        Grade(positionId: position.id, value: GradeValue.hard),
      );
    }
    return stored;
  }

  group('the list (FR-013)', () {
    testWidgets('shows when each session happened and how big it was',
        (tester) async {
      await completedSession(at: DateTime.utc(2026, 8, 6, 9, 30));
      await pumpHistory(tester);

      expect(find.byKey(const Key('history-list')), findsOneWidget);
      expect(find.textContaining('August 2026'), findsOneWidget);
      expect(find.textContaining('2 positions'), findsOneWidget);
    });

    testWidgets('says so when there is nothing yet', (tester) async {
      await pumpHistory(tester);

      expect(find.byKey(const Key('history-empty')), findsOneWidget);
    });

    testWidgets('a session still in progress is not listed', (tester) async {
      await harness.repository.start(positions);
      await pumpHistory(tester);

      expect(find.byKey(const Key('history-empty')), findsOneWidget);
    });

    testWidgets('an abandoned session is listed as abandoned', (tester) async {
      final stored = await harness.repository.start(positions);
      await harness.repository.abandon(stored.id);

      await pumpHistory(tester);

      expect(find.textContaining('abandoned'), findsOneWidget);
    });

    testWidgets('nothing in a row says how the session went', (tester) async {
      await completedSession();
      await pumpHistory(tester);

      for (final leak in const [
        'Missed it',
        'Hard',
        'Good',
        'Easy',
        'correct',
        'wrong',
        '%',
      ]) {
        expect(find.textContaining(leak), findsNothing,
            reason: '"$leak" in the history list would rank sessions by '
                'performance, and the player may meet those positions again');
      }
    });
  });

  group('reopening a completed session (FR-014)', () {
    testWidgets('shows the review, with the solution, notes and grade',
        (tester) async {
      final stored = await completedSession();
      await pumpHistory(tester);

      await tester.tap(find.byKey(Key('history-session-${stored.id}')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.byKey(const Key('review-progress')), findsOneWidget);

      // The review is a long scrolling page; the panels below the board are
      // built lazily, as they are in the app.
      await scrollTo(tester, const Key('metadata-panel'));
      expect(find.byKey(const Key('metadata-panel')), findsOneWidget);
      // The title withheld during training is readable here.
      expect(find.textContaining("Philidor's Legacy"), findsOneWidget);
      // And the grade that was recorded is the one shown as selected.
      expect(find.text('Hard'), findsOneWidget);
    });

    testWidgets('stepping between its positions works', (tester) async {
      final stored = await completedSession();
      await pumpHistory(tester);
      await tester.tap(find.byKey(Key('history-session-${stored.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Review 1 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-next')));
      await tester.pumpAndSettle();
      expect(find.text('Review 2 of 2'), findsOneWidget);
    });

    testWidgets('re-grading replaces the stored grade (FR-017)',
        (tester) async {
      final stored = await completedSession();
      await pumpHistory(tester);
      await tester.tap(find.byKey(Key('history-session-${stored.id}')));
      await tester.pumpAndSettle();

      await scrollTo(tester, const Key('metadata-panel'));
      await tester.tap(find.text('Easy'));
      await tester.pumpAndSettle();

      final reopened = await harness.repository.loadSession(stored.id);
      expect(reopened!.grades[positions[0].id]!.value, GradeValue.easy);
      // One grade per position per session, still.
      expect(await harness.rawGrades(), hasLength(2));
    });
  });

  group('reopening an abandoned session (FR-016)', () {
    testWidgets('shows it as abandoned and reveals nothing', (tester) async {
      final stored = await harness.repository.start(positions);
      await harness.repository
          .commitAttempt(stored.id, sampleAttempt(positions[0]));
      await harness.repository.abandon(stored.id);

      await pumpHistory(tester);
      await tester.tap(find.byKey(Key('history-session-${stored.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('abandoned-notice')), findsOneWidget);
      expect(find.byType(ReviewScreen), findsNothing);

      for (final withheld in const [
        "Philidor's Legacy",
        'White to play and force mate',
        'smothered mate',
        '1500',
        'Classic study',
      ]) {
        expect(find.textContaining(withheld, findRichText: true), findsNothing,
            reason: 'abandoning forfeits the answers permanently (FR-016)');
      }
    });
  });

  group('deleting everything (FR-018)', () {
    testWidgets('warns that it cannot be undone', (tester) async {
      await completedSession();
      await pumpHistory(tester);

      await tester.tap(find.byKey(const Key('delete-everything')));
      await tester.pumpAndSettle();

      final dialog = tester.widget<AlertDialog>(
        find.byKey(const Key('delete-everything-warning')),
      );
      expect((dialog.content! as Text).data, contains('cannot be undone'));
    });

    testWidgets('declining leaves everything where it was', (tester) async {
      await completedSession();
      await pumpHistory(tester);

      await tester.tap(find.byKey(const Key('delete-everything')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-everything-cancel')));
      await tester.pumpAndSettle();

      expect(await harness.repository.listSessions(), hasLength(1));
      expect(find.byKey(const Key('history-list')), findsOneWidget);
    });

    testWidgets('confirming removes everything stored', (tester) async {
      await completedSession();
      await pumpHistory(tester);

      await tester.tap(find.byKey(const Key('delete-everything')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-everything-confirm')));
      await tester.pumpAndSettle();

      expect(await harness.repository.listSessions(), isEmpty);
      expect(await harness.rawAttempts(), isEmpty);
      expect(await harness.rawGrades(), isEmpty);
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
    });
  });
}
