import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

const _nestedVariations = '''
[Title "A nested fixture"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4 {A comment on the first move.} e5 (1... c5 {The Sicilian.} 2. Nf3 (2. Nc3 d6))
2. Nf3 Nc6 3. Bb5 \$1 {Ruy Lopez.}
''';

void main() {
  group('fromPgnNode enforces legality (invariant 10)', () {
    test('every node holds a move legal in its parent position', () {
      final position = parseTrainingPosition(_nestedVariations, id: 'fixture');

      expectEveryNodeLegal(position.solution);
    });

    test('an illegal mainline move fails the parse', () {
      expect(
        () => parseTrainingPosition('1. e4 e5 2. Ke2 Qh4 3. Kd8', id: 'bad'),
        throwsA(isA<PositionParseError>()),
      );
    });

    test('an illegal move inside a variation fails the parse too', () {
      // "e5" is a well-formed SAN token that is simply not legal as White's
      // first move. Garbage that is not SAN at all — "e9" — is dropped by the
      // dartchess tokeniser before it ever reaches here, so it would not
      // exercise the legality check.
      expect(
        () => parseTrainingPosition('1. e4 (1. e5) 1... e5', id: 'bad-variation'),
        throwsA(isA<PositionParseError>()),
      );
    });

    test('duplicate alternatives from one position are rejected', () {
      expect(
        () => parseTrainingPosition('1. e4 (1. e4) 1... e5', id: 'duplicate'),
        throwsA(isA<PositionParseError>()),
      );
    });
  });

  group('tree shape', () {
    test('the mainline becomes the primary line', () {
      final position = parseTrainingPosition(_nestedVariations, id: 'fixture');

      expect(
        position.solution.primaryLine.map((node) => node.san).toList(),
        ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'],
      );
    });

    test('variations become sibling branches at the right node', () {
      final position = parseTrainingPosition(_nestedVariations, id: 'fixture');
      final afterE4 = MovePath.root.child(0);

      final replies = position.solution.childrenAt(afterE4);
      expect(replies.map((node) => node.san).toList(), ['e5', 'c5']);

      // The nested variation inside the Sicilian line.
      final afterC5 = afterE4.child(1);
      expect(
        position.solution.childrenAt(afterC5).map((node) => node.san).toList(),
        ['Nf3', 'Nc3'],
      );
    });

    test('comments and NAGs are carried onto their moves', () {
      final position = parseTrainingPosition(_nestedVariations, id: 'fixture');

      expect(position.solution.nodeAt(MovePath.root.child(0))!.comments,
          contains('A comment on the first move.'));
      expect(
        position.solution.nodeAt(MovePath.root.child(0).child(1))!.comments,
        contains('The Sicilian.'),
      );
      final bb5 = position.solution.nodeAt(
        MovePath.root.child(0).child(0).child(0).child(0).child(0),
      )!;
      expect(bb5.san, 'Bb5');
      expect(bb5.nags, contains(1));
      expect(bb5.comments, contains('Ruy Lopez.'));
    });

    test('a user-shaped tree carries no comments or NAGs', () {
      final position = parseTrainingPosition('1. e4 e5', id: 'plain');
      for (final node in position.solution.primaryLine) {
        expect(node.comments, isEmpty);
        expect(node.nags, isEmpty);
      }
    });
  });

  group('headers', () {
    test('the FEN header sets the starting position', () {
      const pgn = '[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]\n\n1. Kc6';
      final position = parseTrainingPosition(pgn, id: 'endgame');

      expect(position.initialPosition.fen, '3k4/8/3K4/3P4/8/8/8/8 w - - 0 1');
      expect(position.sideToMove, Side.white);
    });

    test('a missing FEN header falls back to the standard position', () {
      final position = parseTrainingPosition('1. e4', id: 'standard');
      expect(position.initialPosition, Chess.initial);
    });

    test('an invalid FEN header fails the parse', () {
      expect(
        () => parseTrainingPosition('[FEN "not a fen"]\n\n1. e4', id: 'bad-fen'),
        throwsA(isA<PositionParseError>()),
      );
    });

    test('metadata is extracted from the headers', () {
      const pgn = '''
[Title "A title"]
[Goal "White to play and win"]
[Themes "fork, pin"]
[Rating "1750"]
[Source "Somewhere"]

1. e4
''';
      final metadata = parseTrainingPosition(pgn, id: 'meta').metadata;

      expect(metadata.title, 'A title');
      expect(metadata.goal, 'White to play and win');
      expect(metadata.themes, ['fork', 'pin']);
      expect(metadata.rating, 1750);
      expect(metadata.source, 'Somewhere');
    });

    test('PGN "unknown" markers are treated as absent metadata', () {
      const pgn = '[Event "?"]\n[Site "?"]\n\n1. e4';
      final metadata = parseTrainingPosition(pgn, id: 'unknown').metadata;

      expect(metadata.title, isNull);
      expect(metadata.source, isNull);
      expect(metadata.isEmpty, isTrue);
    });

    test('a PGN with no moves fails the parse', () {
      expect(
        () => parseTrainingPosition('[Title "Empty"]\n\n*', id: 'empty'),
        throwsA(isA<PositionParseError>()),
      );
    });
  });

  group('round trip', () {
    test('fromPgnNode and toPgnNode are inverses over a nested tree', () {
      final original = parseTrainingPosition(_nestedVariations, id: 'fixture');

      final roundTripped = fromPgnNode(
        toPgnNode(original.solution),
        original.initialPosition,
      );

      expect(roundTripped, original.solution);
    });

    test('a tree survives being written to PGN text and read back', () {
      final original = parseTrainingPosition(_nestedVariations, id: 'fixture');

      final game = PgnGame(
        headers: {'FEN': original.initialPosition.fen},
        moves: toPgnNode(original.solution),
        comments: const [],
      );
      final reparsed = parseTrainingPosition(game.makePgn(), id: 'fixture');

      expect(reparsed.solution, original.solution);
    });
  });
}

/// Walks the whole tree, replaying every move, so that a node holding an
/// illegal move would throw rather than pass unnoticed.
void expectEveryNodeLegal(VariationTree tree) {
  void walk(MovePath path) {
    final position = tree.positionAt(path);
    for (var i = 0; i < tree.childrenAt(path).length; i++) {
      final child = tree.childrenAt(path)[i];
      expect(position.isLegal(child.move), isTrue,
          reason: '${child.san} is not legal in ${position.fen}');
      expect(position.makeSan(child.move).$2, child.san,
          reason: 'stored SAN disagrees with the position');
      walk(path.child(i));
    }
  }

  walk(MovePath.root);
}
