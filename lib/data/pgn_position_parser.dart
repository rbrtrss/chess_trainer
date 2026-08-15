/// Turning PGN into a [TrainingPosition].
///
/// Bundled positions are authored as PGN (research D4) rather than as a bespoke
/// JSON schema, because Lichess studies are PGN with exactly these constructs —
/// variations, comments, NAGs. Feature 003 imports studies through this same
/// code, so the parsing work is done once, here, where it is unit-tested
/// against fixtures.
library;

import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/tree/move_node.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// Headers the typed metadata fields are derived from.
///
/// This list is no longer what "withheld" means — every header is captured into
/// [PositionMetadata.headers] and withheld regardless (003 research D11). These
/// names only decide which values review lays out deliberately.
///
/// `ChapterName` comes first because it is what Lichess writes and it is
/// literally the constitution's example of evidence: "Chapter 3: Winning the
/// Opposition" tells the player the answer.
const _titleHeaders = ['ChapterName', 'Title', 'Event'];
const _sourceHeaders = ['Source', 'Site', 'ChapterURL'];

/// `[Variant]` values that mean ordinary chess.
///
/// `From Position` is what Lichess writes for a chapter set up from a FEN —
/// which is to say, for exactly the chapters this app wants. Treating anything
/// but `Standard` as unsupported would reject every usable chapter of a real
/// study; the first fixture we fetched proved it (see `test/fixtures/README.md`).
const _standardVariants = {'standard', 'from position', 'chess', '?'};

/// Parses one PGN entry into a training position.
///
/// The mainline becomes the solution's primary line, variations become sibling
/// branches, and `{comments}` and NAGs are carried onto the nodes they belong
/// to. Every header is captured into [PositionMetadata.headers].
///
/// Throws [PositionParseError], carrying a [RejectionReason], when the entry
/// cannot be trained:
///
/// - **no `[FEN]` header** — [RejectionReason.noStartingPosition]. This
///   **changed in feature 003**: it used to fall back to the standard initial
///   position. That was safe for the three positions we authored and reviewed,
///   and is wrong for arbitrary imports, where it silently turns a game record
///   into a "position" starting at move 1 that nobody can train and nobody can
///   grade (FR-003, 003 research D10).
/// - **a non-standard `[Variant]`** — [RejectionReason.unsupportedVariant].
/// - **an illegal move** — [RejectionReason.illegalMove]. The entry is rejected
///   whole rather than truncated.
/// - **no moves at all** — [RejectionReason.noMoves].
///
/// Loading the bundled positions still lets this escape and fail the whole load:
/// a malformed sample must never reach a session, where it would look like a bug
/// in the training loop. An import catches it per entry instead.
TrainingPosition parseTrainingPosition(String pgn, {required String id}) =>
    trainingPositionFromGame(
      PgnGame.parsePgn(pgn, initHeaders: PgnGame.emptyHeaders),
      id: id,
    );

/// The same, for a game already parsed.
///
/// Exists so that importing a multi-entry source can split once with
/// `PgnGame.parseMultiGamePgn` and convert each entry in place, rather than
/// re-serialising every chapter back to text only to parse it again — which on
/// a 300-chapter study is the difference between a pause and a hang.
TrainingPosition trainingPositionFromGame(
  PgnGame<PgnNodeData> game, {
  required String id,
}) {
  _requireStandardVariant(game.headers, id);

  final initialPosition = _parseInitialPosition(game.headers, id);

  final VariationTree solution;
  try {
    solution = fromPgnNode(game.moves, initialPosition);
  } on PositionParseError catch (error) {
    throw PositionParseError(
      error.message,
      positionId: id,
      reason: RejectionReason.illegalMove,
    );
  }

  if (solution.isEmpty) {
    throw PositionParseError(
      'the PGN records no moves',
      positionId: id,
      reason: RejectionReason.noMoves,
    );
  }

  return TrainingPosition(
    id: id,
    initialPosition: initialPosition,
    solution: solution,
    metadata: _parseMetadata(game.headers),
  );
}

void _requireStandardVariant(PgnHeaders headers, String id) {
  final variant = headers['Variant']?.trim();
  if (variant == null || variant.isEmpty) return;
  if (_standardVariants.contains(variant.toLowerCase())) return;
  throw PositionParseError(
    'the entry is $variant, not standard chess',
    positionId: id,
    reason: RejectionReason.unsupportedVariant,
  );
}

Position _parseInitialPosition(PgnHeaders headers, String id) {
  final fen = headers['FEN'];
  if (fen == null || fen.trim().isEmpty) {
    throw PositionParseError(
      'the entry has no [FEN] header, so it does not say which position to '
      'train',
      positionId: id,
      reason: RejectionReason.noStartingPosition,
    );
  }
  try {
    return Chess.fromSetup(Setup.parseFen(fen.trim()));
  } on Object catch (error) {
    throw PositionParseError('invalid FEN header "$fen": $error',
        positionId: id, reason: RejectionReason.noStartingPosition);
  }
}

