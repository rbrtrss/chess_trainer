import 'dart:math';

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:chess_trainer/ui/account/account_bar.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';

/// User Story 1 and User Story 3: the account, on the screen a session starts
/// from (004 FR-001 – FR-014).
///
/// Two of these tests came from `collection_list_test.dart`, where the account
/// used to live. They moved with the control rather than being dropped.
void main() {
  late AppDatabase db;
  late DriftCollectionRepository collections;
  late InMemoryCredentialStore credentials;
  late _StubAuth auth;

  /// Seeded on first read, so a test that wants an empty library says so here
  /// rather than deleting what the repository would immediately put back.
  IList<TrainingPosition> samples = const IList.empty();

  setUp(() {
    db = AppDatabase.memory();
    samples = samplePositions();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260815),
      loadSamples: () async => samples,
    );
    credentials = InMemoryCredentialStore();
    auth = _StubAuth(credentials);
    addTearDown(db.close);
  });

  Future<void> connect({String username = 'roberto'}) => credentials.write(
        token: 'lio_TESTTOKEN',
        expiresAt: DateTime.utc(2099),
        username: username,
      );

  /// A credential the reader will judge expired the moment it looks.
  Future<void> expireCredential({String username = 'roberto'}) =>
      credentials.write(
        token: 'lio_TESTTOKEN',
        expiresAt: DateTime.utc(2020),
        username: username,
      );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          sessionRepositoryProvider.overrideWithValue(
            inMemorySessionRepository(),
          ),
          credentialStoreProvider.overrideWithValue(credentials),
          lichessAuthProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: SessionFlow()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what the first screen says about the account (FR-001, FR-002)', () {
    testWidgets('not connected, when nothing is stored', (tester) async {
      await pumpHome(tester);

      expect(find.byKey(const Key('account-disconnected')), findsOneWidget);
      expect(find.textContaining('Not connected'), findsOneWidget);
    });

    testWidgets('connected, and names the account', (tester) async {
      await connect(username: 'magnus');
      await pumpHome(tester);

      expect(find.byKey(const Key('account-connected')), findsOneWidget);
      expect(find.textContaining('magnus'), findsOneWidget);
    });

    testWidgets('it is there with an empty library too (FR-001)',
        (tester) async {
      // The empty library is a different body state, and it is exactly when a
      // player is most likely to want an account. A bar written into only one
      // of the two branches would be missing here.
      samples = const IList.empty();
      await pumpHome(tester);

      expect(find.byKey(const Key('empty-library')), findsOneWidget);
      expect(find.byKey(const Key('account-disconnected')), findsOneWidget);
    });

    testWidgets('no progress indicator, in any state (SC-005)', (tester) async {
      await connect();
      await pumpHome(tester);

      expect(
        find.descendant(
          of: find.byType(AccountBar),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'a spinner is a wait, and the account is a local read',
      );
    });
  });

  group('the bar is the same height whatever it knows (SC-005, D5)', () {
    testWidgets('unknown, disconnected, connected and expired all match',
        (tester) async {
      // The launch sequence is: nothing known → whatever was stored. If those
      // two heights differ, every cold start reflows once.
      final heights = <String, double>{};

      await pumpHome(tester);
      heights['disconnected'] = tester.getSize(find.byType(AccountBar)).height;

      await connect();
      await pumpHome(tester);
      heights['connected'] = tester.getSize(find.byType(AccountBar)).height;

      await expireCredential();
      await pumpHome(tester);
      heights['expired'] = tester.getSize(find.byType(AccountBar)).height;

      expect(heights.values.toSet(), hasLength(1), reason: 'states differ: $heights');
      expect(heights['connected'], accountBarHeight);
    });

    testWidgets('and the same before the read has landed', (tester) async {
      await connect();
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // A store that takes its time, so the window where the answer is not yet
      // known is a real frame rather than a race. On a device the wait is the
      // Android keystore warming up on a cold start.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionRepositoryProvider.overrideWithValue(collections),
            sessionRepositoryProvider
                .overrideWithValue(inMemorySessionRepository()),
            credentialStoreProvider
                .overrideWithValue(_SlowStore(credentials)),
            lichessAuthProvider.overrideWithValue(auth),
          ],
          child: const MaterialApp(
            home: Scaffold(bottomNavigationBar: AccountBar()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('account-bar-unknown')), findsOneWidget);
      expect(tester.getSize(find.byType(AccountBar)).height, accountBarHeight);
      expect(find.textContaining('Not connected'), findsNothing,
          reason: 'guessing at disconnected and flipping to a username a frame '
              'later teaches the player that the app does not know what it is '
              'saying');

      // And when it lands, the bar fills in without changing size — which is
      // the whole point of reserving the space.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-connected')), findsOneWidget);
      expect(tester.getSize(find.byType(AccountBar)).height, accountBarHeight);
    });
  });

  group('connecting (FR-003, FR-007, FR-008, FR-009, FR-010)', () {
    testWidgets('the disclosure is shown before the browser opens',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('connect-lichess')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('connect-lichess-sheet')), findsOneWidget);
      expect(find.textContaining('only to read your studies'), findsOneWidget);
      expect(auth.logIns, 0,
          reason: 'nothing has been granted yet, and nothing should have been '
              'asked for');
    });

    testWidgets('confirming logs in, and the bar then names the account',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('connect-lichess')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-log-in')));
      await tester.pumpAndSettle();

      expect(auth.logIns, 1);
      expect(find.byKey(const Key('account-connected')), findsOneWidget);
      expect(find.textContaining('roberto'), findsOneWidget);
    });

    testWidgets('dismissing the sheet asks for nothing', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('connect-lichess')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(AccountBar))).pop();
      await tester.pumpAndSettle();

      expect(auth.logIns, 0);
      expect(find.byKey(const Key('account-disconnected')), findsOneWidget);
    });

    testWidgets('a cancelled login is reported as nothing at all (FR-009)',
        (tester) async {
      auth.failure = LoginCancelledError();
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('connect-lichess')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-log-in')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing,
          reason: 'backing out of a login is a normal outcome, not a failure '
              'to tell someone about');
      expect(find.byKey(const Key('account-disconnected')), findsOneWidget);
    });

    testWidgets('a failed login says what happened and leaves a working screen',
        (tester) async {
      auth.failure = NoConnectionError('no route to host');
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('connect-lichess')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-log-in')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-login-failure')), findsOneWidget);
      expect(find.textContaining('needs a connection'), findsOneWidget);
      expect(find.byKey(const Key('account-disconnected')), findsOneWidget);
      expect(find.byKey(const Key('start-session')), findsOneWidget,
          reason: 'a failed login must not cost the player the screen');
    });
  });

  group('an expired login (FR-013, FR-014)', () {
    testWidgets('says so, and names whose it was', (tester) async {
      await expireCredential(username: 'magnus');
      await pumpHome(tester);

      expect(find.byKey(const Key('account-expired')), findsOneWidget);
      expect(find.textContaining('magnus'), findsOneWidget);
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('offers a login, not a renewal', (tester) async {
      // Lichess issues no refresh tokens, so there is nothing to renew. The way
      // back is the same login as a first connection.
      await expireCredential();
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('log-in-again')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-log-in')));
      await tester.pumpAndSettle();

      expect(auth.logIns, 1);
      expect(find.byKey(const Key('account-connected')), findsOneWidget);
    });

    testWidgets('can be cleared by disconnecting instead (FR-011)',
        (tester) async {
      await expireCredential();
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('disconnect-lichess')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-disconnected')), findsOneWidget);
    });
  });

  group('disconnecting (FR-011, SC-010)', () {
    testWidgets('forgets the login and keeps the collections', (tester) async {
      // Moved from `collection_list_test.dart` with the control it covers.
      await connect();
      await pumpHome(tester);

      expect(find.textContaining('Connected as roberto'), findsOneWidget);
      final before = await collections.listCollections();

      await tester.tap(find.byKey(const Key('disconnect-lichess')));
      await tester.pumpAndSettle();

      expect(auth.logOuts, 1);
      expect(find.byKey(const Key('account-disconnected')), findsOneWidget);
      expect(await collections.listCollections(), hasLength(before.length),
          reason: 'imported collections are local content now, not a view onto '
              'the account');
    });
  });

  group('the account says nothing about the content (FR-021)', () {
    testWidgets('the bar is identical with no collections and with several',
        (tester) async {
      await connect();
      await pumpHome(tester);
      final withCollections = _barWords(tester);

      samples = const IList.empty();
      await pumpHome(tester);

      expect(_barWords(tester), withCollections,
          reason: 'a bar that changed with the library would be carrying '
              'information about the content into the screen a session starts '
              'from');
    });
  });

  group('Lichess is optional (FR-005, FR-006, SC-003)', () {
    testWidgets('a session starts, runs and reviews with no account',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byKey(const Key('start-session')));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('commit-attempt')));
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const Key('account-login-failure')), findsNothing);
      expect(find.byKey(const Key('connect-lichess-sheet')), findsNothing,
          reason: 'the player was never asked, because they never asked');
    });
  });
}

