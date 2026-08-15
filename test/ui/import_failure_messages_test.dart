import 'dart:math';

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:chess_trainer/ui/library/import_screen.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every row of the lichess-api error contract, on screen (SC-011).
///
/// The requirement is not that these errors exist — `lichess_api_test.dart`
/// covers that — but that each one **reaches the player as a message naming
/// what happened and what to do**, and that none of them leaves a partial
/// collection behind. An error that only appears in a log is an app that
/// stopped for reasons of its own.
void main() {
  late AppDatabase db;
  late DriftCollectionRepository collections;
  late _FailingApi api;

  setUp(() {
    db = AppDatabase.memory();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260814),
      loadSamples: () async => const IList.empty(),
    );
    api = _FailingApi();
    addTearDown(db.close);
  });

  Future<void> pumpImport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          lichessApiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: ImportScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tryImport(WidgetTester tester,
      [String link = 'https://lichess.org/study/9LjyYZ9N']) async {
    await tester.enterText(find.byKey(const Key('study-link')), link);
    await tester.tap(find.byKey(const Key('import-study-link')));
    await tester.pumpAndSettle();
  }

  String messageOn(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('import-failure-message')))
      .data!;

  group('every failure names what happened and what to do', () {
    testWidgets('offline', (tester) async {
      api.failure = NoConnectionError();
      await pumpImport(tester);
      await tryImport(tester);

      expect(messageOn(tester), contains('needs a connection'));
      expect(messageOn(tester), contains('still works offline'),
          reason: 'the player should know the rest of the app is unaffected');
    });

    testWidgets('login expired', (tester) async {
      api.failure = LoginExpiredError();
      await pumpImport(tester);
      await tryImport(tester);

      expect(messageOn(tester), contains('Log in again'));
    });

    testWidgets('not logged in, for a private study', (tester) async {
      api.failure = NotLoggedInError();
      await pumpImport(tester);
      await tryImport(tester);

      expect(messageOn(tester), contains('log in'));
    });

    testWidgets('rate limited says how long', (tester) async {
      api.failure = RateLimitedError();
      await pumpImport(tester);
      await tryImport(tester);

      expect(messageOn(tester), contains('Try again in a minute'));
    });

    testWidgets('a study that is gone or private', (tester) async {
      api.failure = StudyNotAvailableError('9LjyYZ9N');
      await pumpImport(tester);
      await tryImport(tester);

      expect(messageOn(tester), contains('not available to this account'));
    });

    testWidgets('a server problem', (tester) async {
      api.failure = LichessUnavailableError('Lichess answered 503');
      await pumpImport(tester);
      await tryImport(tester);

      expect(messageOn(tester), contains('Lichess had a problem'));
    });

    testWidgets('an address that is not a study says what was expected',
        (tester) async {
      await pumpImport(tester);
      await tryImport(tester, 'https://lichess.org/@/thibault');

      expect(messageOn(tester), contains('not a Lichess study address'));
      expect(messageOn(tester), contains('lichess.org/study/'));
      expect(api.calls, isEmpty,
          reason: 'a mistyped address must cost nothing — it is refused before '
              'a request is made');
    });
  });

  group('no failure leaves anything behind (FR-019, FR-041)', () {
    testWidgets('every one of them imports nothing', (tester) async {
      for (final failure in <Object>[
        NoConnectionError(),
        LoginExpiredError(),
        NotLoggedInError(),
        RateLimitedError(),
        StudyNotAvailableError('9LjyYZ9N'),
        LichessUnavailableError('boom'),
      ]) {
        api.failure = failure;
        await pumpImport(tester);
        await tryImport(tester);

        expect(await collections.listCollections(), isEmpty,
            reason: '$failure left a collection behind');
      }
    });
  });
}

class _FailingApi implements LichessApi {
  final List<String> calls = [];
  Object? failure;

  @override
  Future<String> exportStudy(String studyId) async {
    calls.add('exportStudy');
    if (failure != null) throw failure!;
    return '';
  }

  @override
  Future<List<StudySummary>> listStudies(String username) async => const [];

  @override
  Future<String> username() async => 'roberto';

  @override
  Future<void> revokeToken() async {}
}
