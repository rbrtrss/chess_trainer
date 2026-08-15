/// The library, stored in SQLite.
///
/// See `specs/003-position-import/contracts/library-api.md`. Nothing outside
/// `lib/data/local/` knows this file exists; the app codes against
/// `CollectionRepository`.
library;

import 'dart:math';

import 'package:chess_trainer/data/bundled_position_source.dart';
import 'package:chess_trainer/data/collection_repository.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/evaluation_json.dart';
import 'package:chess_trainer/data/local/metadata_json.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:dartchess/dartchess.dart';
import 'package:drift/drift.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// How the bundled samples are named when they are seeded (FR-033).
const String bundledCollectionName = 'Sample positions';

/// Loads the positions to seed. Injectable so tests need no asset bundle.
typedef SampleLoader = Future<IList<TrainingPosition>> Function();

class DriftCollectionRepository implements CollectionRepository {
  DriftCollectionRepository(
    this._db, {
    Random? random,
    SampleLoader? loadSamples,
  })  : _random = random ?? Random(),
        _loadSamples = loadSamples ?? const BundledPositionSource().loadAll;

  final AppDatabase _db;
  final Random _random;
  final SampleLoader _loadSamples;

  // ------------------------------------------------------------- reading

  @override
  Future<IList<Collection>> listCollections() async {
    final query = _db.select(_db.collections)
      ..orderBy([(row) => OrderingTerm.desc(row.importedAt)]);
    final rows = await query.get();

    final result = <Collection>[];
    for (final row in rows) {
      result.add(await _toCollection(row));
    }
    return result.lock;
  }

  @override
  Future<Collection?> collection(String collectionId) async {
    final row = await (_db.select(_db.collections)
          ..where((table) => table.id.equals(collectionId)))
        .getSingleOrNull();
    return row == null ? null : _toCollection(row);
  }

  @override
  Future<IList<TrainingPosition>> positionsIn(String collectionId) async {
    final query = _db.select(_db.positions)
      ..where((table) => table.collectionId.equals(collectionId))
      ..orderBy([(row) => OrderingTerm.asc(row.ordinal)]);
    final rows = await query.get();

    var positions = const IList<TrainingPosition>.empty();
    for (final row in rows) {
      positions = positions.add(_toPosition(row));
    }
    return positions;
  }

