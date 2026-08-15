import 'dart:math';

import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/data/local/drift_session_repository.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_harness.dart';

/// The library repository, against an in-memory database.
///
/// Covers library-api invariants 1, 2, 6, 7, 8 and 9.
void main() {
  late AppDatabase db;
  late DriftCollectionRepository repository;

  IList<TrainingPosition> samples = const IList.empty();

  setUp(() {
    db = AppDatabase.memory();
    samples = samplePositions();
    repository = DriftCollectionRepository(
      db,
      random: Random(20260814),
      loadSamples: () async => samples,
    );
    addTearDown(db.close);
  });

  Future<Collection> storeSamples({
    String name = 'A study',
    CollectionOrigin origin = const FileOrigin('study.pgn'),
    String hash = 'hash-1',
    IList<TrainingPosition>? positions,
    String idPrefix = 'a',
  }) =>
      repository.store(
        name: name,
        origin: origin,
        contentHash: hash,
        // Re-idded per collection, as a real import does: `ImportService`
        // mints a fresh id for every position it creates, so the same study
        // imported twice yields two collections of distinct positions rather
        // than a primary-key clash.
        positions: reIdded(positions ?? samples, idPrefix),
      );

  group('an engine-judged position round-trips (005 FR-007, FR-021)', () {
    test('its source, evaluation and engine survive storage', () async {
      // The solution itself is stored exactly as an authored one is — that is
      // research D3, and it is why review needed no changes. What is new is the
      // three columns saying where the line came from.
      final judged = TrainingPosition(
        id: 'engine-judged',
        initialPosition: samples.first.initialPosition,
        solution: samples.first.solution,
        solutionSource: SolutionSource.engine,
        evaluation: const PositionEvaluation(
          score: Centipawns(142),
          depth: 12,
          perspective: Side.white,
        ),
      );

      final stored = await repository.store(
        name: 'Hand-made',
        origin: const FileOrigin('mine.pgn'),
        contentHash: 'hash-engine',
        positions: IList([judged]),
        engineId: 'stockfish-16 depth 12',
      );

      final read = (await repository.positionsIn(stored.id)).single;

      expect(read.solutionSource, SolutionSource.engine);
      expect(read.evaluation?.score, const Centipawns(142));
      expect(read.evaluation?.depth, 12);
      expect(read.evaluation?.perspective, Side.white);
      expect(read.solution, judged.solution,
          reason: 'an engine line is a solution like any other');
    });

    test('a mate score survives as a mate, not as a large number of pawns',
        () async {
      // Why `Score` is sealed. Crammed into centipawns, "mate in 3" reads as
      // 327.68 pawns at review.
      final judged = TrainingPosition(
        id: 'mating',
        initialPosition: samples.first.initialPosition,
        solution: samples.first.solution,
        solutionSource: SolutionSource.engine,
        evaluation: const PositionEvaluation(
          score: MateIn(5),
          depth: 12,
          perspective: Side.black,
        ),
      );

      final stored = await repository.store(
        name: 'Mate',
        origin: const FileOrigin('mate.pgn'),
        contentHash: 'hash-mate',
        positions: IList([judged]),
        engineId: 'stockfish-16 depth 12',
      );

      final read = (await repository.positionsIn(stored.id)).single;
      expect(read.evaluation?.score, const MateIn(5));
      expect(read.evaluation?.perspective, Side.black);
    });

    test('a position the engine could not judge stores as none', () async {
      // FR-010: still trainable, and review says so rather than showing a blank
      // pane pretending to be a solution.
      final unjudged = TrainingPosition(
        id: 'unjudged',
        initialPosition: samples.first.initialPosition,
        solution: VariationTree.empty(samples.first.initialPosition),
        solutionSource: SolutionSource.none,
      );

      final stored = await repository.store(
        name: 'Unjudged',
        origin: const FileOrigin('mine.pgn'),
        contentHash: 'hash-none',
        positions: IList([unjudged]),
      );

      final read = (await repository.positionsIn(stored.id)).single;
      expect(read.solutionSource, SolutionSource.none);
      expect(read.evaluation, isNull);
    });

    test('an authored position keeps no evaluation at all (FR-011)', () async {
      final stored = await storeSamples(hash: 'hash-authored');
      final read = (await repository.positionsIn(stored.id)).first;

      expect(read.solutionSource, SolutionSource.author);
      expect(read.evaluation, isNull,
          reason: 'where an author said what they intended, the engine is not '
              'consulted and nothing is stored');
    });
  });

  group('invariant 1 — a collection round-trips unchanged', () {
    test('positions come back with their trees, branches and metadata', () async {
      final stored = await storeSamples();

      final read = await repository.positionsIn(stored.id);
      final expected = reIdded(samples, 'a');

      expect(read, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(read[i].id, expected[i].id);
        expect(read[i].initialPosition.fen, expected[i].initialPosition.fen);
        // The whole tree, not just the mainline: branches and which line is
        // primary are what a solution *is*.
        expect(read[i].solution, expected[i].solution);
        expect(read[i].metadata.title, expected[i].metadata.title);
        expect(read[i].metadata.themes, expected[i].metadata.themes);
      }
    });

    test('the header bag survives storage (invariant 6, FR-024)', () async {
      final position = parsedWithHeaders();
      final stored = await storeSamples(positions: IList([position]));

      final read = (await repository.positionsIn(stored.id)).single;

      expect(read.metadata.headers['SomeTagInventedToday'], 'and its value');
      expect(read.metadata.headers['ChapterName'], 'Chapter 3: The answer');
      expect(read.metadata.headers, position.metadata.headers);
    });

    test('collections list newest first, with their counts and origin',
        () async {
      await storeSamples(name: 'First', hash: 'h1', idPrefix: 'first');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await storeSamples(
        name: 'Second',
        hash: 'h2',
        idPrefix: 'second',
        origin: LichessOrigin(
          studyId: 'abcdefgh',
          studyName: 'A Lichess study',
          fetchedAt: DateTime.utc(2026, 8, 14),
        ),
      );

      final all = await repository.listCollections();

      expect(all.map((collection) => collection.name), ['Second', 'First']);
      expect(all.first.positionCount, samples.length);
      expect(all.first.origin, isA<LichessOrigin>());
      expect((all.first.origin as LichessOrigin).studyId, 'abcdefgh');
      expect(all.last.origin, isA<FileOrigin>());
    });
  });

  group('invariant 2 — storing is atomic', () {
    test('a failure part-way leaves no collection and no positions', () async {
      // Two positions sharing an id: the second insert violates the primary
      // key, part-way through the transaction. Nothing may survive it.
      final clashing = IList([samples.first, samples.first]);

      await expectLater(
        repository.store(
          name: 'Doomed',
          origin: const FileOrigin('doomed.pgn'),
          contentHash: 'doomed',
          positions: clashing,
        ),
        throwsA(isA<StorageWriteError>()),
      );

      expect(await repository.listCollections(), isEmpty);
      expect(await db.select(db.positions).get(), isEmpty,
          reason: 'a half-written import must not leave positions behind, '
              'because a study missing its last chapters looks like a study '
              'that was always that short');
    });
  });

  group('invariant 8 — deleting a collection does not touch history', () {
    test('a played session stays readable after its collection is gone',
        () async {
      final sessions = DriftSessionRepository(db, random: Random(1));
      final collection = await storeSamples();
      final positions = await repository.positionsIn(collection.id);

      final session = await sessions.start(positions);
      await sessions.recordGrade(session.id, gradeFor(positions.first.id));
      final before = await sessions.loadSession(session.id);

      await repository.delete(collection.id);

      final after = await sessions.loadSession(session.id);
      expect(after, isNotNull);
      expect(after!.positions, before!.positions,
          reason: 'the session holds its own frozen copy (002 D4); deleting '
              'the library it was drawn from must not reach it');
      expect(after.grades, before.grades);
      expect(after.positions.first.solution, isNotNull);
    });

    test('the positions go, and only those of that collection', () async {
      final kept = await storeSamples(name: 'Kept', hash: 'k', idPrefix: 'kept');
      final doomed = await storeSamples(
        name: 'Doomed',
        hash: 'd',
        idPrefix: 'doomed',
        positions: IList([parsedWithHeaders()]),
      );

      await repository.delete(doomed.id);

      expect(await repository.positionsIn(doomed.id), isEmpty);
      expect(await repository.positionsIn(kept.id), hasLength(samples.length));
      expect(await repository.collection(doomed.id), isNull);
    });
  });

  group('invariant 9 — the samples are seeded exactly once (FR-033)', () {
    test('seeding plants them as an ordinary collection', () async {
      await repository.seedSamplesIfNeeded();

      final all = await repository.listCollections();
      expect(all, hasLength(1));
      expect(all.single.origin, isA<BundledOrigin>());
      expect(all.single.positionCount, samples.length);
    });

    test('seeding twice does not plant them twice', () async {
      await repository.seedSamplesIfNeeded();
      await repository.seedSamplesIfNeeded();

      expect(await repository.listCollections(), hasLength(1));
    });

    test('deleting the samples is permanent', () async {
      await repository.seedSamplesIfNeeded();
      final seeded = (await repository.listCollections()).single;

      await repository.delete(seeded.id);
      await repository.seedSamplesIfNeeded();

      expect(await repository.listCollections(), isEmpty,
          reason: 'seeding when the library is empty would resurrect content '
              'the player deliberately deleted — the app arguing with its '
              'user about what it should contain');
    });
  });

  group('invariant 11 — duplicate detection is by content (FR-010)', () {
    test('the same content is found again by its hash', () async {
      final first =
          await storeSamples(name: 'Exported Monday', hash: 'same', idPrefix: 'mon');

      final found = await repository.findByContentHash('same');

      expect(found, isNotNull);
      expect(found!.id, first.id);
    });

    test('a different name with the same content still matches', () async {
      await storeSamples(name: 'Exported Monday', hash: 'same', idPrefix: 'mon');
      final second =
          await storeSamples(name: 'Exported Friday', hash: 'same', idPrefix: 'fri');

      // Both exist — the warning is advisory, and the player may proceed.
      expect(await repository.listCollections(), hasLength(2));
      expect((await repository.findByContentHash('same'))!.id, second.id);
    });

    test('unknown content matches nothing', () async {
      await storeSamples(hash: 'one');
      expect(await repository.findByContentHash('another'), isNull);
    });
  });

  group('renaming', () {
    test('a rename is visible and does not disturb the positions', () async {
      final collection = await storeSamples(name: 'Old name');

      await repository.rename(collection.id, 'New name');

      expect((await repository.collection(collection.id))!.name, 'New name');
      expect(await repository.positionsIn(collection.id),
          hasLength(samples.length));
    });

    test('names need not be unique (FR-009)', () async {
      await storeSamples(name: 'Endgames', hash: 'a', idPrefix: 'one');
      await storeSamples(name: 'Endgames', hash: 'b', idPrefix: 'two');

      expect(await repository.listCollections(), hasLength(2));
    });
  });

  group('absences are absences, not errors', () {
    test('positions of an unknown collection is empty', () async {
      expect(await repository.positionsIn('no-such-collection'), isEmpty);
    });

    test('an unknown collection is null', () async {
      expect(await repository.collection('no-such-collection'), isNull);
    });
  });
}

/// A position whose headers include one this app has never heard of, so the
/// bag has something conspicuous to lose.
TrainingPosition parsedWithHeaders() => parseTrainingPosition('''
[Event "A tournament"]
[ChapterName "Chapter 3: The answer"]
[Annotator "Somebody"]
[SomeTagInventedToday "and its value"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

1. Kc6 Kc8 2. d6
''', id: 'with-headers');

Grade gradeFor(String positionId) =>
    Grade(positionId: positionId, value: GradeValue.good);

/// Fresh ids, as an import mints them.
///
/// A position id is unique across the whole library, not within a collection:
/// the same study imported twice is two collections of distinct positions.
IList<TrainingPosition> reIdded(IList<TrainingPosition> positions, String prefix) {
  var i = 0;
  return positions
      .map((position) => TrainingPosition(
            id: '$prefix-${i++}',
            initialPosition: position.initialPosition,
            solution: position.solution,
            metadata: position.metadata,
          ))
      .toIList();
}
