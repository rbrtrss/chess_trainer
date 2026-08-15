/// Where the Lichess access token lives, and the only thing that can read it.
///
/// The constitution requires tokens in `flutter_secure_storage`; that part is
/// not a choice. What is a choice, and is recorded in research D4, is that the
/// Android manifest sets `allowBackup="false"` — without it the plugin's data
/// is ordinary app storage as far as Auto Backup is concerned, and a token can
/// leave the device inside a Google backup, which is exactly the movement
/// FR-021 forbids.
///
/// This is the first secret the app has ever held. Every previous feature could
/// not leak a credential because there was none.
library;

import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reads and writes the credential.
abstract interface class CredentialStore {
  /// The access token, or null when there is none.
  ///
  /// **Nothing outside `lib/data/lichess/` may call this.** The token is not on
  /// [LichessConnection] for the same reason.
  Future<String?> readToken();

  /// The connection, or null when there is none.
  Future<LichessConnection?> readConnection();

  Future<void> write({
    required String token,
    required DateTime expiresAt,
    required String username,
  });

  Future<void> clear();

  /// Deletes the token and keeps the username and expiry (004 research D3).
  ///
  /// This is what expiry does, and it is not the same as [clear]. Feature 003's
  /// rule was that the app never holds a token it knows is dead, and it still
  /// holds: after this, [readToken] returns null, so no request that is certain
  /// to fail can be made. What survives is a name and a date — neither is a
  /// secret, neither grants anything, and together they are what lets the app
  /// say *whose* login ran out instead of pretending nobody ever logged in.
  Future<void> expireToken();
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'lichess_access_token';
  static const String _expiryKey = 'lichess_token_expires_at';
  static const String _usernameKey = 'lichess_username';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<LichessConnection?> readConnection() async {
    final username = await _storage.read(key: _usernameKey);
    final expiry = await _storage.read(key: _expiryKey);
    if (username == null || expiry == null) return null;

    final expiresAt = DateTime.tryParse(expiry);
    if (expiresAt == null) {
      // A credential whose expiry cannot be read is not a credential: nothing
      // can decide whether it is live. Leaving it would orphan a usable token
      // behind an account the app reports as disconnected, so it goes.
      await clear();
      return null;
    }

    return LichessConnection(username: username, expiresAt: expiresAt);
  }

  @override
  Future<void> write({
    required String token,
    required DateTime expiresAt,
    required String username,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(
        key: _expiryKey, value: expiresAt.toUtc().toIso8601String());
    await _storage.write(key: _usernameKey, value: username);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
    await _storage.delete(key: _usernameKey);
  }

  @override
  Future<void> expireToken() => _storage.delete(key: _tokenKey);
}

/// A credential store in memory, for tests and for the widget tests that must
/// never touch a platform channel.
class InMemoryCredentialStore implements CredentialStore {
  String? _token;
  LichessConnection? _connection;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<LichessConnection?> readConnection() async => _connection;

  @override
  Future<void> write({
    required String token,
    required DateTime expiresAt,
    required String username,
  }) async {
    _token = token;
    _connection =
        LichessConnection(username: username, expiresAt: expiresAt.toUtc());
  }

  @override
  Future<void> clear() async {
    _token = null;
    _connection = null;
  }

  @override
  Future<void> expireToken() async {
    _token = null;
  }
}
