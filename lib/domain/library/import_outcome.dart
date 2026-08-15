/// What one import produced: the positions it yielded, and everything it
/// refused, with reasons.
///
/// This is a domain type rather than a UI model because the rejection rules are
/// domain rules — what may be trained is not a presentation concern — and
/// because they are unit-tested as such against real study fixtures, which the
/// constitution's testing floor requires.
library;

import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// Why an entry could not become a trainable position.
///
/// An enum rather than free text so the report can *group*: a real study export
/// often yields nine chapters rejected for the same reason, and nine
/// near-identical lines is a wall, not a report (003 research D10).
enum RejectionReason {
  /// No `[FEN]` header. The common case for a game record, and for any study
  /// chapter that starts from the standard position — Lichess omits the header
  /// there. The app cannot know which of eighty positions was meant to be the
  /// exercise, and starting at move 1 is not a calculation exercise.
  noStartingPosition,

  /// A position with no legal move: checkmate, stalemate, or any other
  /// terminal state.
  ///
  /// **Replaced `noMoves` in feature 005**, and the swap is the whole feature in
  /// one enum. An entry with a position and no *author's* moves used to be
  /// rejected because there was no solution to grade against; an engine now
  /// supplies one, so it is imported. What is still refused is a position with
  /// nothing to calculate — importing one would open a board the player cannot
  /// move on, which is a trap discovered after training starts rather than at
  /// import where the report can explain it.
  ///
  /// `dartchess` decides this, never the engine (Constitution III: the engine
  /// must not be consulted about anything dartchess can answer).
  noLegalMoves,

  /// A move that is not legal in the position it is played from. The entry is
  /// rejected whole rather than truncated: a solution that ends early is
  /// indistinguishable, at review, from one that ends there on purpose.
  illegalMove,

  /// Chess960, Crazyhouse, Atomic and the rest. Training assumes standard
  /// chess, and a variant position trained as standard chess is worse than no
  /// position at all.
  unsupportedVariant,

  /// The entry is not PGN this app can read at all.
  unparseable,
}

/// A short, player-facing description of a reason, for grouping in the report.
///
/// Takes the count because the report reads "$count entries $summary", and a
/// single form cannot serve both: "1 entry has no moves" and "3 entries have no
/// moves" need different verbs. The first device run of this feature produced
/// "3 entries starts from the standard position", which no test caught — they
/// asserted the group existed, not that it read as English.
extension RejectionReasonText on RejectionReason {
  String summaryFor(int count) {
    final many = count != 1;
    return switch (this) {
      RejectionReason.noStartingPosition => many
          ? 'start from the standard position, so there is no position to train'
          : 'starts from the standard position, so there is no position to '
              'train',
      RejectionReason.noLegalMoves => many
          ? 'have no legal move, so there is nothing to calculate'
          : 'has no legal move, so there is nothing to calculate',
      RejectionReason.illegalMove => many
          ? 'contain a move that is not legal'
          : 'contains a move that is not legal',
      RejectionReason.unsupportedVariant =>
        many ? 'are not standard chess' : 'is not standard chess',
      RejectionReason.unparseable => 'could not be read as PGN',
    };
  }
}

/// One entry that did not become a position.
@immutable
class RejectedEntry {
  const RejectedEntry({
    required this.reference,
    required this.reason,
    this.detail,
  });

  /// How the player finds this entry in their own file: the chapter's name or
  /// event, falling back to its ordinal ("entry 7 of 12") when it has neither.
  final String reference;

  final RejectionReason reason;

  /// The parser's own message, for the reasons where it adds something — which
  /// move was illegal, which variant was found.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RejectedEntry &&
          reference == other.reference &&
          reason == other.reason &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(reference, reason, detail);

  @override
  String toString() => 'RejectedEntry($reference: ${reason.name})';
}

/// The result of parsing one source.
///
/// Invariant, asserted by `test/data/import_test.dart`: for a source of *n*
/// entries, `positions.length + rejections.length == n`. Nothing is ever
/// dropped without mention (FR-007, SC-008).
@immutable
class ImportOutcome {
  const ImportOutcome({
    this.positions = const IList.empty(),
    this.rejections = const IList.empty(),
  });

  final IList<TrainingPosition> positions;

  final IList<RejectedEntry> rejections;

  int get entryCount => positions.length + rejections.length;

  bool get isEmpty => positions.isEmpty;

  /// Rejections grouped by reason, for a report that reads like a sentence
  /// rather than a log.
  IMap<RejectionReason, IList<RejectedEntry>> get rejectionsByReason {
    final grouped = <RejectionReason, IList<RejectedEntry>>{};
    for (final rejection in rejections) {
      grouped[rejection.reason] =
          (grouped[rejection.reason] ?? const IList.empty()).add(rejection);
    }
    return grouped.lock;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportOutcome &&
          positions == other.positions &&
          rejections == other.rejections;

  @override
  int get hashCode => Object.hash(positions, rejections);

  @override
  String toString() =>
      'ImportOutcome(${positions.length} positions, '
      '${rejections.length} rejected)';
}
