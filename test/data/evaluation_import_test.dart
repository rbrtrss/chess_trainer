import 'dart:math';

import 'package:chess_trainer/data/engine/evaluator.dart';
import 'package:chess_trainer/data/import_parser.dart';
import 'package:chess_trainer/data/import_service.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine/fake_evaluator.dart';

/// Feature 005's import path: where an author gave no line, an engine supplies
/// one ([contracts/evaluation-api.md](../../specs/005-engine-judged-positions/contracts/evaluation-api.md)
/// invariants 1–4).
///
/// Everything here runs against [FakeEvaluator]. Nothing can run against the
/// real engine: `multistockfish` is Android and iOS only and this is the host
/// VM (005 research D8). That is the whole reason the interface exists.
void main() {
  late AppDatabase db;
  late DriftCollectionRepository collections;

  setUp(() {
    db = AppDatabase.memory();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260815),
      loadSamples: () async => const IList.empty(),
    );
    addTearDown(db.close);
  });

  DefaultImportService serviceWith(FakeEvaluator? evaluator) =>
      DefaultImportService(
        collections,
        parse: (source) async => parseImport(source, newId: timestampIds()),
        evaluator: evaluator,
      );

  /// A position and no moves — the entry this feature exists for.
  const noMoves = '''
[Event "Set up by hand"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

*
''';

  /// A position with a line the author wrote.
  const authored = '''
[Event "Author knew the answer"]
[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]

1. Nh6+ Kh8 2. Qg8+ *
''';

  Future<ImportReported> importOf(
    String pgn, {
    FakeEvaluator? evaluator,
    String name = 'Imported',
  }) async {
    final progress = await serviceWith(evaluator)
        .importText(pgn, name: name, origin: const FileOrigin('mine.pgn'))
        .last;
    return progress as ImportReported;
  }

  group('invariant 1 — a no-moves entry becomes a trainable position', () {
    test('with the engine line as its solution', () async {
      final evaluator = FakeEvaluator(plies: 4);
      final reported = await importOf(noMoves, evaluator: evaluator);

      final stored =
          (await collections.positionsIn(reported.collection.id)).single;

      expect(stored.solutionSource, SolutionSource.engine);
      expect(stored.solution.isEmpty, isFalse,
          reason: 'the engine supplied the line the author did not');
      expect(stored.solution.primaryLine, hasLength(4));
      expect(stored.evaluation, isNotNull);
      expect(stored.evaluation!.depth, searchDepth);
    });

    test('and the engine was asked exactly once, about that position',
        () async {
      final evaluator = FakeEvaluator();
      await importOf(noMoves, evaluator: evaluator);

      expect(evaluator.asked, hasLength(1));
      expect(evaluator.asked.single.fen, startsWith('3k4/8/3K4/3P4'));
    });
  });

  group('invariant 2 — authored entries are left alone (FR-011)', () {
    test('the engine is never asked about them', () async {
      final evaluator = FakeEvaluator();
      final reported = await importOf(authored, evaluator: evaluator);

      expect(evaluator.asked, isEmpty,
          reason: 'where an author said what they intended, that remains the '
              'standard and the engine is not consulted');

      final stored =
          (await collections.positionsIn(reported.collection.id)).single;
      expect(stored.solutionSource, SolutionSource.author);
      expect(stored.evaluation, isNull);
    });

    test('a source with both kinds gets one of each', () async {
      final evaluator = FakeEvaluator();
      final reported =
          await importOf('$authored\n\n$noMoves', evaluator: evaluator);

      final stored = await collections.positionsIn(reported.collection.id);
      expect(stored, hasLength(2));
      expect(
        stored.map((p) => p.solutionSource).toSet(),
        {SolutionSource.author, SolutionSource.engine},
      );
      expect(evaluator.asked, hasLength(1),
          reason: 'only the entry that needed one');
    });
  });

  group('invariant 3 — a terminal position is rejected, unasked (FR-004)', () {
    test('the engine is never started for a position with no legal move',
        () async {
      const mated = '''
[Event "Already over"]
[FEN "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"]

*
''';
      final evaluator = FakeEvaluator();
      final progress = await serviceWith(evaluator)
          .importText(mated, name: 'Over', origin: const FileOrigin('x.pgn'))
          .last;

      expect(progress, isA<ImportFailed>());
      expect((progress as ImportFailed).outcome!.rejections.single.reason,
          RejectionReason.noLegalMoves);
      expect(evaluator.asked, isEmpty,
          reason: 'dartchess answers this, and the constitution forbids asking '
              'the engine anything dartchess can answer');
    });
  });

  group('invariant 4 — an engine with nothing to say costs one entry', () {
    test('that entry is still imported, as none (FR-010)', () async {
      // Not an error. The position stays trainable and the review says plainly
      // that there is no evaluation, rather than showing a blank pane.
      final silent = FakeEvaluator(answersFor: (_) => false);
      final reported = await importOf(noMoves, evaluator: silent);

      final stored =
          (await collections.positionsIn(reported.collection.id)).single;
      expect(stored.solutionSource, SolutionSource.none);
      expect(stored.solution.isEmpty, isTrue);
      expect(stored.evaluation, isNull);
    });

    test('and the other entries are untouched', () async {
      final silent = FakeEvaluator(answersFor: (_) => false);
      final reported =
          await importOf('$authored\n\n$noMoves', evaluator: silent);

      final stored = await collections.positionsIn(reported.collection.id);
      expect(stored, hasLength(2),
          reason: 'one position failing to evaluate must not cost the import '
              'its other entries');
    });

    test('an engine that throws is caught, not propagated', () async {
      // `bestLine` must not throw, and the caller must survive it if it does.
      // An import that dies because one position upset the engine is the worst
      // possible reading of FR-010.
      final broken = FakeEvaluator()..failure = StateError('engine died');
      final reported = await importOf(noMoves, evaluator: broken);

      final stored =
          (await collections.positionsIn(reported.collection.id)).single;
      expect(stored.solutionSource, SolutionSource.none);
    });

    test('no evaluator at all is a normal state, not a failure', () async {
      // A platform with no engine, or any test that does not care about one.
      final reported = await importOf(noMoves);

      final stored =
          (await collections.positionsIn(reported.collection.id)).single;
      expect(stored.solutionSource, SolutionSource.none);
    });
  });

  group('the import reports progress while the engine works', () {
    test('an evaluating state is emitted, and counts up', () async {
      final progress = await serviceWith(FakeEvaluator())
          .importText('$noMoves\n\n$noMoves',
              name: 'Two', origin: const FileOrigin('two.pgn'))
          .toList();

      final evaluating = progress.whereType<ImportEvaluating>().toList();
      expect(evaluating, isNotEmpty,
          reason: 'a search costs about a quarter of a second each; a silent '
              'pause would look like the app had stopped');
      expect(evaluating.last.done, evaluating.last.total);
    });
  });
}
