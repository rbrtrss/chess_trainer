/// Logging in to Lichess: OAuth 2.0 Authorization Code with PKCE.
///
/// Every endpoint and rule here was verified against the Lichess OpenAPI spec
/// on 2026-08-14 (research, "Verified Lichess API facts"):
///
/// - authorization at `GET https://lichess.org/oauth`
/// - token exchange at `POST https://lichess.org/api/token`, form-encoded
/// - `S256` is the only code challenge method accepted
/// - public clients only: there is no client secret, and none is sent
/// - tokens last about a year (`expires_in: 31536000`)
/// - **refresh tokens are not supported**
///
/// **There is deliberately no `refresh()` here, and there must never be one.**
/// A method that cannot work is worse than a missing one, because it invites a
/// caller. Expiry is an invitation to log in again (FR-017, research D5).
library;

// Named parameters cannot be private, so the initializing formals this lint
// prefers are not available for the private fields below — and the fields are
// private precisely so nothing outside this file can reach the token.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

/// The app's public client id.
///
/// Lichess registers nothing in advance and accepts any identifier; the
/// convention is a URL identifying the project. It is public by design and the
/// constitution explicitly permits committing it — unlike a token, it proves
/// nothing and grants nothing.
///
/// It is not inert, though: **this is the string Lichess shows the player on
/// the authorization page**, above the list of permissions they are about to
/// grant. It should therefore be somewhere they can go to see what they are
/// granting them to, which is why it is this repository rather than an
/// arbitrary identifier.
const String lichessClientId = 'https://github.com/rbrtrss/chess_trainer';

/// Where Lichess sends the player back to.
///
/// Must match the intent filter in `android/app/src/main/AndroidManifest.xml`
/// exactly. If the two disagree, login opens Lichess and then hangs on the
/// return trip with no error — the first thing to check when a login never
/// completes.
const String lichessRedirectUri = 'org.chesstrainer://oauth/callback';
const String lichessCallbackScheme = 'org.chesstrainer';

/// The only scope this app asks for.
///
/// Private studies need it; nothing else here does. Asking for more would be
/// asking the player to grant powers the app has no use for.
const String lichessScope = 'study:read';

/// Opens the authorization page and returns the redirect URL it comes back to.
///
/// Injectable so tests exercise the flow without a browser.
typedef AuthorizeCallback = Future<String> Function({
  required String url,
  required String callbackUrlScheme,
});

abstract interface class LichessAuth {
  /// Runs the whole flow and stores the credential.
  ///
  /// Throws [LoginCancelledError] when the player backs out — a normal outcome,
  /// not a failure to report as one.
  Future<LichessConnection> logIn();

  /// Revokes server-side, then deletes the local credential (FR-022).
  Future<void> logOut();

  // There is no `current()` here, and there must never be one again.
  //
  // It used to answer "is anyone connected?", which is a question about local
  // storage that has no business on the object that opens browsers and posts
  // to `/api/token`. `LichessAccountReader` answers it now (004 research D1).
  // The difference matters to exactly one test:
  // `no_network_during_training_test.dart` runs the whole training flow against
  // a fake whose every method fails on contact, and that test is what replaced
  // the offline guarantee feature 003 gave up. While every method here is a
  // network call, that fake needs no exceptions.
}

class PkceLichessAuth implements LichessAuth {
  PkceLichessAuth({
    required CredentialStore credentials,
    required LichessApi api,
    required http.Client client,
    AuthorizeCallback? authorize,
    Random? random,
    DateTime Function()? now,
    this.origin = lichessOrigin,
  })  : _credentials = credentials,
        _api = api,
        _client = client,
        _authorize = authorize ?? _openBrowser,
        _random = random ?? Random.secure(),
        _now = now ?? DateTime.now;

  final CredentialStore _credentials;
  final LichessApi _api;
  final http.Client _client;
  final AuthorizeCallback _authorize;
  final Random _random;
  final DateTime Function() _now;
  final String origin;

  static Future<String> _openBrowser({
    required String url,
    required String callbackUrlScheme,
  }) =>
      FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: callbackUrlScheme,
      );

  @override
  Future<LichessConnection> logIn() async {
    final verifier = _randomString(64);
    final state = _randomString(32);
    final challenge = codeChallengeFor(verifier);

    final authorizeUrl = Uri.parse('$origin/oauth').replace(queryParameters: {
      'response_type': 'code',
      'client_id': lichessClientId,
      'redirect_uri': lichessRedirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'scope': lichessScope,
      'state': state,
    }).toString();

    final String redirected;
    try {
      redirected = await _authorize(
        url: authorizeUrl,
        callbackUrlScheme: lichessCallbackScheme,
      );
    } on Object {
      // The player dismissed the page, or the platform cancelled it. Either
      // way nothing was granted and nothing is stored.
      throw LoginCancelledError();
    }

    final returned = Uri.parse(redirected);
    if (returned.queryParameters['error'] != null) {
      throw LoginCancelledError();
    }

    // Cross-site request forgery defence: the state that comes back must be the
    // state that went out. If it is not, this redirect is not ours.
    if (returned.queryParameters['state'] != state) {
      throw LichessUnavailableError('the authorization response did not match '
          'the request');
    }

    final code = returned.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw LichessUnavailableError('the authorization response carried no '
          'code');
    }

    return _exchange(code, verifier);
  }

  Future<LichessConnection> _exchange(String code, String verifier) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$origin/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'code_verifier': verifier,
          'redirect_uri': lichessRedirectUri,
          'client_id': lichessClientId,
          // No client_secret. Lichess does not support one, and sending an
          // empty value would be worse than sending nothing.
        },
      );
    } on Object catch (error) {
      throw NoConnectionError(error);
    }

    if (response.statusCode == 429) throw RateLimitedError();
    if (response.statusCode != 200) {
      throw LichessUnavailableError(
          'the token exchange failed (${response.statusCode})');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw LichessUnavailableError('the token response was not readable');
    }
    if (decoded is! Map ||
        decoded['access_token'] is! String ||
        decoded['expires_in'] is! int) {
      throw LichessUnavailableError('the token response was not readable');
    }

    final token = decoded['access_token'] as String;
    // Absolute, not a duration: a duration would have to be re-based every time
    // it was read, and getting that wrong means a token treated as live long
    // after it is dead (D5).
    final expiresAt =
        _now().toUtc().add(Duration(seconds: decoded['expires_in'] as int));

    // Written before the username lookup, because the lookup needs it.
    await _credentials.write(
      token: token,
      expiresAt: expiresAt,
      username: '',
    );

    final String username;
    try {
      username = await _api.username();
    } on Object {
      // A token that works for nothing is worse than no token: clear it rather
      // than leave the app "connected" as nobody.
      await _credentials.clear();
      rethrow;
    }

    await _credentials.write(
      token: token,
      expiresAt: expiresAt,
      username: username,
    );

    return LichessConnection(username: username, expiresAt: expiresAt);
  }

  @override
  Future<void> logOut() async {
    // Best effort server-side, unconditional locally: a player who asked to
    // disconnect must end up disconnected on their own device whatever the
    // network did (FR-022).
    try {
      await _api.revokeToken();
    } on Object {
      // Ignored on purpose, as above.
    }
    await _credentials.clear();
  }

  /// 43–128 unreserved characters, as PKCE requires.
  String _randomString(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
      length,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }
}

/// `base64url(sha256(verifier))`, unpadded — the S256 challenge.
///
/// Top-level so it can be tested directly against the PKCE specification's own
/// worked example.
String codeChallengeFor(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
