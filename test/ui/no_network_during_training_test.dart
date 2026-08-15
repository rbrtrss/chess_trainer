import 'dart:math';

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/ui/history/history_screen.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';

/// **The behavioural half of the guarantee feature 003 gave up** (research
/// D14, FR-015, FR-016, SC-009).
///
/// Until this feature the release build declared no INTERNET permission and was
/// therefore incapable of reaching the network — enforced by the operating
/// system. Importing from Lichess needs that permission, so the guarantee is
/// gone.
///
/// What replaces it is this: the whole training flow runs against a Lichess
/// client whose every method fails the test on contact. Not "the app cannot
/// reach the network" but "the app does not, unless the player asked".
///
/// If this test is ever weakened to make something else pass, the replacement
/// guarantee is gone too and nothing is left.
void main() {
  IList<TrainingPosition> positions() => IList(
        List.generate(
          3,
          (i) => parseTrainingPosition('''
[Title "Secret title $i"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4 e5 2. Nf3
''', id: 'offline-$i'),
        ),
      );

  late _ExplodingApi api;
  late _ExplodingAuth auth;
  late AppDatabase db;

  setUp(() {
    api = _ExplodingApi();
    auth = _ExplodingAuth();
    db = AppDatabase.memory();
    addTearDown(db.close);
  });

  Future<void> pumpApp(WidgetTester tester, {bool loggedIn = false}) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final collections = DriftCollectionRepository(
      db,
      random: Random(20260814),
      loadSamples: () async => positions(),
    );

    final credentials = InMemoryCredentialStore();
    if (loggedIn) {
      await credentials.write(
        token: 'lio_TESTTOKEN',
        expiresAt: DateTime.utc(2099),
        username: 'roberto',
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          sessionRepositoryProvider.overrideWithValue(
            inMemorySessionRepository(),
          ),
          credentialStoreProvider.overrideWithValue(credentials),
          // Any contact with either of these fails the test.
          lichessApiProvider.overrideWithValue(api),
          lichessAuthProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: SessionFlow()),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoContact(String phase) {
    expect(api.calls, isEmpty,
        reason: 'the app called Lichess during $phase. Nothing may reach the '
            'network except an import or a login the player asked for '
            '(FR-015)');
    expect(auth.calls, isEmpty,
        reason: 'the app touched the login during $phase');
  }

  testWidgets('opening the app makes no request', (tester) async {
    await pumpApp(tester);

    // Including the seeding of the samples, which happens on first run and is
    // the most tempting place to "just check for updates".
    expectNoContact('startup');
  });

  testWidgets('opening the app while logged in makes none either',
      (tester) async {
    // Feature 004 put the account on the home screen, so the app now reads
    // account state on the launch path and shows a username on the first
    // screen. **This test was not relaxed to allow that.** `_ExplodingAuth`
    // still fails on every method it has; the read goes through
    // `LichessAccountReader`, which is built on the credential store and holds
    // no client (004 research D1, FR-004).
    //
    // If a future change makes this test need an exception, the exception is
    // the bug.
    await pumpApp(tester, loggedIn: true);

    expect(find.textContaining('roberto'), findsOneWidget,
        reason: 'the account must actually be on screen — otherwise this test '
            'passes by not exercising the thing it is about');
    expectNoContact('startup while logged in');
  });

  testWidgets('a whole session — setup, training, commits, review — makes none',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();
    expectNoContact('starting a session');

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('commit-attempt')));
      await tester.pumpAndSettle();
      expectNoContact('committing position ${i + 1}');
    }

    // Review.
    expectNoContact('review');
  });

  testWidgets('browsing history makes none', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('open-history')));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryScreen), findsOneWidget);
    expectNoContact('history');
  });

  testWidgets('opening the import screen makes none until asked',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('open-import')));
    await tester.pumpAndSettle();

    // Merely arriving at the import screen must not fetch anything: a screen
    // that fetches on build is a screen that fetches when the player is on a
    // train with no signal, for nothing.
    expectNoContact('opening the import screen');
  });

  testWidgets('but asking to import a study does reach it', (tester) async {
    // Without this, every assertion above could be passing because the fake is
    // wired to nothing. This is the control: the same overrides, and the one
    // action that *should* reach the network does.
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('open-import')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('study-link')),
        'https://lichess.org/study/9LjyYZ9N');
    api.silent = true;
    await tester.tap(find.byKey(const Key('import-study-link')));
    await tester.pumpAndSettle();

    expect(api.calls, ['exportStudy'],
        reason: 'the player asked for this one, and it must actually go');
  });

  testWidgets('an engine-judged position needs no network either (005 FR-008)',
      (tester) async {
    // Feature 005 is the first content feature since 002 that adds no network
    // path at all: the engine is on the device, so a position judged by one
    // reviews on a plane exactly as an authored one does. Worth asserting
    // rather than assuming, since the whole argument for embedding a 39 MB
    // neural network was that this stays true (005 research D10).
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('commit-attempt')));
      await tester.pumpAndSettle();
    }

    expectNoContact('a whole session on engine-judged content');
  });

  testWidgets('resuming an interrupted session makes none', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('start-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit-attempt')));
    await tester.pumpAndSettle();

    // Rebuild from scratch, as a relaunch would.
    await pumpApp(tester);
    expectNoContact('relaunch with a session to resume');
  });
}

/// A Lichess client that fails the test if it is touched.
class _ExplodingApi implements LichessApi {
  final List<String> calls = [];

  /// Records instead of failing, for the control test above.
  bool silent = false;

  Never _explode(String method) {
    calls.add(method);
    if (silent) throw const _NotToday();
    fail('LichessApi.$method was called outside an explicit import or login');
  }

  @override
  Future<String> username() async => _explode('username');

  @override
  Future<List<StudySummary>> listStudies(String username) async =>
      _explode('listStudies');

  @override
  Future<String> exportStudy(String studyId) async => _explode('exportStudy');

  @override
  Future<void> revokeToken() async => _explode('revokeToken');
}

class _NotToday implements Exception {
  const _NotToday();
}

class _ExplodingAuth implements LichessAuth {
  final List<String> calls = [];

  Never _explode(String method) {
    calls.add(method);
    fail('LichessAuth.$method was called outside an explicit login');
  }

  @override
  Future<LichessConnection> logIn() async => _explode('logIn');

  @override
  Future<void> logOut() async => _explode('logOut');

  // No `current()` to answer, and that is the point. Until feature 004 this
  // fake had to explode on a method that only read local storage; the account
  // is now read through `LichessAccountReader`, so every method that remains
  // here is genuinely a network call and every one of them still explodes
  // (004 research D1).
}
