import 'dart:convert';

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Every request this app makes, against a fake client.
///
/// **No test in this repository makes a real network request.** Covers
/// lichess-api invariants 6, 7, 8 and 10.
void main() {
  late _FakeClient client;
  late InMemoryCredentialStore credentials;
  late HttpLichessApi api;
  var unauthorizedCalls = 0;

  setUp(() {
    client = _FakeClient();
    credentials = InMemoryCredentialStore();
    unauthorizedCalls = 0;
    api = HttpLichessApi(
      client: client,
      readToken: credentials.readToken,
      onUnauthorized: () async {
        unauthorizedCalls++;
        await credentials.clear();
      },
    );
  });

  Future<void> logIn() => credentials.write(
        token: 'lio_TESTTOKEN',
        expiresAt: DateTime.utc(2027),
        username: 'roberto',
      );

  group('exporting a study (invariant 8, D7)', () {
    test('asks for comments and variations, and not for clocks', () async {
      await logIn();
      client.respond(200, '[Event "x"]\n\n1. e4');

      await api.exportStudy('9LjyYZ9N');

      final url = client.requests.single.url.toString();
      expect(url, contains('/api/study/9LjyYZ9N.pgn'));
      // The variations *are* the solution and the comments *are* the notes; a
      // study exported without them is worthless here.
      expect(url, contains('comments=true'));
      expect(url, contains('variations=true'));
      // Clock annotations would land in the same comment text and be shown at
      // review as if they were the author's notes.
      expect(url, contains('clocks=false'));
    });

    test('sends the token as a bearer when there is one', () async {
      await logIn();
      client.respond(200, 'pgn');

      await api.exportStudy('9LjyYZ9N');

      expect(client.requests.single.headers['Authorization'],
          'Bearer lio_TESTTOKEN');
    });

    test('works with no token at all, for a public study (FR-011)', () async {
      client.respond(200, 'pgn');

      await api.exportStudy('9LjyYZ9N');

      expect(client.requests.single.headers.containsKey('Authorization'),
          isFalse);
    });

    test('an id of the wrong shape never reaches the network', () async {
      await expectLater(
        api.exportStudy('too-short'),
        throwsA(isA<NotAStudyLinkError>()),
      );
      expect(client.requests, isEmpty);
    });
  });

  group('failures are mapped to something a player can act on', () {
    test('401 clears the credential and asks for a new login (FR-017)',
        () async {
      await logIn();
      client.respond(401, '');

      await expectLater(
        api.exportStudy('9LjyYZ9N'),
        throwsA(isA<LoginExpiredError>()),
      );

      expect(unauthorizedCalls, 1);
      expect(await credentials.readToken(), isNull,
          reason: 'the app must not keep a token it knows is dead');
      // Exactly one request: no renewal was attempted, because none can work.
      expect(client.requests, hasLength(1));
    });

    test('429 surfaces rate limiting and issues one request only (invariant 6)',
        () async {
      await logIn();
      client.respond(429, '');

      await expectLater(
        api.exportStudy('9LjyYZ9N'),
        throwsA(isA<RateLimitedError>()),
      );

      expect(client.requests, hasLength(1),
          reason: 'an automatic backoff loop turns a one-minute wait into an '
              'app that appears to hang (FR-018)');
    });

    test('404 and 403 read as "not available to this account"', () async {
      await logIn();
      client.respond(404, '');
      await expectLater(api.exportStudy('9LjyYZ9N'),
          throwsA(isA<StudyNotAvailableError>()));

      client.respond(403, '');
      await expectLater(api.exportStudy('9LjyYZ9N'),
          throwsA(isA<StudyNotAvailableError>()));
    });

    test('a server error is reported as Lichess having a problem', () async {
      await logIn();
      client.respond(503, '');

      await expectLater(api.exportStudy('9LjyYZ9N'),
          throwsA(isA<LichessUnavailableError>()));
    });

    test('a transport failure reads as no connection', () async {
      await logIn();
      client.fail(const _Offline());

      await expectLater(
          api.exportStudy('9LjyYZ9N'), throwsA(isA<NoConnectionError>()));
    });

    test('an unauthenticated private request is refused before it is sent',
        () async {
      await expectLater(api.username(), throwsA(isA<NotLoggedInError>()));
      expect(client.requests, isEmpty);
    });
  });

  group('listing studies (D9)', () {
    test('parses NDJSON, one study per line', () async {
      await logIn();
      client.respond(
        200,
        '${jsonEncode({
              'id': 'WTvnkWAL',
              'name': 'Guess the move',
              'createdAt': 1463756350225,
              'updatedAt': 1469965025205,
            })}\n'
        '${jsonEncode({
              'id': '55NSdxBQ',
              'name': 'Puzzles',
              'createdAt': 1604302196377,
              'updatedAt': 1729131860114,
            })}\n',
      );

      final studies = await api.listStudies('roberto');

      expect(studies.map((study) => study.name),
          ['Guess the move', 'Puzzles']);
      expect(studies.first.id, 'WTvnkWAL');
      expect(studies.first.updatedAt.year, 2016);
    });

    test('a malformed line is skipped, not fatal', () async {
      await logIn();
      client.respond(
        200,
        '${jsonEncode({
              'id': 'WTvnkWAL',
              'name': 'Fine',
              'createdAt': 1,
              'updatedAt': 2,
            })}\n'
        'this line is not json\n'
        '${jsonEncode({
              'id': '55NSdxBQ',
              'name': 'Also fine',
              'createdAt': 1,
              'updatedAt': 2,
            })}\n',
      );

      final studies = await api.listStudies('roberto');

      expect(studies.map((study) => study.name), ['Fine', 'Also fine'],
          reason: 'one bad row must not cost the player their whole list');
    });
  });

  group('requests are serialised (invariant 7, D6)', () {
    test('two calls do not produce two in-flight requests', () async {
      await logIn();
      client.respondSlowly(200, 'pgn');

      final first = api.exportStudy('9LjyYZ9N');
      final second = api.exportStudy('55NSdxBQ');

      // Lichess asks for one request at a time; a client that ignores that is
      // how an app gets its rate limit tightened.
      expect(client.inFlight, lessThanOrEqualTo(1));

      await first;
      await second;
      expect(client.requests, hasLength(2));
    });

    test('a failure does not deadlock the requests behind it', () async {
      await logIn();
      client.respond(500, '');
      await expectLater(
          api.exportStudy('9LjyYZ9N'), throwsA(isA<LichessUnavailableError>()));

      client.respond(200, 'pgn');
      expect(await api.exportStudy('55NSdxBQ'), 'pgn');
    });
  });

  group('logging out (invariant 10, FR-022)', () {
    test('revocation is attempted with the token', () async {
      await logIn();
      client.respond(204, '');

      await api.revokeToken();

      expect(client.requests.single.method, 'DELETE');
      expect(client.requests.single.headers['Authorization'],
          'Bearer lio_TESTTOKEN');
    });

    test('a failed revocation is not fatal', () async {
      await logIn();
      client.fail(const _Offline());

      await api.revokeToken();
      // No throw: the caller deletes the local credential regardless, because a
      // player who asked to disconnect must end up disconnected on their own
      // device whatever the network did.
    });

    test('with no token, nothing is sent', () async {
      await api.revokeToken();
      expect(client.requests, isEmpty);
    });
  });
}

class _Offline implements Exception {
  const _Offline();
}

/// An `http.Client` that answers from a script and records what it was asked.
class _FakeClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  int inFlight = 0;

  int _status = 200;
  String _body = '';
  Object? _failure;
  bool _slow = false;

  void respond(int status, String body) {
    _status = status;
    _body = body;
    _failure = null;
    _slow = false;
  }

  void respondSlowly(int status, String body) {
    respond(status, body);
    _slow = true;
  }

  void fail(Object error) => _failure = error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (_failure != null) throw _failure!;

    inFlight++;
    try {
      if (_slow) await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.StreamedResponse(
        Stream.value(utf8.encode(_body)),
        _status,
        request: request,
      );
    } finally {
      inFlight--;
    }
  }
}
