/// Turning one import source — a picked file, or a study fetched from Lichess —
/// into positions and rejections.
///
/// Pure: no I/O, no plugins, no Flutter. That is what lets it run inside
/// `Isolate.run` so parsing a large study does not drop frames (003 research
/// D15), and what lets it be tested against real study fixtures with no device
/// attached (Constitution V).
///
/// The rule this file exists to enforce is FR-007: **one bad entry costs the
/// player that entry and nothing else.** A source is only refused as a whole
/// when there is nothing in it to import.
library;

import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// Supplies a stable, unique id for each imported position.
typedef IdGenerator = String Function();

/// The caps, stated rather than discovered (003 research D16).
///
/// A refusal that names its limit is the alternative to an app that appears to
/// hang; the numbers are chosen against reality, since a large Lichess study
/// exports at a few hundred kilobytes and only a PGN *database* exceeds these.
const int maxSourceCharacters = 5 * 1024 * 1024;
const int maxEntries = 500;

/// Headers that name an entry well enough for a player to find it in their own
/// file. `ChapterName` is what Lichess writes.
const _referenceHeaders = ['ChapterName', 'Title', 'Event', 'White'];

/// Parses a whole source.
///
/// Returns every usable entry and every rejection, such that
/// `positions.length + rejections.length` equals the number of entries in the
/// source — always. Nothing is dropped without mention (SC-008).
///
/// Throws only when the *source* is unusable:
///
/// - [SourceUnreadableError] when it is empty or is not PGN at all.
/// - [SourceTooLargeError] when it is past [maxSourceCharacters] or
///   [maxEntries].
ImportOutcome parseImport(String pgn, {required IdGenerator newId}) {
  if (pgn.trim().isEmpty) {
    throw SourceUnreadableError('the file is empty');
  }
  if (pgn.length > maxSourceCharacters) {
    throw SourceTooLargeError(
      'this file is larger than the 5 MB this app imports at once. A study '
      'exports at a few hundred kilobytes, so this is probably a database of '
      'games rather than a study',
    );
  }

  final List<PgnGame<PgnNodeData>> games;
  try {
    // `emptyHeaders` rather than the default: dartchess otherwise invents the
    // seven Standard Tag Roster headers with `?` placeholders, which would put
    // headers the file never carried into the metadata bag and make "is there
    // anything here to read?" unanswerable.
    games = PgnGame.parseMultiGamePgn(pgn,
        initHeaders: PgnGame.emptyHeaders);
  } on Object catch (error) {
    throw SourceUnreadableError(
      'this does not read as PGN. A study exported from Lichess, or any file '
      'of games or positions in PGN, is what this expects ($error)',
    );
  }

  if (_hasNothingToRead(games)) {
    throw SourceUnreadableError(
      'this does not read as PGN. A study exported from Lichess, or any file '
      'of games or positions in PGN, is what this expects',
    );
  }

  if (games.length > maxEntries) {
    throw SourceTooLargeError(
      'this source holds ${games.length} entries, and this app imports at most '
      '$maxEntries at a time',
    );
  }

  var positions = const IList<TrainingPosition>.empty();
  var rejections = const IList<RejectedEntry>.empty();

  for (var index = 0; index < games.length; index++) {
    final game = games[index];
    final reference = _referenceFor(game.headers, index, games.length);
    try {
      positions = positions.add(trainingPositionFromGame(game, id: newId()));
    } on PositionParseError catch (error) {
      rejections = rejections.add(RejectedEntry(
        reference: reference,
        reason: error.reason,
        detail: error.message,
      ));
    } on Object catch (error) {
      // Anything dartchess raises that we did not anticipate is still one
      // entry's problem, not the source's. Losing a chapter is recoverable;
      // losing the import because of a chapter is not.
      rejections = rejections.add(RejectedEntry(
        reference: reference,
        reason: RejectionReason.unparseable,
        detail: '$error',
      ));
    }
  }

  return ImportOutcome(positions: positions, rejections: rejections);
}

/// True when the text produced no entry with either a header or a move.
///
/// `parseMultiGamePgn` is forgiving by design — hand it a photo and it hands
/// back one empty game rather than throwing. That would otherwise be reported
/// as "1 entry, rejected: no moves", which tells the player nothing about the
/// actual problem, which is that they picked the wrong file.
bool _hasNothingToRead(List<PgnGame<PgnNodeData>> games) =>
    games.isEmpty ||
    games.every((game) =>
        game.headers.isEmpty && game.moves.children.isEmpty);

String _referenceFor(PgnHeaders headers, int index, int total) {
  for (final name in _referenceHeaders) {
    final value = headers[name]?.trim();
    if (value != null && value.isNotEmpty && value != '?') return value;
  }
  return 'entry ${index + 1} of $total';
}
