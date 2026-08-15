import 'dart:io';

import 'package:chess_trainer/data/import_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// Import parsing, against **real** Lichess study exports.
///
/// The constitution's testing floor asks for exactly this: "Study PGN →
/// training position extraction, against real fixture files". Hand-written
/// fixtures would not contain the things that actually break an import —
/// `[Variant "From Position"]`, `[ChapterName]`, chapters with no starting
/// position, and annotation styles we did not invent. See
/// `test/fixtures/README.md` for where each file came from.
String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

IdGenerator counterIds() {
  var next = 0;
  return () => 'p${next++}';
}

void main() {
  group('a real multi-chapter study (SC-005)', () {
    late ImportOutcome outcome;

    setUp(() {
      outcome = parseImport(fixture('study_multi_chapter.pgn'),
          newId: counterIds());
    });

    test('every chapter becomes a position', () {
      // 33 chapters, every one of them with a [FEN]. This is the happy path at
      // a realistic size.
      expect(outcome.positions, hasLength(33));
      expect(outcome.rejections, isEmpty);
    });

    test('the author\'s comments survive onto the moves (FR-005)', () {
      final withComments = outcome.positions.where((position) =>
          position.solution.primaryLine.any((node) => node.comments.isNotEmpty));

      expect(withComments, isNotEmpty,
          reason: 'the fixture has annotator comments; if none survived, the '
              'export parameters or the parser dropped them');
    });

    test('variations survive as branches, not a flattened line (FR-004)', () {
      // Somewhere in a real annotated study, a position has more than one move
      // offered from it. If nothing branches anywhere, variations were
      // flattened — which would make the solutions useless to train against.
      final branching = outcome.positions
          .where((position) => _branches(position.solution, MovePath.root));

      expect(branching, isNotEmpty);
    });

    test('every position carries the full header bag (FR-024)', () {
      for (final position in outcome.positions) {
        expect(position.metadata.headers['StudyName'], isNotNull,
            reason: '${position.id} lost the study name, which is withheld '
                'during training but must be there to withhold');
        expect(position.metadata.headers['ChapterName'], isNotNull);
      }
    });

    test('ids are unique across the import', () {
      final ids = outcome.positions.map((position) => position.id).toSet();
      expect(ids, hasLength(outcome.positions.length));
    });
  });

  group('a real study with chapters that cannot be trained (FR-007)', () {
    late ImportOutcome outcome;

    setUp(() {
      outcome = parseImport(fixture('study_mixed_chapters.pgn'),
          newId: counterIds());
    });

    test('the usable chapters import and the rest are rejected', () {
      // 11 chapters. **Eight are trainable since feature 005**, and three start
      // from the standard position with no [FEN]. One bad chapter does not
      // discard the rest — that is the whole rule (003 invariant 3).
      //
      // It was seven before 005, because one chapter is a position with no
      // moves and there was no way to grade it. That chapter is exactly what
      // this feature exists for, and it is a real one from a real study rather
      // than a case invented to prove a point — which makes this the cheapest
      // demonstration in the suite that the feature does something.
      expect(outcome.positions, hasLength(8));
      expect(outcome.rejections, hasLength(3));
    });

    test('each rejection says which kind of unusable it is', () {
      expect(
        outcome.rejections.map((rejection) => rejection.reason).toSet(),
        {RejectionReason.noStartingPosition},
      );
    });

    test('each rejection identifies the chapter the player would look for', () {
      for (final rejection in outcome.rejections) {
        expect(rejection.reference, isNotEmpty);
        expect(rejection.reference, isNot(startsWith('entry ')),
            reason: 'this fixture names its chapters, so the report should use '
                'the name rather than falling back to an ordinal');
      }
    });

    test('rejections group by reason, so the report is not a wall (D10)', () {
      // Three chapters, one line: "3 chapters start from the standard
      // position, so there is no position to train."
      final grouped = outcome.rejectionsByReason;
      expect(grouped.keys, hasLength(1));
      expect(grouped[RejectionReason.noStartingPosition], hasLength(3));
    });
  });

  group('a real study in another variant (FR-006)', () {
    test('every chapter is rejected as not standard chess', () {
      final outcome =
          parseImport(fixture('study_variant.pgn'), newId: counterIds());

      expect(outcome.positions, isEmpty);
      expect(
        outcome.rejections.map((rejection) => rejection.reason).toSet(),
        {RejectionReason.unsupportedVariant},
      );
    });
  });

  group('nothing is dropped without mention (SC-008, invariant 5)', () {
    test('positions plus rejections equals the entry count, every time', () {
      for (final name in const [
        'study_multi_chapter.pgn',
        'study_mixed_chapters.pgn',
        'study_variant.pgn',
      ]) {
        final source = fixture(name);
        final outcome = parseImport(source, newId: counterIds());
        final chapters = '[Event '.allMatches(source).length;

        expect(outcome.entryCount, chapters,
            reason: '$name: ${outcome.positions.length} imported and '
                '${outcome.rejections.length} rejected does not account for '
                'all $chapters entries — something was dropped silently');
      }
    });
  });

  group('a source that cannot be read at all (US1 scenario 8)', () {
    test('an empty file is refused, not imported as nothing', () {
      expect(() => parseImport('   \n  ', newId: counterIds()),
          throwsA(isA<SourceUnreadableError>()));
    });

    test('a file that is not PGN says what was expected', () {
      // The failure mode this guards against is a parser error shown to a
      // player who picked a photo: `parseMultiGamePgn` is forgiving enough to
      // return one empty game rather than throwing, which would otherwise be
      // reported as "1 entry, rejected: no moves".
      expect(
        () => parseImport('PNG\r\n\n binary rubbish',
            newId: counterIds()),
        throwsA(isA<SourceUnreadableError>().having(
          (error) => error.message,
          'message',
          contains('PGN'),
        )),
      );
    });

    test('a source past the size cap names the limit (D16)', () {
      final huge = '${'[Event "x"]\n\n1. e4\n\n' * 10}${' ' * maxSourceCharacters}';

      expect(
        () => parseImport(huge, newId: counterIds()),
        throwsA(isA<SourceTooLargeError>().having(
          (error) => error.message,
          'message',
          contains('5 MB'),
        )),
      );
    });

    test('a source past the entry cap names that limit too', () {
      final many =
          '[Event "e"]\n[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]\n\n1. Kc6\n\n' *
              (maxEntries + 1);

      expect(
        () => parseImport(many, newId: counterIds()),
        throwsA(isA<SourceTooLargeError>().having(
          (error) => error.message,
          'message',
          contains('$maxEntries'),
        )),
      );
    });
  });

  group('one bad entry costs one entry (invariant 3)', () {
    test('an illegal move rejects its own chapter and no other', () {
      const source = '''
[Event "Fine"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

1. Kc6

[Event "Broken"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

1. Kc6 Kd8 2. Qh8

[Event "Also fine"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

1. Ke6
''';
      final outcome = parseImport(source, newId: counterIds());

      expect(outcome.positions, hasLength(2));
      expect(outcome.rejections, hasLength(1));
      expect(outcome.rejections.first.reference, 'Broken');
      expect(outcome.rejections.first.reason, RejectionReason.illegalMove);
    });

    test('an entry with no moves is imported, awaiting an engine (005 FR-001)',
        () {
      const source = '''
[Event "Position only"]
[FEN "3k4/8/3K4/3P4/8/8/8/8 w - - 0 1"]

*
''';
      final outcome = parseImport(source, newId: counterIds());

      expect(outcome.rejections, isEmpty);
      expect(outcome.positions.single.solutionSource, SolutionSource.none,
          reason: 'the parser knows no engine exists; the import service is '
              'what asks one and upgrades this to `engine`');
    });

    test('an entry with no legal move is rejected (005 FR-004)', () {
      // Nothing to calculate. Importing it would open a board the player cannot
      // move on — a trap found after training starts, rather than at import
      // where the report can explain it.
      const source = '''
[Event "Already over"]
[FEN "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"]

*
''';
      final outcome = parseImport(source, newId: counterIds());

      expect(outcome.positions, isEmpty);
      expect(outcome.rejections.single.reason, RejectionReason.noLegalMoves);
    });

    test('an unnamed entry is referenced by its ordinal', () {
      const source = '''
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4 e5 2. Ke2 Qh4 3. Kd8
''';
      final outcome = parseImport(source, newId: counterIds());

      expect(outcome.rejections.single.reference, 'entry 1 of 1');
    });
  });
}

/// True when anywhere at or below [path] a position offers more than one move.
bool _branches(VariationTree tree, MovePath path) {
  final children = tree.childrenAt(path);
  if (children.length > 1) return true;
  for (var i = 0; i < children.length; i++) {
    if (_branches(tree, path.child(i))) return true;
  }
  return false;
}
