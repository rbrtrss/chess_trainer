import 'dart:math';

import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/ui/history/history_screen.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/engine/fake_evaluator.dart';
import '../data/repository_harness.dart';

/// **The structural half of FR-019**, and the reason Principle I survives this
/// feature.
///
/// Feature 005 gave the app an engine — the first thing it has ever owned that
/// can say which move was *better*. FR-017 forbids a training screen varying by
/// evaluation **including latency**, and no widget test can see latency,
/// battery or heat. So the guarantee is not "the engine is careful during a
/// session", it is "there is no engine during a session at all", and that is
/// what this asserts: the whole session flow runs against an evaluator whose
/// every method fails the test on contact.
///
/// Modelled on `no_network_during_training_test.dart`, which plays the same
/// part for the network. If this is ever weakened to make something else pass,
/// what replaces it is nothing.
void main() {
  late AppDatabase db;

  /// One authored position and one judged by an engine, so a session mixes both
  /// and the assertion is about the kind that *has* an evaluation to leak.
  IList<TrainingPosition> positions() {
    final authored = parseTrainingPosition('''
[Title "Author knew"]
[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]

1. Nh6+ Kh8 2. Qg8+
''', id: 'authored');

    final start =
        Chess.fromSetup(Setup.parseFen('3k4/8/3K4/3P4/8/8/8/8 w - - 0 1'));
    var tree = VariationTree.empty(start);
    final edit = tree.play(MovePath.root, const NormalMove(from: Square.d6, to: Square.c6));
    tree = edit.tree;

    return IList([
      authored,
      TrainingPosition(
        id: 'engine-judged',
        initialPosition: start,
        solution: tree,
        solutionSource: SolutionSource.engine,
        evaluation: const PositionEvaluation(
          score: Centipawns(210),
          depth: 12,
          perspective: Side.white,
        ),
      ),
    ]);
  }

  late List<String> contacts;
  late DriftCollectionRepository collections;

  setUp(() {
    contacts = [];
    db = AppDatabase.memory();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260815),
      loadSamples: () async => positions(),
    );
    addTearDown(db.close);
  });

  /// The assertion that stops every test here from passing vacuously.
  ///
  /// "No engine was touched" is trivially true of a session with nothing to
  /// evaluate. This feature's own history is the argument for checking: a
  /// broken fake once hid behind a correctly-working error path, and every test
  /// still passed.
  Future<void> expectSomethingToLeak() async {
    final stored = await collections.listCollections();
    final all = await collections.positionsIn(stored.single.id);

    expect(all.any((p) => p.solutionSource == SolutionSource.engine), isTrue,
        reason: 'this session must contain a position that *has* an engine '
            'evaluation, or "the engine was not touched" means nothing');
    expect(all.any((p) => p.evaluation != null), isTrue);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          sessionRepositoryProvider
              .overrideWithValue(inMemorySessionRepository()),
          // Any contact at all fails the test.
          evaluatorProvider.overrideWithValue(
            ExplodingEvaluator((method) {
              contacts.add(method);
              fail('Evaluator.$method was called while a session existed. '
                  'The engine runs at import and nowhere else — a search '
                  'beside a player who is calculating leaks through latency, '
                  'battery and heat, none of which a widget test can see '
                  '(005 FR-019, Constitution III)');
            }),
          ),
        ],
        child: const MaterialApp(home: SessionFlow()),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoContact(String phase) {
    expect(contacts, isEmpty, reason: 'the engine was touched during $phase');
  }

  testWidgets('opening the app starts no engine', (tester) async {
    await pumpApp(tester);
    expectNoContact('startup');
  });

  testWidgets('a whole session — setup, training, commits, review — starts none',
      (tester) async {
    await pumpApp(tester);

    await expectSomethingToLeak();

    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();
    expectNoContact('starting a session');

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('commit-attempt')));
      await tester.pumpAndSettle();
      expectNoContact('committing position ${i + 1}');
    }

    expectNoContact('review');
  });

  testWidgets('resuming an interrupted session starts none', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit-attempt')));
    await tester.pumpAndSettle();

    await pumpApp(tester);
    expectNoContact('relaunch with a session to resume');
  });

  testWidgets('browsing history starts none', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('open-history')));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryScreen), findsOneWidget);
    expectNoContact('history');
  });

  testWidgets('the control: the evaluator would fire if anything called it',
      (tester) async {
    // Without this, every assertion above could be passing because the
    // exploding evaluator is wired to nothing at all. This is the same control
    // `no_network_during_training_test.dart` carries, and for the same reason:
    // a guard nobody has seen fail is a guard nobody knows works.
    var fired = false;
    final evaluator = ExplodingEvaluator((method) {
      fired = true;
      throw StateError(method);
    });

    expect(() => evaluator.engineId, throwsStateError);
    expect(fired, isTrue);
  });
}
