/// Turning PGN into a [TrainingPosition].
///
/// Bundled positions are authored as PGN (research D4) rather than as a bespoke
/// JSON schema, because Lichess studies are PGN with exactly these constructs —
/// variations, comments, NAGs. Feature 004 imports studies through this same
/// code, so the parsing work is done once, here, where it is unit-tested
/// against fixtures.
library;

import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/tree/move_node.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// Headers that carry metadata. Everything here is withheld during training
/// (FR-003) and revealed at review (FR-025).
const _titleHeaders = ['Title', 'Event'];
const _sourceHeaders = ['Source', 'Site'];

/// Parses one bundled PGN into a training position.
///
/// Expects a `[FEN]` header for the starting position and falls back to the
/// standard initial position when absent. The mainline becomes the solution's
/// primary line, variations become sibling branches, and `{comments}` and NAGs
/// are carried onto the nodes they belong to.
///
/// Throws [PositionParseError] on an invalid FEN, an illegal move anywhere in
/// the game, or a PGN with no moves at all. This is deliberately loud: a
/// malformed sample position that reached a session would look to the user like
/// a bug in the training loop.
TrainingPosition parseTrainingPosition(String pgn, {required String id}) {
  final game = PgnGame.parsePgn(pgn, initHeaders: PgnGame.emptyHeaders);

  final initialPosition = _parseInitialPosition(game.headers, id);

  final VariationTree solution;
  try {
    solution = fromPgnNode(game.moves, initialPosition);
  } on PositionParseError catch (error) {
    throw PositionParseError(error.message, positionId: id);
  }

  if (solution.isEmpty) {
    throw PositionParseError('the PGN records no moves', positionId: id);
  }

  return TrainingPosition(
    id: id,
    initialPosition: initialPosition,
    solution: solution,
    metadata: _parseMetadata(game.headers),
  );
}

Position _parseInitialPosition(PgnHeaders headers, String id) {
  final fen = headers['FEN'];
  if (fen == null || fen.trim().isEmpty) return Chess.initial;
  try {
    return Chess.fromSetup(Setup.parseFen(fen.trim()));
  } on Object catch (error) {
    throw PositionParseError('invalid FEN header "$fen": $error',
        positionId: id);
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

  return PositionMetadata(
    title: pick(_titleHeaders),
    goal: pick(const ['Goal']),
    themes: themes,
    rating: rating == null ? null : int.tryParse(rating.trim()),
    source: pick(_sourceHeaders),
  );
}

/// Writes [tree] as PGN text, for storage (research D2).
///
/// The `[FEN]` header makes the result self-describing: a stored row can be
/// replayed without knowing which bundled position it came from, which is what
/// makes "the app updated and the bundled positions changed" survivable.
///
/// This is the same format feature 004 will ingest, so the app has one tree
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

/// The inverse of [fromPgnNode], for round-trip tests and for feature 004,
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