/// Every word the bar puts on screen, in order.
List<String?> _barWords(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(AccountBar), matching: find.byType(Text)),
    )
    .map((text) => text.data)
    .toList();

/// A credential store that answers a frame late, so the not-yet-known state
/// can be looked at.
class _SlowStore implements CredentialStore {
  _SlowStore(this._inner);

  final CredentialStore _inner;

  @override
  Future<LichessConnection?> readConnection() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _inner.readConnection();
  }

  @override
  Future<String?> readToken() => _inner.readToken();

  @override
  Future<void> write({
    required String token,
    required DateTime expiresAt,
    required String username,
  }) =>
      _inner.write(token: token, expiresAt: expiresAt, username: username);

  @override
  Future<void> clear() => _inner.clear();

  @override
  Future<void> expireToken() => _inner.expireToken();
}

/// A login that stores a credential without a browser, and can fail on demand.
class _StubAuth implements LichessAuth {
  _StubAuth(this._credentials);

  final CredentialStore _credentials;

  int logIns = 0;
  int logOuts = 0;

  /// Thrown by [logIn] when set.
  Object? failure;

  @override
  Future<LichessConnection> logIn() async {
    final failure = this.failure;
    if (failure != null) throw failure;

    logIns++;
    final connection = LichessConnection(
      username: 'roberto',
      expiresAt: DateTime.utc(2099),
    );
    await _credentials.write(
      token: 'lio_TESTTOKEN',
      expiresAt: connection.expiresAt,
      username: connection.username,
    );
    return connection;
  }

  @override
  Future<void> logOut() async {
    logOuts++;
    await _credentials.clear();
  }
}