PositionMetadata _parseMetadata(PgnHeaders headers) {
  String? pick(List<String> names) {
    for (final name in names) {
      final value = headers[name]?.trim();
      // '?' is PGN's "unknown", and dartchess writes it into default headers.
      if (value != null && value.isNotEmpty && value != '?') return value;
    }
    return null;
  }

  final themes = headers['Themes']
          ?.split(',')
          .map((theme) => theme.trim())
          .where((theme) => theme.isNotEmpty)
          .toIList() ??
      const IList<String>.empty();

  final rating = headers['Rating'];

  // Every header, verbatim, including the ones the typed fields above are
  // derived from and every one this app has never heard of. `?` is kept here
  // although the typed fields skip it: at review, "[Date "?"]" is the file
  // being honest, and no training screen sees any of this either way.
  final bag = <String, String>{};
  for (final entry in headers.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) continue;
    bag[key] = entry.value;
  }

  return PositionMetadata(
    title: pick(_titleHeaders),
    goal: pick(const ['Goal']),
    themes: themes,
    rating: rating == null ? null : int.tryParse(rating.trim()),
    source: pick(_sourceHeaders),
    headers: bag.lock,
  );
}

/// Writes [tree] as PGN text, for storage (research D2).
///
/// The `[FEN]` header makes the result self-describing: a stored row can be
/// replayed without knowing which bundled position it came from, which is what
/// makes "the app updated and the bundled positions changed" survivable.
///
/// This is the same format feature 003 will ingest, so the app has one tree
/// interchange format in both directions rather than two — and it is legible in
/// a database browser, which matters when diagnosing a report of lost work.
String encodeTree(VariationTree tree) {
  final game = PgnGame<PgnNodeData>(
    headers: {'FEN': tree.initialPosition.fen},
    moves: toPgnNode(tree),
    comments: const [],
  );
  return game.makePgn();
}

/// The inverse of [encodeTree].
///
/// Throws [TreeDecodeError] when the text is not a tree this app wrote: a
/// missing or invalid `[FEN]` header, or a move that is illegal in the position
/// it is played from. Every move is replayed as the tree is rebuilt, so a
/// corrupted row cannot become a tree that looks fine and behaves strangely.
VariationTree decodeTree(String pgn) {
  final PgnGame<PgnNodeData> game;
  try {
    game = PgnGame.parsePgn(pgn, initHeaders: PgnGame.emptyHeaders);
  } on Object catch (error) {
    throw TreeDecodeError('stored PGN could not be parsed: $error');
  }

  final fen = game.headers['FEN']?.trim();
  if (fen == null || fen.isEmpty) {
    throw TreeDecodeError('stored PGN has no [FEN] header');
  }

  final Position initialPosition;
  try {
    initialPosition = Chess.fromSetup(Setup.parseFen(fen));
  } on Object catch (error) {
    throw TreeDecodeError('stored PGN has an invalid [FEN] header "$fen": $error');
  }

  try {
    return fromPgnNode(game.moves, initialPosition);
  } on PositionParseError catch (error) {
    throw TreeDecodeError('stored PGN is not replayable: ${error.message}');
  }
}

/// Converts a parsed dartchess tree into the domain tree.
///
/// Every move is replayed from [initialPosition] as the tree is built, so a
/// node holding a move that is illegal in its parent position cannot be
/// constructed (invariant 10). The dartchess parser is deliberately lenient —
/// it produces syntactically valid but not necessarily legal trees — so this is
/// the step where that leniency is converted into a hard failure.
VariationTree fromPgnNode(PgnNode<PgnNodeData> node, Position initialPosition) {
  return VariationTree(
    initialPosition: initialPosition,
    children: _convertChildren(node, initialPosition),
  );
}

IList<MoveNode> _convertChildren(PgnNode<PgnNodeData> node, Position position) {
  final converted = <MoveNode>[];
  for (final child in node.children) {
    final san = child.data.san;
    final move = position.parseSan(san);
    if (move == null) {
      throw PositionParseError('"$san" is not legal in ${position.fen}');
    }
    if (converted.any((sibling) => sibling.san == san)) {
      // Two identical variations from one position would give the tree two
      // nodes that navigation cannot tell apart (FR-008).
      throw PositionParseError(
          'the move "$san" appears twice as an alternative in ${position.fen}');
    }
    final after = position.playUnchecked(move);
    converted.add(
      MoveNode(
        move: move,
        san: san,
        children: _convertChildren(child, after),
        comments: _comments(child.data),
        nags: child.data.nags?.toIList() ?? const IList<int>.empty(),
      ),
    );
  }
  return converted.lock;
}

/// Comments written before the move and after it both belong to that move as
/// far as review is concerned, so they are flattened into one list. A PGN
/// round trip therefore normalises pre-move comments into post-move comments.
IList<String> _comments(PgnNodeData data) {
  final comments = <String>[
    ...?data.startingComments,
    ...?data.comments,
  ];
  return comments.isEmpty ? const IList<String>.empty() : comments.lock;
}

/// The inverse of [fromPgnNode], for round-trip tests and for feature 003,
/// which will need to write trees back out as PGN.
PgnNode<PgnNodeData> toPgnNode(VariationTree tree) {
  final root = PgnNode<PgnNodeData>();
  _appendChildren(root, tree.children);
  return root;
}

void _appendChildren(PgnNode<PgnNodeData> parent, IList<MoveNode> children) {
  for (final node in children) {
    final child = PgnChildNode(
      PgnNodeData(
        san: node.san,
        comments: node.comments.isEmpty ? null : node.comments.unlock,
        nags: node.nags.isEmpty ? null : node.nags.unlock,
      ),
    );
    parent.children.add(child);
    _appendChildren(child, node.children);
  }
}
