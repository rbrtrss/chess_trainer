import 'dart:math';

import 'package:chess_trainer/data/import_parser.dart';
import 'package:chess_trainer/data/import_service.dart';
import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:chess_trainer/ui/library/import_screen.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:chess_trainer/ui/library/study_picker_screen.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// User Story 2: **import does not ask anyone to log in** (004 FR-015 – FR-018).
///
/// Until this feature the login lived two screens inside here, which is what
/// made the account feel like a property of importing. The assertions below are
/// mostly about things *not* being on screen, so each one names the state it
/// checked — an absence that was never reachable proves nothing.
void main() {
  late AppDatabase db;
  late DriftCollectionRepository collections;
  late InMemoryCredentialStore credentials;
  late _ExplodingAuth auth;
  late _StubApi api;

  setUp(() {
    db = AppDatabase.memory();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260815),
      loadSamples: () async => const IList.empty(),
    );
    credentials = InMemoryCredentialStore();
    auth = _ExplodingAuth();
    api = _StubApi();
    addTearDown(db.close);
  });

  Future<void> connect() => credentials.write(
        token: 'lio_TESTTOKEN',
        expiresAt: DateTime.utc(2099),
        username: 'roberto',
      );

  Future<void> expireCredential() => credentials.write(
        token: 'lio_TESTTOKEN',
        expiresAt: DateTime.utc(2020),
        username: 'roberto',
      );

  Future<void> pumpImport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          // Parsed in-process. The real service parses on another isolate,
          // which never settles under `pumpAndSettle`; what is under test here
          // is which screens offer a login, not where parsing runs.
          importServiceProvider.overrideWithValue(
            DefaultImportService(
              collections,
              parse: (source) async => parseImport(source, newId: timestampIds()),
            ),
          ),
          credentialStoreProvider.overrideWithValue(credentials),
          lichessAuthProvider.overrideWithValue(auth),
          lichessApiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: ImportScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Everything the deleted log-in prompt used to put on screen.
  void expectNoLoginOffered(String state) {
    expect(find.byKey(const Key('log-in-to-lichess')), findsNothing,
        reason: 'import offered a login while $state (FR-015)');
    expect(find.byKey(const Key('lichess-login-prompt')), findsNothing,
        reason: 'the log-in prompt is still reachable while $state');
    expect(find.byKey(const Key('connect-lichess')), findsNothing,
        reason: 'the account control belongs on the home screen only '
            '(FR-012), and it appeared while $state');
    expect(auth.logIns, 0,
        reason: 'import started a login while $state — it may assume an '
            'account, never establish one');
  }

  group('the import screen itself (FR-015)', () {
    testWidgets('offers no login while disconnected', (tester) async {
      await pumpImport(tester);

      expectNoLoginOffered('disconnected');
    });

    testWidgets('offers no login while connected', (tester) async {
      await connect();
      await pumpImport(tester);

      expectNoLoginOffered('connected');
    });

    testWidgets('offers no login while expired', (tester) async {
      await expireCredential();
      await pumpImport(tester);

      expectNoLoginOffered('expired');
    });
  });

  group('what import says, not just what it offers (FR-015, FR-017)', () {
    /// Every string the screen puts in front of the player.
    List<String> visibleText(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();

    testWidgets('nothing tells the player to log in without saying where',
        (tester) async {
      // **Found on the device, not here.** The screen kept 003's line — "pick
      // one of your own after logging in" — which points at a control this
      // feature removed and does not say where the account went. Every
      // assertion in this file was about widgets that must not exist; none was
      // about the prose, and prose is what the player actually reads.
      //
      // "Log in again from the home screen" is fine: it names the place. A
      // bare instruction to log in is not.
      for (final state in ['disconnected', 'connected', 'expired']) {
        if (state == 'connected') await connect();
        if (state == 'expired') await expireCredential();
        await pumpImport(tester);

        for (final line in visibleText(tester)) {
          final mentionsLogin = line.toLowerCase().contains('log in') ||
              line.toLowerCase().contains('logging in') ||
              line.toLowerCase().contains('login');
          if (!mentionsLogin) continue;

          expect(line.toLowerCase(), contains('home screen'),
              reason: 'while $state, import says "$line" — it sends the player '
                  'to look for a login that is not on this screen and does not '
                  'say where it is (FR-015, FR-017)');
        }
        await credentials.clear();
      }
    });
  });

  group('asking for my own studies (FR-017, FR-018)', () {
    testWidgets('disconnected: says what is needed, and goes nowhere',
        (tester) async {
      await pumpImport(tester);

      await tester.tap(find.byKey(const Key('pick-my-studies')));
      await tester.pumpAndSettle();

      expect(find.byType(StudyPickerScreen), findsNothing,
          reason: 'navigating to a screen whose only content is "log in '
              'somewhere else" is a dead end that has to be backed out of '
              '(004 research D7)');
      final message = tester
          .widget<Text>(find.byKey(const Key('studies-need-account')))
          .data!;
      expect(message, contains('connected Lichess account'));
      expect(message, contains('home screen'),
          reason: 'FR-017: say what is needed *and* where it lives');
      expectNoLoginOffered('being told an account is needed');
      expect(api.calls, isEmpty,
          reason: 'nothing to ask Lichess when there is nobody to ask about');
    });

    testWidgets('expired: says the login ran out, and goes nowhere',
        (tester) async {
      await expireCredential();
      await pumpImport(tester);

      await tester.tap(find.byKey(const Key('pick-my-studies')));
      await tester.pumpAndSettle();

      expect(find.byType(StudyPickerScreen), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studies-need-account')))
            .data!,
        contains('expired'),
        reason: 'an expired login and no login at all are different problems '
            'with different fixes',
      );
    });

    testWidgets('connected: opens the picker with no extra step',
        (tester) async {
      await connect();
      await pumpImport(tester);

      await tester.tap(find.byKey(const Key('pick-my-studies')));
      await tester.pumpAndSettle();

      expect(find.byType(StudyPickerScreen), findsOneWidget);
      expect(find.byKey(const Key('studies-need-account')), findsNothing);
      expect(api.calls, contains('listStudies'),
          reason: 'the studies are fetched when the picker opens, and at no '
              'other time (FR-019)');
      expectNoLoginOffered('picking from my studies');
    });
  });

  group('the picker reached in a state it does not expect', () {
    testWidgets('explains, and still offers no login', (tester) async {
      // Defensive: the import screen checks before navigating, so this should
      // be unreachable. A screen that assumes it can only be entered in one
      // state eventually gets entered in another — a login can expire between
      // opening the picker and reading it.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            credentialStoreProvider.overrideWithValue(credentials),
            lichessAuthProvider.overrideWithValue(auth),
            lichessApiProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: StudyPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('study-picker-message')))
            .data!,
        contains('home screen'),
      );
      expectNoLoginOffered('inside the picker with no account');
    });
  });

  group('a public study still needs nothing (FR-016)', () {
    testWidgets('pasting an address imports with no account', (tester) async {
      await pumpImport(tester);

      await tester.enterText(find.byKey(const Key('study-link')),
          'https://lichess.org/study/9LjyYZ9N');
      await tester.tap(find.byKey(const Key('import-study-link')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('exportStudy'));
      expect(find.byKey(const Key('import-report')), findsOneWidget);
      expectNoLoginOffered('importing a public study');
    });
  });
}

/// A Lichess client that answers without a network.
class _StubApi implements LichessApi {
  final List<String> calls = [];

  @override
  Future<String> username() async {
    calls.add('username');
    return 'roberto';
  }

  @override
  Future<List<StudySummary>> listStudies(String username) async {
    calls.add('listStudies');
    return [
      StudySummary(
        id: 'abcd1234',
        name: 'Endgames',
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    ];
  }

  @override
  Future<String> exportStudy(String studyId) async {
    calls.add('exportStudy');
    return '''
[Event "A public study"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4 e5 2. Nf3 *
''';
  }

  @override
  Future<void> revokeToken() async => calls.add('revokeToken');
}

/// A login that fails the test if import reaches for it.
class _ExplodingAuth implements LichessAuth {
  int logIns = 0;

  @override
  Future<LichessConnection> logIn() async {
    logIns++;
    fail('import started a login — that is the thing feature 004 removed');
  }

  @override
  Future<void> logOut() async =>
      fail('import disconnected an account, which it has no business doing');
}
