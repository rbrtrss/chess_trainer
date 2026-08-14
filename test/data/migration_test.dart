import 'package:chess_trainer/data/local/database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../generated/schema.dart';

/// The migration harness (research D9, FR-025).
///
/// There is nothing to migrate yet — this is version 1. That is exactly why it
/// is built now: the update that loses a player's history is always the one
/// where nobody thought about migration, and retrofitting this after real data
/// exists is what fails.
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
