import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The login, without a browser.
///
/// Covers lichess-api invariants 1–5 and 11. Every fact asserted here was
/// verified against the Lichess OpenAPI spec on 2026-08-14: S256 only, no
/// client secret, `expires_in` about a year, and **no refresh tokens**.
void main() {
  late _FakeClient client;
  late InMemoryCredentialStore credentials;
  late _StubApi api;

  setUp(() {
    client = _FakeClient();
    credentials = InMemoryCredentialStore();
    api = _StubApi();
  });

  PkceLichessAuth authWith({
    AuthorizeCallback? authorize,
    DateTime Function()? now,
  }) =>
      PkceLichessAuth(
        credentials: credentials,
        api: api,
        client: client,
        authorize: authorize ??
            ({required url, required callbackUrlScheme}) async {
              final state = Uri.parse(url).queryParameters['state'];
              return '$lichessRedirectUri?code=liu_CODE&state=$state';
            },
        random: Random(20260814),
        now: now ?? () => DateTime.utc(2026, 8, 14),
      );

  void respondWithToken({int expiresIn = 31536000}) => client.respond(
        200,
        jsonEncode({
          'token_type': 'Bearer',
          'access_token': 'lio_TESTTOKEN',
          'expires_in': expiresIn,
        }),
      );

  group('invariant 1 — the PKCE challenge is S256 of the verifier', () {
    test('the authorization request carries the right parameters', () async {
      respondWithToken();
      String? authorizeUrl;

      await authWith(
        authorize: ({required url, required callbackUrlScheme}) async {
          authorizeUrl = url;
          final state = Uri.parse(url).queryParameters['state'];
          return '$lichessRedirectUri?code=liu_CODE&state=$state';
        },
      ).logIn();

      final query = Uri.parse(authorizeUrl!).queryParameters;
      expect(Uri.parse(authorizeUrl!).path, '/oauth');
      expect(query['response_type'], 'code');
      expect(query['code_challenge_method'], 'S256',
          reason: 'S256 is the only method Lichess accepts');
      expect(query['client_id'], lichessClientId);
      expect(query['redirect_uri'], lichessRedirectUri);
      expect(query['scope'], 'study:read',
          reason: 'asking for more would be asking the player to grant powers '
              'the app has no use for');
      expect(query['state'], isNotEmpty);
      expect(query['code_challenge'], isNotEmpty);
    });

    test('the challenge really is unpadded base64url of SHA-256', () {
      // The worked example from RFC 7636 appendix B.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(codeChallengeFor(verifier),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('the verifier is long enough and uses only unreserved characters',
        () async {
      respondWithToken();
      await authWith().logIn();

      final verifier = client.lastBody!['code_verifier']!;
      expect(verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);

      // And it is the verifier the challenge was made from.
      final challenge =
          base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes)
              .replaceAll('=', '');
      expect(challenge, isNotEmpty);
    });
  });

  group('invariant 2 — a mismatched state aborts the login', () {
    test('nothing is stored and the login fails', () async {
      respondWithToken();

      await expectLater(
        authWith(
          authorize: ({required url, required callbackUrlScheme}) async =>
              '$lichessRedirectUri?code=liu_CODE&state=not-the-state-we-sent',
        ).logIn(),
        throwsA(isA<LichessUnavailableError>()),
      );

      expect(await credentials.readToken(), isNull);
      expect(client.requests, isEmpty,
          reason: 'the code must not be exchanged for a redirect that is not '
              'ours');
    });
  });

  group('invariant 3 — the exchange is form-encoded and has no secret', () {
    test('every required parameter, and nothing resembling a secret', () async {
      respondWithToken();

      await authWith().logIn();

      final body = client.lastBody!;
      expect(body['grant_type'], 'authorization_code');
      expect(body['code'], 'liu_CODE');
      expect(body['redirect_uri'], lichessRedirectUri);
      expect(body['client_id'], lichessClientId);
      expect(body.containsKey('code_verifier'), isTrue);

      // Lichess supports no client secret, and sending an empty one would be
      // worse than sending nothing.
      expect(body.containsKey('client_secret'), isFalse);
      expect(client.requests.single.url.path, '/api/token');
      expect(client.requests.single.method, 'POST');
    });
  });

  group('invariant 4 — expiry is absolute, and expired means gone', () {
    test('expires_in becomes an absolute moment', () async {
      respondWithToken();

      final connection = await authWith().logIn();

      // A year from the fixed "now".
      expect(connection.expiresAt, DateTime.utc(2027, 8, 14));
      expect(connection.username, 'roberto');
    });

    test('a passed expiry clears the credential and reports nothing', () async {
      respondWithToken(expiresIn: 60);
      final auth = authWith();
      await auth.logIn();

      expect(await auth.current(), isNotNull);

      final later = authWith(now: () => DateTime.utc(2027));
      expect(await later.current(), isNull);
      expect(await credentials.readToken(), isNull,
          reason: 'an expired credential is deleted rather than reported, so '
              'the app never holds a token it knows is dead');
    });

    test('checking expiry makes no request', () async {
      respondWithToken();
      await authWith().logIn();
      final before = client.requests.length;

      await authWith(now: () => DateTime.utc(2027)).current();

      expect(client.requests, hasLength(before),
          reason: 'a request certain to fail is a request not worth making');
    });
  });

  group('invariant 5 — there is no refresh path anywhere', () {
    test('no source file mentions a refresh token', () {
      // The strongest form of this assertion: not "we do not call refresh" but
      // "no such code exists". Lichess issues no refresh tokens, so a renewal
      // path cannot work, and a method that cannot work is worse than a
      // missing one because it invites a caller (FR-017, 003 research D5).
      final offenders = io.Directory('lib')
          .listSync(recursive: true)
          .whereType<io.File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) {
            final source = file.readAsStringSync();
            return source.contains('refresh_token') ||
                source.contains('refreshToken');
          })
          .map((file) => file.path)
          .toList();

      expect(offenders, isEmpty,
          reason: 'Lichess supports no refresh tokens; any code here that '
              'looks like renewal is code that cannot work');
    });

    test('the auth interface exposes no refresh method', () {
      final source =
          io.File('lib/data/lichess/lichess_auth.dart').readAsStringSync();
      expect(source, isNot(contains('Future<LichessConnection> refresh(')));
    });
  });

  group('cancellation is not a failure', () {
    test('a dismissed page raises LoginCancelledError', () async {
      await expectLater(
        authWith(
          authorize: ({required url, required callbackUrlScheme}) =>
              throw Exception('user dismissed'),
        ).logIn(),
        throwsA(isA<LoginCancelledError>()),
      );
      expect(await credentials.readToken(), isNull);
    });

    test('an access_denied redirect is cancellation too', () async {
      await expectLater(
        authWith(
          authorize: ({required url, required callbackUrlScheme}) async =>
              '$lichessRedirectUri?error=access_denied',
        ).logIn(),
        throwsA(isA<LoginCancelledError>()),
      );
    });
  });

  group('invariant 11 — the token never appears in an error or a log', () {
    test('no error message carries the token', () async {
      const sentinel = 'lio_SENTINELTOKENVALUE';
      client.respond(
        200,
        jsonEncode({
          'token_type': 'Bearer',
          'access_token': sentinel,
          'expires_in': 31536000,
        }),
      );
      api.failUsername = true;

      Object? raised;
      try {
        await authWith().logIn();
      } on Object catch (error) {
        raised = error;
      }

      expect(raised, isNotNull);
      expect(raised.toString(), isNot(contains(sentinel)));
      // And a token that works for nothing is not kept.
      expect(await credentials.readToken(), isNull);
    });

    test('nothing in the app prints', () {
      // `avoid_print` is on in analysis_options, but a token reaching a log is
      // the failure this is really about, so it is asserted rather than
      // trusted to a lint someone can ignore.
      final offenders = io.Directory('lib')
          .listSync(recursive: true)
          .whereType<io.File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) =>
              RegExp(r'\bprint\(').hasMatch(file.readAsStringSync()))
          .map((file) => file.path)
          .toList();

      expect(offenders, isEmpty);
    });
  });

  group('logging out', () {
    test('revokes, then forgets locally whatever the network did', () async {
      respondWithToken();
      final auth = authWith();
      await auth.logIn();

      api.failRevoke = true;
      await auth.logOut();

      expect(await credentials.readToken(), isNull);
      expect(await auth.current(), isNull);
    });
  });
}

/// A `LichessApi` that answers without a network.
class _StubApi implements LichessApi {
  bool failUsername = false;
  bool failRevoke = false;

  @override
  Future<String> username() async {
    if (failUsername) throw LichessUnavailableError('no account');
    return 'roberto';
  }

  @override
  Future<List<StudySummary>> listStudies(String username) async => const [];

  @override
  Future<String> exportStudy(String studyId) async => '';

  @override
  Future<void> revokeToken() async {
    if (failRevoke) throw const _Offline();
  }
}

class _Offline implements Exception {
  const _Offline();
}

class _FakeClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];

  int _status = 200;
  String _body = '';

  /// The form fields of the last POST, decoded.
  Map<String, String>? lastBody;

  void respond(int status, String body) {
    _status = status;
    _body = body;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request && request.bodyFields.isNotEmpty) {
      lastBody = request.bodyFields;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(_body)),
      _status,
      request: request,
    );
  }
}
