/// The SQLite database, and the only file that knows where it lives.
///
/// **This file is code-generated against.** `flutter test` and `flutter run`
/// fail until `dart run build_runner build --delete-conflicting-outputs` has
/// produced `database.g.dart`, which is gitignored on purpose (research D8).
library;

import 'package:chess_trainer/data/local/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// The name of the partial unique index that keeps at most one session live
/// (research D7). Declared on the `Sessions` table in `tables.dart`.
///
/// Named here so the repository can recognise the constraint failure it raises
/// and translate it into `SessionAlreadyInProgressError` rather than leaking a
/// Drift exception outward.
const String oneSessionInProgressIndex = 'one_session_in_progress';

/// The `app_settings` key that records the bundled samples having been seeded.
///
/// Named here so the repository and the migration agree on it (003 D12).
const String samplesSeededKey = 'samples_seeded';

@DriftDatabase(tables: [
  Sessions,
  SessionPositions,
  Attempts,
  Grades,
  Collections,
  Positions,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  /// The database the app runs on: `<app documents>/chess_trainer.sqlite`.
  ///
  /// `driftDatabase` puts the queries on a background isolate, so no write
  /// blocks the frame the player is looking at.
  AppDatabase() : super(driftDatabase(name: 'chess_trainer'));

  /// An in-memory database, for tests.
  ///
  /// This is what lets the whole data layer be exercised under `flutter test`
  /// with no device attached, which the constitution's testing floor needs.
  AppDatabase.memory() : super(NativeDatabase.memory());

  /// For the migration harness, which opens a database it built itself.
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // `createAll` creates the tables *and* the partial unique index
        // declared on `Sessions`, so the one-session-in-progress rule is part
        // of the schema rather than a statement someone has to remember.
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          // v1 → v2: feature 003 adds the library. Nothing in v1 is altered,
          // so a player's stored sessions cannot be damaged by this migration
          // — which is the property `migration_test.dart` asserts, and the
          // reason the new tables are additions rather than a restructuring.
          //
          // Seeding the bundled samples is deliberately **not** done here. It
          // belongs to the repository, which runs it on both a fresh install
          // and an upgrade, so both paths end in the same state rather than
          // one of them quietly ending somewhere else.
          if (from < 2) {
            await migrator.createTable(collections);
            await migrator.createTable(positions);
            await migrator.createTable(appSettings);
            await migrator.createIndex(collectionsByContent);
            await migrator.createIndex(positionsByCollection);
          }
        },
        beforeOpen: (details) async {
          // Without this, SQLite accepts rows referring to sessions that are
          // not there, and `deleteEverything` would leave orphans behind.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
