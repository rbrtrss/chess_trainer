/// The app's entire network surface: four requests.
///
/// See `specs/003-position-import/contracts/lichess-api.md`. Every endpoint and
/// parameter here was verified against the Lichess OpenAPI spec on 2026-08-14
/// (research, "Verified Lichess API facts") rather than recalled.
///
/// **This directory is the only place in `lib/` allowed to mention an HTTP
/// client**, enforced in both directions by `test/domain/layering_test.dart`.
library;

import 'dart:convert';

import 'package:chess_trainer/domain/errors.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Where Lichess lives. Overridable only so tests can be explicit about it.
const String lichessOrigin = 'https://lichess.org';

/// One row of the study list.
@immutable
class StudySummary {
  const StudySummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Exactly 8 characters.
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Supplies the current access token, or null when there is none.
typedef TokenReader = Future<String?> Function();

/// Called when the server says the credential is no longer good, so the store
/// can drop it rather than keep a token the app knows is dead.
typedef TokenInvalidator = Future<void> Function();

/// Every request this app makes.
///
/// Four methods; there will not be a fifth without a specification that argues
/// for it. Every one is called only as the direct result of the player asking
/// for something (FR-015) — never from a build method, a provider initialiser,
/// an app-start path, or a timer.
abstract interface class LichessApi {
  /// The logged-in user's username, for listing their studies.
  Future<String> username();

  /// Their studies, including private and unlisted ones when authenticated.
  Future<List<StudySummary>> listStudies(String username);

  /// A whole study as PGN, chapters concatenated.
  Future<String> exportStudy(String studyId);

  /// Revokes the token server-side. Best effort.
  Future<void> revokeToken();
}

class HttpLichessApi implements LichessApi {
  HttpLichessApi({
    required http.Client client,
    required TokenReader readToken,
    required TokenInvalidator onUnauthorized,
    this.origin = lichessOrigin,
  })  // The fields are private so nothing outside this file can reach the
      // client or the token reader. Named parameters cannot be private, so an
      // initializing formal — which the lint would prefer — is not available.
      // ignore_for_file: prefer_initializing_formals
      : _client = client,
        _readToken = readToken,
        _onUnauthorized = onUnauthorized;

  final http.Client _client;
  final TokenReader _readToken;
  final TokenInvalidator _onUnauthorized;
  final String origin;

  /// Requests are serialised: Lichess asks for one at a time, and a client that
  /// ignores that is how an app gets its rate limit tightened (D6).
  Future<void> _inFlight = Future<void>.value();

  @override
  Future<String> username() async {
    final body = await _get('/api/account', authenticated: true);
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['username'] is! String) {
      throw LichessUnavailableError('the account response was not readable');
    }
    return decoded['username'] as String;
  }

  @override
  Future<List<StudySummary>> listStudies(String username) async {
    final body = await _get('/api/study/by/$username', authenticated: true);

    // NDJSON: one object per line, not an array. A malformed line is skipped
    // rather than fatal — one bad row must not cost the player their whole
    // study list.
    final studies = <StudySummary>[];
    for (final line in const LineSplitter().convert(body)) {
      if (line.trim().isEmpty) continue;
      try {
        final row = jsonDecode(line);
        if (row is! Map) continue;
        final id = row['id'];
        final name = row['name'];
        if (id is! String || name is! String) continue;
        studies.add(
          StudySummary(
            id: id,
            name: name,
            createdAt: _epoch(row['createdAt']),
            updatedAt: _epoch(row['updatedAt']),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return studies;
  }

  @override
  Future<String> exportStudy(String studyId) async {
    // Validated before a request is made, so a mistyped id costs nothing.
    // `async` so this arrives as a failed future like every other error here —
    // a method that sometimes throws synchronously and sometimes does not is a
    // trap for its callers.
    if (!RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(studyId)) {
      throw NotAStudyLinkError(studyId);
    }

    // `comments` and `variations` because the variations *are* the solution and
    // the comments *are* the author's notes — a study exported without them is
    // worthless here. `clocks=false` because clock annotations land in the same
    // comment text and would be shown at review as if they were notes (D7).
    return _get(
      '/api/study/$studyId.pgn'
      '?clocks=false&comments=true&variations=true',
      authenticated: true,
      optionalAuth: true,
      studyId: studyId,
    );
  }

  @override
  Future<void> revokeToken() async {
    final token = await _readToken();
    if (token == null) return;
    await _serialised(() async {
      try {
        await _client.delete(
          Uri.parse('$origin/api/token'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } on Object {
        // Best effort. The caller deletes the local credential regardless: a
        // player who asked to disconnect must end up disconnected on their own
        // device whatever the network did (FR-022).
      }
    });
  }

  Future<String> _get(
    String path, {
    required bool authenticated,
    bool optionalAuth = false,
    String? studyId,
  }) async {
    final token = authenticated ? await _readToken() : null;
    if (authenticated && token == null && !optionalAuth) {
      throw NotLoggedInError();
    }

    return _serialised(() async {
      final http.Response response;
      try {
        response = await _client.get(
          Uri.parse('$origin$path'),
          headers: {
            'Accept': 'application/x-ndjson, application/json, text/plain',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );
      } on Object catch (error) {
        // Offline, DNS failure, timeout: all the same thing to the player, and
        // all recoverable by trying again later.
        throw NoConnectionError(error);
      }

      switch (response.statusCode) {
        case 200:
          return response.body;
        case 401:
          // No renewal is attempted, because none can be: Lichess issues no
          // refresh tokens (FR-017, D5).
          await _onUnauthorized();
          throw LoginExpiredError();
        case 403:
        case 404:
          throw StudyNotAvailableError(studyId ?? path);
        case 429:
          // No retry loop. The player retries, which keeps the request count
          // honest and the app from appearing to hang (FR-018, D6).
          throw RateLimitedError();
        default:
          throw LichessUnavailableError(
            'Lichess answered ${response.statusCode}',
          );
      }
    });
  }

  /// Runs [action] after whatever is already in flight.
  Future<T> _serialised<T>(Future<T> Function() action) {
    final result = _inFlight.then((_) => action());
    // The chain must not break on failure, or one error would deadlock every
    // request after it.
    _inFlight = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  DateTime _epoch(Object? value) => DateTime.fromMillisecondsSinceEpoch(
    value is int ? value : 0,
    isUtc: true,
  );
}
