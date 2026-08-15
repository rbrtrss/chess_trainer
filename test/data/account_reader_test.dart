import 'package:chess_trainer/data/lichess/account_reader.dart';
import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/domain/lichess/account.dart';
import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The local read that replaced `LichessAuth.current()` (004 research D1).
///
/// Four of these assertions used to live in `lichess_auth_test.dart`, against
/// the method this class replaced. They moved rather than being dropped, and
/// gained the case they could not express there: **expired is not the same
/// answer as never logged in**.
///
/// The clock is injected throughout. Nothing here waits a year.
void main() {
  late InMemoryCredentialStore credentials;

  setUp(() => credentials = InMemoryCredentialStore());

  LichessAccountReader readerAt(DateTime now) => LichessAccountReader(
        credentials: credentials,
        now: () => now,
      );

  Future<void> storeCredential({
    String username = 'roberto',
    required DateTime expiresAt,
  }) =>
      credentials.write(
        token: 'lio_TESTTOKEN',
        expiresAt: expiresAt,
        username: username,
      );

  group('the three states', () {
    test('nothing stored reads as disconnected', () async {
      final account = await readerAt(DateTime.utc(2026, 8, 15)).read();

      expect(account, const AccountDisconnected());
    });

    test('a live credential reads as connected, and names the account',
        () async {
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));

      final account = await readerAt(DateTime.utc(2026, 8, 15)).read();

      expect(account, isA<AccountConnected>());
      expect((account as AccountConnected).username, 'roberto');
      expect(account.connection.expiresAt, DateTime.utc(2027, 8, 14));
    });

    test('a passed expiry reads as expired, and still names the account',
        () async {
      // The whole reason this type has three cases. Before 004 this was
      // indistinguishable from having never logged in, which left the player
      // with no explanation for why their imports had stopped working.
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));

      final account = await readerAt(DateTime.utc(2027, 8, 15)).read();

      expect(account, isA<AccountExpired>());
      expect((account as AccountExpired).username, 'roberto');
    });

    test('expiry is inclusive — the moment it passes, it has passed', () async {
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));

      final account = await readerAt(DateTime.utc(2027, 8, 14)).read();

      expect(account, isA<AccountExpired>());
    });
  });

  group('what expiry does to the token (research D3)', () {
    test('the token is deleted, and the name and date are kept', () async {
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));
      expect(await credentials.readToken(), isNotNull);

      await readerAt(DateTime.utc(2027, 8, 15)).read();

      expect(await credentials.readToken(), isNull,
          reason: '003 D5 still holds: the app never holds a token it knows is '
              'dead, so no request certain to fail can be made');
      expect((await credentials.readConnection())?.username, 'roberto',
          reason: 'the name is not a secret and grants nothing, and it is what '
              'lets the app say whose login ran out');
    });

    test('reading again still reports expired, not disconnected', () async {
      // The token is gone after the first read. If the state were derived from
      // the token rather than from the connection record, the second read would
      // silently downgrade to "never logged in" — which is exactly the bug this
      // feature exists to fix, arriving one launch later.
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));
      final reader = readerAt(DateTime.utc(2027, 8, 15));

      await reader.read();

      expect(await reader.read(), isA<AccountExpired>());
    });

    test('a live credential is left completely alone', () async {
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));

      await readerAt(DateTime.utc(2026, 8, 15)).read();

      expect(await credentials.readToken(), 'lio_TESTTOKEN');
    });

    test('disconnecting clears everything, and reads as disconnected',
        () async {
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));

      await credentials.clear();

      expect(await readerAt(DateTime.utc(2026, 8, 15)).read(),
          const AccountDisconnected());
      expect(await credentials.readToken(), isNull);
    });
  });

  group('the reader cannot reach the network (research D1)', () {
    test('it takes a credential store and a clock, and nothing else', () {
      // The structural half of the guarantee, stated as a compile-time fact:
      // this constructor accepts no client, no gateway and no auth object, so
      // there is nothing for a future edit to reach through. The behavioural
      // half is in `no_network_during_training_test.dart`, where the whole
      // training flow runs against fakes that fail the test on contact.
      final reader = LichessAccountReader(credentials: credentials);

      expect(reader, isNotNull);
    });

    test('it never reads the token', () async {
      // Knowing whether an account is connected does not require the secret,
      // and the fewer places that touch it, the smaller its blast radius.
      final watched = _TokenWatchingStore(credentials);
      await storeCredential(expiresAt: DateTime.utc(2027, 8, 14));

      await LichessAccountReader(
        credentials: watched,
        now: () => DateTime.utc(2026, 8, 15),
      ).read();

      expect(watched.tokenReads, 0);
    });
  });

  group('a credential that cannot be read is not a credential', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test('an unparseable expiry clears the whole credential', () async {
      // Only reachable in the real store: the in-memory one holds a parsed
      // object. A corrupt date would otherwise orphan a usable token behind an
      // account the app reports as disconnected.
      FlutterSecureStorage.setMockInitialValues({
        'lichess_access_token': 'lio_TESTTOKEN',
        'lichess_token_expires_at': 'not a date',
        'lichess_username': 'roberto',
      });
      final store = SecureCredentialStore();

      final account = await LichessAccountReader(
        credentials: store,
        now: () => DateTime.utc(2026, 8, 15),
      ).read();

      expect(account, const AccountDisconnected());
      expect(await store.readToken(), isNull,
          reason: 'a token nothing can decide the expiry of must not survive');
    });
  });
}

/// Wraps a store to count token reads.
class _TokenWatchingStore implements CredentialStore {
  _TokenWatchingStore(this._inner);

  final CredentialStore _inner;
  int tokenReads = 0;

  @override
  Future<String?> readToken() {
    tokenReads++;
    return _inner.readToken();
  }

  @override
  Future<LichessConnection?> readConnection() => _inner.readConnection();

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
