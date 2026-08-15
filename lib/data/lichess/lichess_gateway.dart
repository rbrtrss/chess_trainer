/// Everything Lichess, assembled.
///
/// Exists so that no file outside this directory ever names an HTTP client —
/// not even the provider that builds these. `test/domain/layering_test.dart`
/// enforces that, and without this seam the provider file would have to import
/// `package:http` and the rule would have to be weakened to allow it.
library;

import 'package:chess_trainer/data/lichess/credential_store.dart';
import 'package:chess_trainer/data/lichess/lichess_api.dart';
import 'package:chess_trainer/data/lichess/lichess_auth.dart';
import 'package:http/http.dart' as http;

class LichessGateway {
  LichessGateway({required CredentialStore credentials})
      : this._(credentials, http.Client());

  LichessGateway._(CredentialStore credentials, http.Client client)
      : _client = client,
        api = HttpLichessApi(
          client: client,
          readToken: credentials.readToken,
          onUnauthorized: credentials.clear,
        ) {
    auth = PkceLichessAuth(
      credentials: credentials,
      api: api,
      client: _client,
    );
  }

  final http.Client _client;

  final LichessApi api;

  late final LichessAuth auth;

  /// Closed with the app.
  void close() => _client.close();
}
