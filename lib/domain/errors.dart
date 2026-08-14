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

/// Thrown when stored PGN cannot be replayed as a tree this app wrote.
///
/// Its two readers treat it differently on purpose. A *read* swallows it and
/// reports the data as absent (FR-023) — a corrupt row must not stop the app
/// from starting. A *write* never swallows it, because the one thing that must
/// not happen is the player believing their work was stored (FR-024).
class TreeDecodeError implements Exception {
  TreeDecodeError(this.message);

  final String message;

  @override
  String toString() => 'TreeDecodeError: $message';
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

/// Thrown when a session is started while another is already unfinished.
///
/// A caller bug rather than a user error: the UI warns and discards first
/// (FR-010). It exists so that the mistake fails at the moment it is made
/// instead of producing a second live session that makes "resume" ambiguous.
class SessionAlreadyInProgressError extends Error {
  SessionAlreadyInProgressError(this.existingSessionId);

  final String? existingSessionId;

  @override
  String toString() => 'SessionAlreadyInProgressError: a session is already in '
      'progress${existingSessionId == null ? '' : ' ($existingSessionId)'}';
}

/// Thrown when a write fails.
///
/// **Must surface to the player** (FR-024). A failed read is swallowed and the
/// data reported as absent; a failed write never is, because the one thing that
/// must not happen is the player believing their work was stored when it was
/// not.
class StorageWriteError implements Exception {
  StorageWriteError(this.operation, this.cause);

  /// What was being attempted, in words a player-facing message can use.
  final String operation;

  final Object cause;

  @override
  String toString() => 'StorageWriteError: $operation failed ($cause)';
}
