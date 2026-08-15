/// The Lichess connection, as the UI sees it.
///
/// The UI never learns that Lichess is reached over a network, or that a token
/// exists: it asks to log in, asks who is connected, and asks to disconnect.
///
/// **This file is the single exception to that**, in the same way
/// `session_controller.dart` is the only file that constructs the Drift
/// repository. Providers live in `lib/ui/` by this project's convention, so
/// something here has to name the implementation; what matters is that it is
/// exactly one file, and that no screen imports `lib/data/lichess/`.
/// `test/domain/layering_test.dart` enforces both.
///
/// **Feature 004 moved the account to the home screen and left this file where
/// it was**, under `library/`, which no longer describes what it holds. The
/// tidy move to `lib/ui/account/` was rejected because this file also holds
/// `StudyImporter`, which is genuinely an import concern: moving the whole file
/// drags the study importer into an account directory, and splitting it makes
/// *two* files that may name the network client. The layering rule currently
/// reads "exactly one", and one rule enforced by a test is worth more than one
/// path that reads better (004 research D9).
library;

// Named parameters cannot be private, so the initializing formals this lint
// prefers are not available for the private fields below.
// ignore_for_file: prefer_initializing_formals

import 'package:chess_trainer/data/import_service.dart';
import 'package:chess_trainer/data/lichess/account_reader.dart';
import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:chess_trainer/data/lichess/lichess_gateway.dart';
import 'package:chess_trainer/data/lichess/study_link.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/lichess/account.dart';
import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  return SecureCredentialStore();
});

/// Everything Lichess, built once and closed with the app.
///
/// The gateway exists so that not even this file names an HTTP client: the
/// rule is that networking lives in one directory, and a provider that had to
/// import `package:http` to build a client would be the first exception to it.
final lichessGatewayProvider = Provider<LichessGateway>((ref) {
  final gateway =
      LichessGateway(credentials: ref.watch(credentialStoreProvider));
  ref.onDispose(gateway.close);
  return gateway;
});

/// The Lichess client.
///
/// Nothing calls it except an explicit import or login (FR-015): no build
/// method, no provider initialiser, no app-start path, no timer.
final lichessApiProvider =
    Provider<LichessApi>((ref) => ref.watch(lichessGatewayProvider).api);

final lichessAuthProvider =
    Provider<LichessAuth>((ref) => ref.watch(lichessGatewayProvider).auth);

/// Whether an account is connected, who as, and whether the login has run out.
///
/// **Built from `credentialStoreProvider`, never from `lichessAuthProvider`**,
/// and that is not an implementation detail (004 research D1). This is the
/// provider the home screen watches on every launch. Routing it through the
/// object that opens browsers would force
/// `no_network_during_training_test.dart` to let one method of that object
/// through, and that test is the whole of what replaced the offline guarantee
/// feature 003 gave up. Reading local storage directly keeps the guard
/// absolute.
final lichessAccountProvider = FutureProvider<LichessAccount>((ref) async {
  return LichessAccountReader(credentials: ref.watch(credentialStoreProvider))
      .read();
});

/// The account's studies, fetched when the player opens the picker.
///
/// A `FutureProvider.family` keyed on nothing would fetch on first watch; this
/// is watched only by the study picker screen, which the player has to open.
final myStudiesProvider = FutureProvider<List<StudySummary>>((ref) async {
  final api = ref.watch(lichessApiProvider);
  final account = await ref.watch(lichessAccountProvider.future);
  // An expired login is as unable to list studies as no login at all, and the
  // message for each says something different about how to fix it.
  return switch (account) {
    AccountConnected(:final username) => api.listStudies(username),
    AccountExpired() => throw LoginExpiredError(),
    AccountDisconnected() => throw NotLoggedInError(),
  };
});

/// Log in, log out, and the messages that go with failing to.
final connectionControllerProvider =
    Provider<ConnectionController>((ref) => ConnectionController(ref));

class ConnectionController {
  ConnectionController(this._ref);

  final Ref _ref;

  /// Returns the connection, or null when the player cancelled.
  ///
  /// Cancellation is a normal outcome and is reported as nothing at all.
  Future<LichessConnection?> logIn() async {
    try {
      final connection = await _ref.read(lichessAuthProvider).logIn();
      _ref.invalidate(lichessAccountProvider);
      return connection;
    } on LoginCancelledError {
      return null;
    }
  }

  /// Forgets the login. Imported collections are untouched: they are local
  /// content now, not a view onto the account (FR-022).
  Future<void> logOut() async {
    await _ref.read(lichessAuthProvider).logOut();
    _ref.invalidate(lichessAccountProvider);
    _ref.invalidate(myStudiesProvider);
  }
}

