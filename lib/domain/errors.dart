/// Errors raised by the domain layer.
///
/// See `specs/001-training-session-core/contracts/domain-api.md`, "Error
/// contract", and `specs/003-position-import/contracts/` for the import and
/// network errors added by feature 003.
library;

import 'package:chess_trainer/domain/library/import_outcome.dart';

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

/// Thrown when a PGN entry cannot be turned into a training position.
///
/// Its two readers treat it differently, which is the point of [reason].
/// Loading the *bundled* positions still lets it escape and fail the load: a
/// malformed sample must never reach a session, where it would look like a bug
/// in the training loop. An *import* catches it per entry and turns it into a
/// [RejectedEntry], so one bad chapter costs the player that chapter and
/// nothing else (FR-007).
class PositionParseError implements Exception {
  PositionParseError(
    this.message, {
    this.positionId,
    this.reason = RejectionReason.unparseable,
  });

  final String message;
  final String? positionId;

  /// Which kind of unusable this is, so the import report can group by it
  /// rather than printing near-identical lines (003 research D10).
  final RejectionReason reason;

  @override
  String toString() =>
      'PositionParseError${positionId == null ? '' : ' [$positionId]'}: $message';
}

/// Thrown when a whole import source cannot be read.
///
/// Distinct from [PositionParseError], which rejects one entry. This one means
/// there is nothing to import at all — the file is a photo, a spreadsheet, or
/// empty — and the player is told what was expected rather than shown a parser
/// error (FR-006).
class SourceUnreadableError implements Exception {
  SourceUnreadableError(this.message);

  final String message;

  @override
  String toString() => 'SourceUnreadableError: $message';
}

/// Thrown when an import source is past the stated caps.
///
/// The message **must name the limit** (003 research D16). A refusal that
/// explains itself is the alternative to an app that appears to hang, which is
/// the only other honest option for a source this large.
class SourceTooLargeError implements Exception {
  SourceTooLargeError(this.message);

  final String message;

  @override
  String toString() => 'SourceTooLargeError: $message';
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

// ---------------------------------------------------------------------------
// Feature 003: the network. Every one of these must produce a message naming
// what happened and what the player can do (SC-011), and none of them may leave
// a partial collection behind (FR-019).
// ---------------------------------------------------------------------------

/// The device has no usable connection, or the request timed out.
///
/// Importing needs one; nothing else in the app does (FR-016).
class NoConnectionError implements Exception {
  NoConnectionError([this.cause]);

  final Object? cause;

  @override
  String toString() => 'NoConnectionError${cause == null ? '' : ': $cause'}';
}

/// A private study was asked for without a credential.
class NotLoggedInError implements Exception {
  @override
  String toString() => 'NotLoggedInError';
}

/// The credential is expired or revoked.
///
/// **There is no refresh path, and there must never be one.** Lichess issues no
/// refresh tokens, so renewal cannot work; the only honest response is to ask
/// the player to log in again (FR-017, 003 research D5).
class LoginExpiredError implements Exception {
  @override
  String toString() => 'LoginExpiredError';
}

/// The player dismissed the authorization page.
///
/// A normal outcome, not a failure, and reported as neither.
class LoginCancelledError implements Exception {
  @override
  String toString() => 'LoginCancelledError';
}

/// Lichess is rate-limiting this app.
///
/// Its own guidance is to wait about a minute and reduce request frequency.
/// The app does not retry on its own: an automatic backoff loop turns a
/// one-minute wait into an app that appears to hang (FR-018, D6).
class RateLimitedError implements Exception {
  @override
  String toString() => 'RateLimitedError';
}

/// The study does not exist, or is not visible to this account.
class StudyNotAvailableError implements Exception {
  StudyNotAvailableError(this.studyId);

  final String studyId;

  @override
  String toString() => 'StudyNotAvailableError: $studyId';
}

/// What the player pasted is not a Lichess study address.
class NotAStudyLinkError implements Exception {
  NotAStudyLinkError(this.input);

  final String input;

  @override
  String toString() => 'NotAStudyLinkError: $input';
}

/// Lichess answered with a server error, or with something unreadable.
class LichessUnavailableError implements Exception {
  LichessUnavailableError(this.detail);

  final String detail;

  @override
  String toString() => 'LichessUnavailableError: $detail';
}
