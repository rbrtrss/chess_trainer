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

@DriftDatabase(tables: [Sessions, SessionPositions, Attempts, Grades])
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // `createAll` creates the tables *and* the partial unique index
        // declared on `Sessions`, so the one-session-in-progress rule is part
        // of the schema rather than a statement someone has to remember.
        onCreate: (migrator) => migrator.createAll(),
        beforeOpen: (details) async {
          // Without this, SQLite accepts rows referring to sessions that are
          // not there, and `deleteEverything` would leave orphans behind.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