  @override
  Future<Collection?> findByContentHash(String contentHash) async {
    final row = await (_db.select(_db.collections)
          ..where((table) => table.contentHash.equals(contentHash))
          ..orderBy([(table) => OrderingTerm.desc(table.importedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toCollection(row);
  }

  // ------------------------------------------------------------- writing

  @override
  Future<Collection> store({
    required String name,
    required CollectionOrigin origin,
    required String contentHash,
    required IList<TrainingPosition> positions,
    DateTime? now,
    String? engineId,
  }) async {
    if (positions.isEmpty) {
      throw ArgumentError('a collection needs at least one position');
    }

    final importedAt = _stamp(now);
    final id = _newId(importedAt);

    try {
      // One transaction, so a failure part-way leaves no collection row and no
      // positions. An import that produced half a study would be invisible
      // until the player wondered where the last four chapters went.
      await _db.transaction(() async {
        await _db.into(_db.collections).insert(
              CollectionsCompanion.insert(
                id: id,
                name: name,
                originKind: _originKind(origin),
                originRef: Value(_originRef(origin)),
                originLabel: Value(_originLabel(origin)),
                importedAt: importedAt.millisecondsSinceEpoch,
                contentHash: contentHash,
              ),
            );

        for (var ordinal = 0; ordinal < positions.length; ordinal++) {
          final position = positions[ordinal];
          await _db.into(_db.positions).insert(
                PositionsCompanion.insert(
                  id: position.id,
                  collectionId: id,
                  ordinal: ordinal,
                  initialFen: position.initialPosition.fen,
                  solutionPgn: encodeTree(position.solution),
                  metadataJson: encodeMetadata(position.metadata),
                  solutionSource:
                      Value(encodeSolutionSource(position.solutionSource)),
                  evaluationJson: Value(position.evaluation == null
                      ? null
                      : encodeEvaluation(position.evaluation!)),
                  engineId: Value(engineId),
                ),
              );
        }
      });
    } on Object catch (error) {
      if (error is StorageWriteError) rethrow;
      throw StorageWriteError('importing "$name"', error);
    }

    return Collection(
      id: id,
      name: name,
      origin: origin,
      importedAt: importedAt,
      positionCount: positions.length,
    );
  }

  @override
  Future<void> rename(String collectionId, String name) async {
    try {
      await (_db.update(_db.collections)
            ..where((table) => table.id.equals(collectionId)))
          .write(CollectionsCompanion(name: Value(name)));
    } on Object catch (error) {
      throw StorageWriteError('renaming the collection', error);
    }
  }

  @override
  Future<void> delete(String collectionId) async {
    try {
      // The positions go with it, by the cascade declared on the table. The
      // player's *sessions* do not: `session_positions` holds its own frozen
      // copy and refers to nothing here, so a past review survives this
      // (FR-037). That is a decision feature 002 made, not a coincidence.
      await (_db.delete(_db.collections)
            ..where((table) => table.id.equals(collectionId)))
          .go();
    } on Object catch (error) {
      throw StorageWriteError('deleting the collection', error);
    }
  }

  @override
  Future<void> seedSamplesIfNeeded() async {
    if (await _flag(samplesSeededKey)) return;

    final samples = await _loadSamples();
    if (samples.isEmpty) return;

    await store(
      name: bundledCollectionName,
      origin: const BundledOrigin(),
      contentHash: 'bundled:${samples.map((p) => p.id).join(',')}',
      positions: samples,
    );

    // Set *after* the store succeeds, so a failed seed is retried next launch
    // rather than silently skipped forever. Set at all — rather than seeding
    // whenever the library is empty — so that deleting the samples is
    // permanent (FR-033).
    await _setFlag(samplesSeededKey);
  }

  // ------------------------------------------------------------- plumbing

  Future<bool> _flag(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((table) => table.key.equals(key)))
        .getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> _setFlag(String key) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(AppSettingRow(key: key, value: 'true'));

  Future<Collection> _toCollection(CollectionRow row) async {
    final count = await _countPositions(row.id);
    return Collection(
      id: row.id,
      name: row.name,
      origin: _toOrigin(row),
      importedAt: DateTime.fromMillisecondsSinceEpoch(row.importedAt,
          isUtc: true),
      positionCount: count,
    );
  }

  Future<int> _countPositions(String collectionId) async {
    final count = _db.positions.id.count();
    final query = _db.selectOnly(_db.positions)
      ..addColumns([count])
      ..where(_db.positions.collectionId.equals(collectionId));
    return (await query.getSingle()).read(count) ?? 0;
  }

  TrainingPosition _toPosition(PositionRow row) {
    final Position initial;
    try {
      initial = Chess.fromSetup(Setup.parseFen(row.initialFen));
    } on Object catch (error) {
      throw TreeDecodeError('stored FEN "${row.initialFen}" is invalid: $error');
    }
    return TrainingPosition(
      id: row.id,
      initialPosition: initial,
      solution: decodeTree(row.solutionPgn),
      metadata: decodeMetadata(row.metadataJson),
      solutionSource: decodeSolutionSource(row.solutionSource),
      evaluation: row.evaluationJson == null
          ? null
          : decodeEvaluation(row.evaluationJson!),
    );
  }

  CollectionOrigin _toOrigin(CollectionRow row) => switch (row.originKind) {
        'file' => FileOrigin(row.originRef ?? ''),
        'lichess' => LichessOrigin(
            studyId: row.originRef ?? '',
            studyName: row.originLabel ?? '',
            fetchedAt: DateTime.fromMillisecondsSinceEpoch(row.importedAt,
                isUtc: true),
          ),
        // Anything else, including a value written by a future version, reads
        // as bundled rather than throwing: an unknown origin is a display
        // detail, and refusing to list a collection over it would be a poor
        // trade.
        _ => const BundledOrigin(),
      };

  String _originKind(CollectionOrigin origin) => switch (origin) {
        BundledOrigin() => 'bundled',
        FileOrigin() => 'file',
        LichessOrigin() => 'lichess',
      };

  String? _originRef(CollectionOrigin origin) => switch (origin) {
        BundledOrigin() => null,
        FileOrigin(:final fileName) => fileName,
        LichessOrigin(:final studyId) => studyId,
      };

  String? _originLabel(CollectionOrigin origin) => switch (origin) {
        LichessOrigin(:final studyName) => studyName,
        _ => null,
      };

  String _newId(DateTime importedAt) {
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'c${importedAt.millisecondsSinceEpoch.toRadixString(16)}-$suffix';
  }

  /// UTC, truncated to the millisecond the column can hold.
  DateTime _stamp(DateTime? now) {
    final moment = (now ?? DateTime.now()).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      moment.millisecondsSinceEpoch,
      isUtc: true,
    );
  }
}
