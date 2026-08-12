/// Errors raised by the domain layer.
///
/// See `specs/001-training-session-core/contracts/domain-api.md`, "Error contract".
library;

/// Thrown when a move is played that is not legal in the position it is played
/// from.
///
/// This indicates a caller bug rather than a user error: the board only ever
/// offers legal destinations (research D6), so a user cannot provoke it.
class IllegalMoveError extends Error {
  IllegalMoveError(this.uci, this.fen);

  /// UCI of the offending move.
  final String uci;

  /// FEN of the position it was played from.
  final String fen;

  @override
  String toString() => 'IllegalMoveError: $uci is not legal in $fen';
}

/// Thrown when a [MovePath] does not address an existing node.
///
/// The usual cause is a stale cursor held across a `promote` or `delete`, which
/// renumber sibling indices.
class InvalidPathError extends Error {
  InvalidPathError(this.path, [this.detail]);

  /// String form of the offending path.
  final String path;

  /// Optional extra context.
  final String? detail;

  @override
  String toString() =>
      'InvalidPathError: $path does not address a node${detail == null ? '' : ' ($detail)'}';
}

/// Thrown when a bundled PGN cannot be turned into a training position.
///
/// Deliberately fatal at load time: a malformed sample position must never
/// reach a session, where it would look like a bug in the training loop.
class PositionParseError implements Exception {
  PositionParseError(this.message, {this.positionId});

  final String message;
  final String? positionId;

  @override
  String toString() =>
      'PositionParseError${positionId == null ? '' : ' [$positionId]'}: $message';
}
