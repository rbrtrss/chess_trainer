/// What the app knows, locally, about the player's Lichess account.
///
/// Feature 003 answered this question with `LichessConnection?`, and `null` was
/// doing the work of two different answers: "you have never logged in" and
/// "your login ran out". Those are different sentences — only the second one
/// explains why a study that imported last month does not import today — so
/// this type has three cases instead of two (004 research D2).
///
/// **The token is not here**, for the same reason it is not on
/// [LichessConnection]: nothing in the domain or UI layers may hold it, log it,
/// or put it in an error message (003 FR-021).
library;

import 'package:chess_trainer/domain/lichess/lichess_connection.dart';
import 'package:meta/meta.dart';

/// Sealed so every `switch` over it is exhaustive, and a fourth state cannot be
/// added without the compiler naming every place that has to handle it.
@immutable
sealed class LichessAccount {
  const LichessAccount();
}

/// No credential is stored: either the player never logged in, or they
/// disconnected.
final class AccountDisconnected extends LichessAccount {
  const AccountDisconnected();

  @override
  bool operator ==(Object other) => other is AccountDisconnected;

  @override
  int get hashCode => (AccountDisconnected).hashCode;

  @override
  String toString() => 'AccountDisconnected()';
}

/// A credential is stored and its expiry has not passed.
final class AccountConnected extends LichessAccount {
  const AccountConnected(this.connection);

  final LichessConnection connection;

  String get username => connection.username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountConnected && connection == other.connection;

  @override
  int get hashCode => Object.hash(AccountConnected, connection);

  @override
  String toString() => 'AccountConnected(${connection.username})';
}

/// A credential was stored, its expiry has passed, and the token is gone.
///
/// The username and the date survive so the app can say *whose* login ran out.
/// They are not secrets and grant nothing; the token, which is and does, is
/// deleted the moment this state is observed (004 research D3). There is
/// deliberately no path from here to a renewed token — Lichess issues no
/// refresh tokens, so the only way back is logging in again.
final class AccountExpired extends LichessAccount {
  const AccountExpired(this.connection);

  final LichessConnection connection;

  String get username => connection.username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountExpired && connection == other.connection;

  @override
  int get hashCode => Object.hash(AccountExpired, connection);

  @override
  String toString() => 'AccountExpired(${connection.username})';
}
