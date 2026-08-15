import 'package:chess_trainer/data/local/database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../generated/schema.dart';
import '../generated/schema_v1.dart' as v1;
import '../generated/schema_v2.dart' as v2;

/// The migration harness (002 research D9, FR-025).
///
/// Built at version 1 when there was nothing to migrate, on the reasoning that
/// the update which loses a player's history is always the one where nobody
/// thought about migration. Feature 003 is the first update to use it: v1 → v2
/// adds the library, and the test that matters is that a database holding
/// sessions the player has already played comes through it untouched.
///
/// Two commands keep it honest, and both belong to a schema change rather than
/// to a build:
///
/// ```bash
/// dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
/// dart run drift_dev schema generate drift_schemas/ test/generated/
/// ```
///
/// `drift_schemas/` and `test/generated/` are committed on purpose: a version
/// that has nothing to migrate *from* cannot be tested.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the app creates exactly the schema recorded for version 1', () async {
    final connection = await verifier.startAt(1);
    final database = AppDatabase.forExecutor(connection);
    addTearDown(database.close);

    // Compares every table, column, constraint and index — including the
    // partial unique index that keeps at most one session in progress, which is
    // declared on the table for this reason (research D7).
    await verifier.migrateAndValidate(database, 1);
  });

  test('data written at version 1 is still readable after opening it',
      () async {
    final connection = await verifier.startAt(1);
    final database = AppDatabase.forExecutor(connection);
    addTearDown(database.close);

    await database.into(database.sessions).insert(
          SessionsCompanion.insert(
            id: 'stored-before-the-update',
            startedAt: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
            status: 'complete',
            currentIndex: 0,
          ),
        );

    final rows = await database.select(database.sessions).get();
    expect(rows.single.id, 'stored-before-the-update');
  });

  test('the app creates exactly the schema recorded for version 2', () async {
    final connection = await verifier.startAt(2);
    final database = AppDatabase.forExecutor(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 2);
  });

  test('v1 upgrades to the current schema and it matches', () async {
    final connection = await verifier.startAt(1);
    final database = AppDatabase.forExecutor(connection);
    addTearDown(database.close);

    // Runs onUpgrade and then compares every table, column, constraint and
    // index against the recorded v2 schema — so a migration that creates the
    // tables *slightly* differently from `createAll` fails here rather than on
    // a player's phone.
    //
    // **Validated against the current version, not against v2**, and that is
    // forced rather than chosen. The v1 → v2 step calls `createTable`, which
    // builds tables from today's definitions — so a database upgraded from v1
    // arrives with v3's columns and can never match the v2 snapshot. What is
    // worth asserting is that a v1 database reaches the schema this app
    // actually creates, which is what this does.
    await verifier.migrateAndValidate(database, 3);
  });

  test('a session played at v1 survives the upgrade intact (FR-040)', () async {
    // `schemaAt` rather than `startAt`, because this test needs the *same*
    // database twice: once as the old version to write into, once as the new
    // one to open. `startAt` hands out a fresh database each call, which would
    // make this test pass by finding nothing wrong with data it never wrote.
    final schema = await verifier.schemaAt(1);

    // Written as SQL against the v1 schema on purpose: the generated v1 tables
    // carry no companions, and writing through today's app classes would test
    // the migration against data only today's app could have produced.
    final old = v1.DatabaseAtV1(schema.newConnection());
    final playedAt = DateTime.utc(2026, 8, 1).millisecondsSinceEpoch;
    await old.customStatement(
      'INSERT INTO sessions (id, started_at, ended_at, status, current_index) '
      "VALUES ('played-before-the-library-existed', $playedAt, $playedAt, "
      "'complete', 2)",
    );
    await old.customStatement(
      'INSERT INTO grades (session_id, position_id, value, graded_at) '
      "VALUES ('played-before-the-library-existed', '001-tactic', 'good', "
      '$playedAt)',
    );
    await old.close();

    // Opening it with the current app is the update happening.
    final upgraded = AppDatabase.forExecutor(schema.newConnection());
    addTearDown(upgraded.close);
    await verifier.migrateAndValidate(upgraded, 3);

    final sessions = await upgraded.select(upgraded.sessions).get();
    final grades = await upgraded.select(upgraded.grades).get();

    expect(sessions.single.id, 'played-before-the-library-existed');
    expect(sessions.single.currentIndex, 2);
    expect(grades.single.value, 'good');

    // And the library tables now exist, empty and ready to be seeded.
    expect(await upgraded.select(upgraded.collections).get(), isEmpty);
    expect(await upgraded.select(upgraded.positions).get(), isEmpty);
  });

  test('the app creates exactly the schema recorded for version 3', () async {
    final connection = await verifier.startAt(3);
    final database = AppDatabase.forExecutor(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 3);
  });

  test('a library imported at v2 survives the upgrade, and reads as authored '
      '(005 FR-021, FR-022)', () async {
    // The property this feature has to prove. Feature 005 lets a position be
    // judged by an engine, and every position that already exists was judged by
    // an author — that is not an assumption, it is a fact about what v2 could
    // store: before 005, an entry with no moves was rejected at import.
    //
    // So the migration sets `author` for every existing row, and this asserts
    // it. If it ever set `none` instead, a player's whole library would review
    // as "no evaluation could be produced" after an update.
    final schema = await verifier.schemaAt(2);

    final old = v2.DatabaseAtV2(schema.newConnection());
    final importedAt = DateTime.utc(2026, 8, 14).millisecondsSinceEpoch;
    await old.customStatement(
      'INSERT INTO collections (id, name, origin_kind, origin_ref, '
      'imported_at, content_hash) '
      "VALUES ('col-1', 'Imported before the engine', 'file', 'study.pgn', "
      "$importedAt, 'hash-1')",
    );
    await old.customStatement(
      'INSERT INTO positions (id, collection_id, ordinal, initial_fen, '
      'solution_pgn, metadata_json) '
      "VALUES ('pos-1', 'col-1', 0, "
      "'5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1', '1. Nh6+', '{}')",
    );
    await old.close();

    final upgraded = AppDatabase.forExecutor(schema.newConnection());
    addTearDown(upgraded.close);
    await verifier.migrateAndValidate(upgraded, 3);

    final positions = await upgraded.select(upgraded.positions).get();
    expect(positions.single.id, 'pos-1');
    expect(positions.single.solutionPgn, '1. Nh6+',
        reason: 'nothing is re-parsed, re-evaluated or re-imported');
    expect(positions.single.solutionSource, 'author',
        reason: 'every position that could already exist had an author\'s '
            'line, because v2 rejected entries with no moves');
    expect(positions.single.evaluationJson, isNull);
    expect(positions.single.engineId, isNull);

    final collections = await upgraded.select(upgraded.collections).get();
    expect(collections.single.name, 'Imported before the engine');
  });

  test('the schema snapshot is in step with the database', () async {
    // A schema change with no re-dump would leave the two tests above
    // validating yesterday's schema and passing anyway.
    final database = AppDatabase.memory();
    addTearDown(database.close);

    expect(GeneratedHelper.versions, contains(database.schemaVersion),
        reason: 'the schema was bumped without a re-dump, so the tests above '
            "are validating yesterday's schema and passing anyway");
  });
}