/// Why the player's own studies cannot be listed right now (FR-017).
///
/// Not `messageForNetworkError(NotLoggedInError())`, which says "That study is
/// not public" — true when someone pasted the address of a private study, and
/// nonsense when they asked for *their own* studies and named nothing. Found on
/// a device on 2026-08-15, on a fresh install that had never connected.
const String studiesNeedAccountMessage =
    'Picking from your own studies needs a connected Lichess account. Connect '
    'one on the home screen.';

/// What to say when listing the player's own studies fails.
///
/// The my-studies context never talks about "that study", because the player
/// named none — but `NotLoggedInError` carries wording written for someone who
/// pasted a private address, and it reaches here whenever the account reads as
/// disconnected. That includes the case nobody predicted: a token revoked on
/// lichess.org, where the 401 clears the credential mid-request and the player
/// is left reading about a study they never mentioned.
///
/// Found on a device on 2026-08-15, by revoking a real token. It is the third
/// time this one message has leaked into a context it was not written for.
String messageForStudyListError(Object error) => error is NotLoggedInError
    ? studiesNeedAccountMessage
    : messageForNetworkError(error);

/// A disconnect that did not happen (FR-011).
///
/// Deliberately not `messageForNetworkError`, whose every branch is written
/// about importing — its storage branch says "could not save the import" and
/// its fallback says "That import did not work", and neither is about anything
/// the player just did. Revoking the token server-side is best-effort and
/// already ignored; what can fail here is clearing the credential locally, and
/// if that fails the player is still connected, which they need telling.
const String disconnectFailedMessage =
    'This device could not forget the login, so you are still connected. Try '
    'again.';

/// Turns a network failure into something a player can act on (SC-011).
///
/// Every branch names what happened *and* what to do. A message that only
/// names the fault leaves the player with an app that stopped for reasons of
/// its own.
String messageForNetworkError(Object error) => switch (error) {
      NoConnectionError() =>
        'Importing from Lichess needs a connection. Everything already '
            'imported still works offline.',
      // These two name an action whose place moved in feature 004. Every
      // message here names what happened *and* what to do; one that says "log
      // in" without saying where now leaves the player looking for a button
      // that is no longer in front of them (research D8).
      NotLoggedInError() =>
        'That study is not public, so it needs a connected Lichess account. '
            'Connect one on the home screen.',
      LoginExpiredError() =>
        'Your Lichess login has expired. Log in again from the home screen.',
      RateLimitedError() =>
        'Lichess is rate-limiting this app. Try again in a minute.',
      StudyNotAvailableError() =>
        'That study is not available to this account. It may have been '
            'deleted, or made private.',
      NotAStudyLinkError() =>
        'That is not a Lichess study address. It should look like '
            'lichess.org/study/abcd1234.',
      LichessUnavailableError(:final detail) =>
        'Lichess had a problem, so nothing was imported ($detail). Try again '
            'later.',
      StorageWriteError(:final operation) =>
        'This device could not save the import, so nothing was added '
            '($operation).',
      _ => 'That import did not work, so nothing was added ($error).',
    };

/// Imports a study, given whatever the player pasted or picked.
///
/// Lives here rather than in `ImportService` because fetching is the only part
/// that needs the network, and this is the seam the layering rule draws.
final studyImporterProvider = Provider<StudyImporter>((ref) {
  return StudyImporter(
    api: ref.watch(lichessApiProvider),
    imports: ref.watch(importServiceProvider),
  );
});

class StudyImporter {
  StudyImporter({
    required LichessApi api,
    required ImportService imports,
  })  : _api = api,
        _imports = imports;

  final LichessApi _api;
  final ImportService _imports;

  /// Fetches a study and runs it through the same import the file path uses.
  ///
  /// One parser, one set of rejection rules, one place where the withholding is
  /// enforced (003 research D7).
  ///
  /// [input] is whatever the player pasted: a study URL, a chapter URL, or a
  /// bare id. Anything else is refused with a message saying what kind of
  /// address was expected, rather than with a failed request.
  Stream<ImportProgress> importStudy(
    String input, {
    required String name,
  }) async* {
    final studyId = parseStudyId(input);
    if (studyId == null) {
      yield ImportFailed(messageForNetworkError(NotAStudyLinkError(input)));
      return;
    }

    yield const ImportAcquiring();

    final String pgn;
    try {
      pgn = await _api.exportStudy(studyId);
    } on Object catch (error) {
      // Nothing partial is left behind, because nothing has been written yet
      // (FR-019).
      yield ImportFailed(messageForNetworkError(error));
      return;
    }

    yield* _imports.importText(
      pgn,
      name: name,
      origin: LichessOrigin(
        studyId: studyId,
        studyName: name,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
  }
}
