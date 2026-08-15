/// Answers "is an account connected?" without touching the network.
///
/// **This class exists to keep a test absolute** (004 research D1).
///
/// The question used to be asked through `LichessAuth.current()`. That object
/// also opens browsers and posts to `/api/token`, and
/// `test/ui/no_network_during_training_test.dart` drives the whole training
/// flow against a fake whose *every* method fails the test on contact — the
/// behavioural guarantee that replaced the one feature 003 gave up when the
/// manifest started declaring `INTERNET`. Putting the account on the home
/// screen means reading it at startup, and reading it through `LichessAuth`
/// would have forced that fake to start answering one method, turning "nothing
/// on the login object is touched at startup" into "nothing except this one,
/// judged by hand, forever".
///
/// So the read moved here instead. This class takes a [CredentialStore] and a
/// clock, holds no HTTP client and accepts none, and therefore *cannot* reach
/// the network — which is a stronger thing to be able to say than that it does
/// not.
library;

// Named parameters cannot be private, so the initializing formals this lint
// prefers are not available for the private fields below.
// ignore_for_file: prefer_initializing_formals

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/domain/lichess/account.dart';

class LichessAccountReader {
  LichessAccountReader({
    required CredentialStore credentials,
    DateTime Function()? now,
  })  : _credentials = credentials,
        _now = now ?? DateTime.now;

  final CredentialStore _credentials;
  final DateTime Function() _now;

  /// Reads local storage, and nothing else.
  ///
  /// Deliberately never calls [CredentialStore.readToken]: knowing whether an
  /// account is connected does not require the secret, and the fewer places
  /// that read it the better.
  Future<LichessAccount> read() async {
    final connection = await _credentials.readConnection();
    if (connection == null) return const AccountDisconnected();

    if (connection.isExpiredAt(_now().toUtc())) {
      // The token goes now, not when something next tries to use it. What is
      // left is a name and a date, which is what the home screen needs to say
      // "your login expired" rather than "log in" (research D3).
      await _credentials.expireToken();
      return AccountExpired(connection);
    }

    return AccountConnected(connection);
  }
}
