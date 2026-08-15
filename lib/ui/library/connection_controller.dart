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
library;

// Named parameters cannot be private, so the initializing formals this lint
// prefers are not available for the private fields below.
// ignore_for_file: prefer_initializing_formals

import 'package:chess_trainer/data/import_service.dart';
import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:chess_trainer/data/lichess/lichess_gateway.dart';
import 'package:chess_trainer/data/lichess/study_link.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/collection.dart';
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

/// Who is connected, or null.
final lichessConnectionProvider =
    FutureProvider<LichessConnection?>((ref) async {
  // Reads storage only. An expired credential is deleted here rather than
  // reported, so the app never holds a token it knows is dead (D5).
  return ref.watch(lichessAuthProvider).current();
});

/// The account's studies, fetched when the player opens the picker.
///
/// A `FutureProvider.family` keyed on nothing would fetch on first watch; this
/// is watched only by the study picker screen, which the player has to open.
final myStudiesProvider = FutureProvider<List<StudySummary>>((ref) async {
  final api = ref.watch(lichessApiProvider);
  final connection = await ref.watch(lichessConnectionProvider.future);
  if (connection == null) throw NotLoggedInError();
  return api.listStudies(connection.username);
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
      _ref.invalidate(lichessConnectionProvider);
      return connection;
    } on LoginCancelledError {
      return null;
    }
  }

  /// Forgets the login. Imported collections are untouched: they are local
  /// content now, not a view onto the account (FR-022).
  Future<void> logOut() async {
    await _ref.read(lichessAuthProvider).logOut();
    _ref.invalidate(lichessConnectionProvider);
    _ref.invalidate(myStudiesProvider);
  }
}

/// Turns a network failure into something a player can act on (SC-011).
///
/// Every branch names what happened *and* what to do. A message that only
/// names the fault leaves the player with an app that stopped for reasons of
/// its own.
String messageForNetworkError(Object error) => switch (error) {
      NoConnectionError() =>
        'Importing from Lichess needs a connection. Everything already '
            'imported still works offline.',
      NotLoggedInError() =>
        'That study is not public, so it needs you to log in to Lichess.',
      LoginExpiredError() =>
        'Your Lichess login has expired. Log in again to import from it.',
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
