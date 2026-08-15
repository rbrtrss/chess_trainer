import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// The standard starting position, spelled out.
///
/// Feature 003 made `[FEN]` mandatory (003 research D10), so the fixtures below
/// that used to rely on the old fallback now say where they start. Without this
/// they would still throw `PositionParseError` and still pass — for the wrong
/// reason, testing the missing-header rule instead of the legality rule they
/// were written for.
const _initialFen =
    '[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]\n\n';

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
        () => parseTrainingPosition('$_initialFen'
            '1. e4 e5 2. Ke2 Qh4 3. Kd8', id: 'bad'),
        throwsA(isA<PositionParseError>()),
      );
    });

    test('an illegal move inside a variation fails the parse too', () {
      // "e5" is a well-formed SAN token that is simply not legal as White's
      // first move. Garbage that is not SAN at all — "e9" — is dropped by the
      // dartchess tokeniser before it ever reaches here, so it would not
      // exercise the legality check.
      expect(
        () => parseTrainingPosition('$_initialFen'
            '1. e4 (1. e5) 1... e5', id: 'bad-variation'),
        throwsA(isA<PositionParseError>()),
      );
    });

    test('duplicate alternatives from one position are rejected', () {
      expect(
        () => parseTrainingPosition('$_initialFen'
            '1. e4 (1. e4) 1... e5', id: 'duplicate'),
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
      final position = parseTrainingPosition('$_initialFen' '1. e4 e5', id: 'plain');
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

    test('a missing FEN header is rejected, not filled in (FR-003)', () {
      // Until feature 003 this fell back to the standard initial position.
      // Against arbitrary imports that silently turned a game record into a
      // "position" starting at move 1 — untrainable, and ungradeable.
      expect(
        () => parseTrainingPosition('1. e4', id: 'standard'),
        throwsA(isA<PositionParseError>().having(
          (error) => error.reason,
          'reason',
          RejectionReason.noStartingPosition,
        )),
      );
    });

    test('an invalid FEN header fails the parse', () {
      expect(
        () => parseTrainingPosition('[FEN "not a fen"]\n\n1. e4', id: 'bad-fen'),
        throwsA(isA<PositionParseError>().having(
          (error) => error.reason,
          'reason',
          RejectionReason.noStartingPosition,
        )),
      );
    });

    test('metadata is extracted from the headers', () {
      const pgn = '''
[Title "A title"]
[Goal "White to play and win"]
[Themes "fork, pin"]
[Rating "1750"]
[Source "Somewhere"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4
''';
      final metadata = parseTrainingPosition(pgn, id: 'meta').metadata;

      expect(metadata.title, 'A title');
      expect(metadata.goal, 'White to play and win');
      expect(metadata.themes, ['fork', 'pin']);
      expect(metadata.rating, 1750);
      expect(metadata.source, 'Somewhere');
    });

    test('PGN "unknown" markers are treated as absent typed metadata', () {
      final metadata =
          parseTrainingPosition('[Event "?"]\n[Site "?"]\n$_initialFen 1. e4',
                  id: 'unknown')
              .metadata;

      expect(metadata.title, isNull);
      expect(metadata.source, isNull);
      // The bag keeps them, because at review "[Event "?"]" is the file being
      // honest about what it does not know. `isEmpty` is therefore false: the
      // entry carried headers, even if none of them said anything.
      expect(metadata.headers['Event'], '?');
      expect(metadata.isEmpty, isFalse);
    });

    test('a PGN with no moves now parses, with no solution and no author '
        '(005 FR-001)', () {
      // The rejection this feature exists to remove. Setting up a position and
      // stopping is how a player authors an exercise for themselves, and until
      // 005 the app refused exactly that — on a real device, on 2026-08-15,
      // with "1 entry has no moves, so there is no solution".
      final position =
          parseTrainingPosition('[Title "Empty"]\n$_initialFen*', id: 'empty');

      expect(position.solution.isEmpty, isTrue);
      expect(position.solutionSource, SolutionSource.none,
          reason: 'the parser does no I/O and knows no engine exists; the '
              'import service is what upgrades this to `engine`');
      expect(position.evaluation, isNull);
      expect(position.initialPosition.fen, contains('rnbqkbnr'));
    });

    test('a position with moves is still authored', () {
      final position = parseTrainingPosition(
        '[Title "Has a line"]\n$_initialFen 1. e4 e5 *',
        id: 'authored',
      );

      expect(position.solutionSource, SolutionSource.author);
      expect(position.evaluation, isNull,
          reason: 'where an author said what they intended, the engine is not '
              'consulted and nothing is stored (FR-011)');
    });

    test('a checkmate position is rejected — nothing to calculate (FR-004)',
        () {
      // New in 005, inside a feature whose purpose is to reject less. It stays
      // because the alternative is a position that imports and then opens a
      // board the player cannot move on: a trap found after training starts,
      // rather than at import where the report can explain it.
      expect(
        () => parseTrainingPosition(
          '[FEN "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"]\n*',
          id: 'mated',
        ),
        throwsA(isA<PositionParseError>().having(
          (error) => error.reason,
          'reason',
          RejectionReason.noLegalMoves,
        )),
      );
    });

    test('a stalemate position is rejected for the same reason', () {
      expect(
        () => parseTrainingPosition(
          '[FEN "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"]\n*',
          id: 'stalemated',
        ),
        throwsA(isA<PositionParseError>().having(
          (error) => error.reason,
          'reason',
          RejectionReason.noLegalMoves,
        )),
      );
    });
  });

  group('the header bag (FR-024, FR-025, 003 research D11)', () {
    test('every header is captured, including ones nobody anticipated', () {
      const pgn = '''
[Event "World Blitz 2025 Open"]
[StudyName "A study"]
[ChapterName "Chapter 3: Winning the Opposition"]
[Annotator "https://lichess.org/@/Lichess"]
[WhiteFideId "939935"]
[SomeTagInventedToday "and its value"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

1. Kc6
''';
      final metadata = parseTrainingPosition(pgn, id: 'bag').metadata;

      // The point of the bag: a header this app has never heard of is captured
      // and therefore withheld, rather than dropped on the floor and lost to
      // review. The rule cannot be a list of field names, because the list is
      // not ours to write.
      expect(metadata.headers['SomeTagInventedToday'], 'and its value');
      expect(metadata.headers['WhiteFideId'], '939935');
      expect(metadata.headers['Annotator'], contains('Lichess'));
      expect(metadata.headers['StudyName'], 'A study');
      expect(metadata.headers['FEN'], isNotNull);
    });

    test('ChapterName is preferred as the title — it is the leak', () {
      const pgn = '''
[Event "Some event"]
[ChapterName "Chapter 3: Winning the Opposition"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

1. Kc6
''';
      expect(parseTrainingPosition(pgn, id: 'chapter').metadata.title,
          'Chapter 3: Winning the Opposition');
    });
  });

  group('variants (FR-006)', () {
    test('a non-standard variant is rejected', () {
      const pgn = '''
[Variant "Crazyhouse"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4
''';
      expect(
        () => parseTrainingPosition(pgn, id: 'zh'),
        throwsA(isA<PositionParseError>().having(
          (error) => error.reason,
          'reason',
          RejectionReason.unsupportedVariant,
        )),
      );
    });

    test('"From Position" is standard chess, and must not be rejected', () {
      // This is what Lichess writes for a chapter set up from a FEN — which is
      // to say, for every chapter this app can actually use. Rejecting it would
      // reject an entire real study.
      const pgn = '''
[Variant "From Position"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

1. Kc6
''';
      expect(parseTrainingPosition(pgn, id: 'from-position').sideToMove,
          Side.white);
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
