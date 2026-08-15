import 'dart:math';

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/data/local/drift_session_repository.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/ui/library/collection_list_screen.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';

/// User Story 4: managing what has been imported (FR-033 – FR-039, FR-022).
void main() {
  late AppDatabase db;
  late DriftCollectionRepository collections;
  late DriftSessionRepository sessions;

  IList<TrainingPosition> samples = const IList.empty();

  setUp(() {
    db = AppDatabase.memory();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260814),
      loadSamples: () async => samples,
    );
    sessions = DriftSessionRepository(db, random: Random(1));
    // Nothing is seeded unless a test asks for it: the samples are an ordinary
    // collection now, and most of these tests are about other ones.
    samples = const IList.empty();
    addTearDown(db.close);
  });

  Future<Collection> add(String name, {String prefix = 'p', int count = 3}) =>
      collections.store(
        name: name,
        origin: FileOrigin('$name.pgn'),
        contentHash: name,
        positions: _positions(prefix, count),
      );

  Future<void> pumpLibrary(
    WidgetTester tester, {
    LichessAuth? auth,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          sessionRepositoryProvider.overrideWithValue(sessions),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          if (auth != null) lichessAuthProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: CollectionListScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the list (FR-034)', () {
    testWidgets('shows name, origin, count and import date', (tester) async {
      await add('Rook endgames');
      await pumpLibrary(tester);

      expect(find.text('Rook endgames'), findsOneWidget);
      expect(find.textContaining('Rook endgames.pgn'), findsOneWidget);
      expect(find.textContaining('3 positions'), findsOneWidget);
      expect(find.textContaining('imported '), findsOneWidget);
    });

    testWidgets('says so when there is nothing', (tester) async {
      await pumpLibrary(tester);
      expect(find.byKey(const Key('library-empty')), findsOneWidget);
    });
  });

  group('renaming (FR-035)', () {
    testWidgets('the new name is used', (tester) async {
      final collection = await add('Old name');
      await pumpLibrary(tester);

      await tester.tap(find.byKey(Key('rename-${collection.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rename-field')), 'New name');
      await tester.tap(find.byKey(const Key('rename-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('New name'), findsOneWidget);
      expect(find.text('Old name'), findsNothing);
    });
  });

  group('deleting (FR-036, FR-037)', () {
    testWidgets('warns that it cannot be undone', (tester) async {
      final collection = await add('Doomed');
      await pumpLibrary(tester);

      await tester.tap(find.byKey(Key('delete-${collection.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete-collection-warning')), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
    });

    testWidgets('cancelling keeps it', (tester) async {
      final collection = await add('Kept');
      await pumpLibrary(tester);

      await tester.tap(find.byKey(Key('delete-${collection.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Kept'), findsOneWidget);
      expect(await collections.listCollections(), hasLength(1));
    });

    testWidgets('confirming removes it', (tester) async {
      final collection = await add('Doomed');
      await pumpLibrary(tester);

      await tester.tap(find.byKey(Key('delete-${collection.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Doomed'), findsNothing);
      expect(await collections.listCollections(), isEmpty);
    });

    testWidgets('a played session stays readable afterwards (SC-012)',
        (tester) async {
      final collection = await add('Played against');
      final positions = await collections.positionsIn(collection.id);

      // Played to the end, not left in progress: an *unfinished* session that
      // depends on this collection is a different case, covered below, where
      // deleting forfeits it on purpose (FR-038).
      final session = await sessions.start(positions);
      for (final position in positions) {
        await sessions.commitAttempt(session.id, sampleAttempt(position));
      }
      await sessions.recordGrade(
        session.id,
        Grade(positionId: positions.first.id, value: GradeValue.good),
      );
      final before = await sessions.loadSession(session.id);

      await pumpLibrary(tester);
      await tester.tap(find.byKey(Key('delete-${collection.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();

      final after = await sessions.loadSession(session.id);
      expect(after!.positions, before!.positions,
          reason: 'each session keeps its own copy of what it showed (002 D4), '
              'so deleting the library it came from cannot reach it');
      expect(after.grades, before.grades);
    });
  });

  group('deleting what the unfinished session needs (FR-038)', () {
    testWidgets('warns in the same terms as abandoning, and discards it',
        (tester) async {
      final collection = await add('In use');
      final positions = await collections.positionsIn(collection.id);
      await sessions.start(positions);

      await pumpLibrary(tester);
      await tester.tap(find.byKey(Key('delete-${collection.id}')));
      await tester.pumpAndSettle();

      // The same words the abandon warning uses: the player is forfeiting
      // answers, not tidying up.
      expect(find.textContaining('no answers will be shown'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();

      expect(await sessions.loadInProgress(), isNull);
      expect(await collections.listCollections(), isEmpty);
    });

    testWidgets('an unrelated collection carries no such warning',
        (tester) async {
      final inUse = await add('In use', prefix: 'used');
      final other = await add('Unrelated', prefix: 'other');
      await sessions.start(await collections.positionsIn(inUse.id));

      await pumpLibrary(tester);
      await tester.tap(find.byKey(Key('delete-${other.id}')));
      await tester.pumpAndSettle();

      expect(find.textContaining('no answers will be shown'), findsNothing);
      expect(find.textContaining('stay readable'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();

      expect(await sessions.loadInProgress(), isNotNull,
          reason: 'deleting a collection the session does not use must not '
              'cost the player the session');
    });
  });

  group('the bundled samples are an ordinary collection (FR-033)', () {
    testWidgets('they can be deleted and do not come back', (tester) async {
      samples = _positions('sample', 3);
      await collections.seedSamplesIfNeeded();
      await pumpLibrary(tester);

      final seeded = (await collections.listCollections()).single;
      expect(find.textContaining('Included with the app'), findsOneWidget);

      await tester.tap(find.byKey(Key('delete-${seeded.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();

      // A relaunch would seed again if the flag were not set.
      await collections.seedSamplesIfNeeded();
      expect(await collections.listCollections(), isEmpty);
    });
  });

  group('the Lichess connection (FR-022)', () {
    testWidgets('shows as not connected when there is no login',
        (tester) async {
      await pumpLibrary(tester, auth: _StubAuth());

      expect(find.byKey(const Key('lichess-disconnected')), findsOneWidget);
    });

    testWidgets('disconnecting forgets the login and keeps the collections',
        (tester) async {
      final auth = _StubAuth(
        connection: LichessConnection(
          username: 'roberto',
          expiresAt: DateTime.utc(2027),
        ),
      );
      await add('Imported from Lichess');
      await pumpLibrary(tester, auth: auth);

      expect(find.textContaining('Connected as roberto'), findsOneWidget);

      await tester.tap(find.byKey(const Key('disconnect-lichess')));
      await tester.pumpAndSettle();

      expect(auth.loggedOut, isTrue);
      expect(await collections.listCollections(), hasLength(1),
          reason: 'imported collections are local content now, not a view onto '
              'the account');
    });
  });
}

IList<TrainingPosition> _positions(String prefix, int count) => IList(
      List.generate(
        count,
        (i) => parseTrainingPosition('''
[Title "$prefix secret $i"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4 e5 2. Nf3
''', id: '$prefix-$i'),
      ),
    );

class _StubAuth implements LichessAuth {
  _StubAuth({this.connection});

  LichessConnection? connection;
  bool loggedOut = false;

  @override
  Future<LichessConnection?> current() async => connection;

  @override
  Future<LichessConnection> logIn() async =>
      connection ??
      LichessConnection(username: 'roberto', expiresAt: DateTime.utc(2027));

  @override
  Future<void> logOut() async {
    loggedOut = true;
    connection = null;
  }
}
