import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:chess_trainer/ui/training/training_screen.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';

/// FR-024: the player is told when their work could not be stored.
///
/// The asymmetry this covers is deliberate. A failed *read* is swallowed and
/// the data reported as absent, so a corrupt row cannot stop the app from
/// starting (FR-023). A failed *write* is never swallowed, because the one
/// thing that must not happen is the player believing a committed analysis was
/// stored when it was not.
///
/// Quickstart scenario 10 does this on a device by filling the disk; here the
/// repository is made to fail on demand, which is the same failure arriving at
/// the same place.
void main() {
  late RepositoryHarness harness;
  late FailingWriteRepository repository;
  late IList<TrainingPosition> positions;

  setUp(() {
    harness = RepositoryHarness.create();
    repository = FailingWriteRepository(harness.repository, failWrites: false);
    positions = samplePositions(count: 3);
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bundledPositionsProvider.overrideWith((ref) async => positions),
          sessionRepositoryProvider.overrideWithValue(repository),
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

  testWidgets('a session that cannot be stored does not start', (tester) async {
    repository.failWrites = true;
    await launch(tester);

    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('storage-failure')), findsOneWidget);
    expect(find.byType(TrainingScreen), findsNothing);
    expect(sessionOf(tester), isNull,
        reason: 'a session that was never stored must not look started');
  });

  testWidgets('a commit that cannot be stored does not advance the session',
      (tester) async {
    await launch(tester);
    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();
    expect(find.byType(TrainingScreen), findsOneWidget);

    // The device fills up between one position and the next.
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('commit-attempt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('storage-failure')), findsOneWidget);
    final progress =
        tester.widget<Text>(find.byKey(const Key('session-progress')));
    expect(progress.data, '1 of 3',
        reason: 'the session moved on from a position whose analysis was not '
            'stored, which is the state FR-005 forbids');
    expect(sessionOf(tester)!.attempts, isEmpty);
  });

  testWidgets('the message says what failed, in the player\'s terms',
      (tester) async {
    await launch(tester);
    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();

    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('commit-attempt')));
    await tester.pumpAndSettle();

    final message = tester.widget<SnackBar>(
      find.byKey(const Key('storage-failure')),
    );
    final text = (message.content as Text).data!;
    expect(text, contains('could not save'));
    expect(text, contains('has not been committed'));
  });

  testWidgets('a read that fails is silent, and the app still opens',
      (tester) async {
    // The other half of the asymmetry: unreadable stored data is absent, not
    // fatal (FR-023). Here the session row is corrupted outright.
    await harness.repository.start(positions);
    await harness.corrupt("UPDATE session_positions SET initial_fen = 'x'");

    await launch(tester);

    expect(find.byKey(const Key('storage-failure')), findsNothing);
    expect(find.byKey(const Key('resume-prompt')), findsNothing);
    expect(find.byKey(const Key('start-session')), findsOneWidget);
  });
}
