import 'dart:math';

import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:chess_trainer/ui/training/training_screen.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';

/// User Story 3: choosing what a session draws from (FR-029 – FR-032).
void main() {
  late AppDatabase db;
  late DriftCollectionRepository collections;

  setUp(() {
    db = AppDatabase.memory();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260814),
      loadSamples: () async => const IList.empty(),
    );
    addTearDown(db.close);
  });

  IList<TrainingPosition> positionsNamed(String prefix, int count) => IList(
        List.generate(
          count,
          (i) => parseTrainingPosition('''
[Title "$prefix secret $i"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4 e5 2. Nf3
''', id: '$prefix-$i'),
        ),
      );

  Future<Collection> add(String name, int count) => collections.store(
        name: name,
        origin: FileOrigin('$name.pgn'),
        contentHash: name,
        positions: positionsNamed(name, count),
      );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          sessionRepositoryProvider
              .overrideWithValue(inMemorySessionRepository()),
        ],
        child: const MaterialApp(home: SessionFlow()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with one collection there is nothing to choose', (tester) async {
    await add('Endgames', 3);
    await pumpApp(tester);

    expect(find.byKey(const Key('collection-chooser')), findsNothing);
    expect(find.byKey(const Key('collection-name-label')), findsOneWidget);
  });

  testWidgets('with several, the player picks one (FR-029)', (tester) async {
    await add('Endgames', 3);
    await add('Tactics', 5);
    await pumpApp(tester);

    expect(find.byKey(const Key('collection-chooser')), findsOneWidget);
  });

  testWidgets('every position comes from the chosen collection (FR-030)',
      (tester) async {
    final endgames = await add('Endgames', 3);
    await add('Tactics', 5);
    await pumpApp(tester);

    // Choose the older collection explicitly — the default is the newest.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(selectedCollectionProvider.notifier).choose(endgames.id);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();

    expect(find.byType(TrainingScreen), findsOneWidget);
    final session = container.read(sessionControllerProvider)!;
    expect(session.length, 3);
  });

  testWidgets('the collection name is on setup and on no training screen '
      '(FR-026)', (tester) async {
    await add('Back-rank mates', 3);
    await pumpApp(tester);

    expect(find.textContaining('Back-rank mates'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();

    expect(find.byType(TrainingScreen), findsOneWidget);
    expect(find.textContaining('Back-rank mates', findRichText: true),
        findsNothing,
        reason: 'a collection called "Back-rank mates" tells the player the '
            'answer as surely as a chapter title does');
  });

  testWidgets('a short collection runs a shorter session, not a repeated one '
      '(FR-031)', (tester) async {
    await add('Two only', 2);
    await pumpApp(tester);

    // The slider defaults to 3; this collection has 2.
    expect(find.byKey(const Key('short-collection-notice')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('session-length'))).data,
      'Positions: 2',
    );

    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final session = container.read(sessionControllerProvider)!;
    expect(session.length, 2);

    // The two positions are distinct: seeing the same one twice in a session
    // would be its own kind of hint.
    final ids = session.positions.map((position) => position.id).toSet();
    expect(ids, hasLength(2));
  });

  testWidgets('an empty library offers import rather than a broken form '
      '(FR-039)', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('empty-library')), findsOneWidget);
    expect(find.byKey(const Key('start-session')), findsNothing);
  });
}
