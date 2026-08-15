/// The fact that the player has logged in to Lichess.
///
/// **The token is deliberately not here.** It lives in the data layer's Lichess
/// directory, behind the credential store, so that no domain or UI value can
/// hold it, log it, or put it in an error message (FR-021). What the rest of
/// the app needs to know is "connected as whom, until when", and that is all
/// this carries.
library;

import 'package:meta/meta.dart';

@immutable
class LichessConnection {
  const LichessConnection({required this.username, required this.expiresAt});

  final String username;

  /// Absolute, computed from `expires_in` at login.
  ///
  /// Lichess tokens last about a year and cannot be refreshed, so this is not a
  /// hint about when to renew — it is when the player will be asked to log in
  /// again (003 research D5).
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LichessConnection &&
          username == other.username &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(username, expiresAt);

  @override
  String toString() => 'LichessConnection($username)';
}
