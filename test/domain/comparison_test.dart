import 'package:chess_trainer/domain/attempt/comparison.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tree_helpers.dart';

/// Invariants 4-6. The three outcomes the spec's edge cases insist stay
/// distinguishable are *diverged*, *ran short*, and *ran long*; collapsing any
/// two of them would tell a user they were wrong when they were merely brief.
void main() {
  final solution = treeFromLine(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']);

  group('invariant 4: diverged, ran short and ran long stay distinct', () {
    test('a differing move is a divergence at that ply', () {
      final attempt = treeFromLine(['e4', 'e5', 'Bc4']);

      final result = compareToSolution(attempt, solution);

      expect(result.agreementLength, 2);
      expect(result.solutionLength, 6);
      expect(result.divergence,
          const Divergence(ply: 3, playedSan: 'Bc4', expectedSan: 'Nf3'));
      expect(result.ranShort, isFalse);
      expect(result.isComplete, isFalse);
    });

    test('a first move that differs diverges at ply 1', () {
      final attempt = treeFromLine(['d4']);

      final result = compareToSolution(attempt, solution);

      expect(result.agreementLength, 0);
      expect(result.divergence!.ply, 1);
      expect(result.divergence!.playedSan, 'd4');
      expect(result.divergence!.expectedSan, 'e4');
    });

    test('stopping early is never reported as a divergence', () {
      final attempt = treeFromLine(['e4', 'e5', 'Nf3']);

      final result = compareToSolution(attempt, solution);

      expect(result.divergence, isNull,
          reason: 'stopping is not a wrong move and must not look like one');
      expect(result.agreementLength, 3);
      expect(result.solutionLength, 6);
      expect(result.ranShort, isTrue);
      expect(result.isComplete, isFalse);
    });

    test('running past the solution caps the agreement and faults nothing', () {
      final attempt =
          treeFromLine(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6']);

      final result = compareToSolution(attempt, solution);

      expect(result.agreementLength, 6,
          reason: 'capped at the solution length — there is nothing beyond it '
              'to agree or disagree with');
      expect(result.solutionLength, 6);
      expect(result.divergence, isNull);
      expect(result.isComplete, isTrue);
      expect(result.ranShort, isFalse);
    });

    test('matching the solution exactly is complete', () {
      final result = compareToSolution(solution, solution);

      expect(result.agreementLength, 6);
      expect(result.isComplete, isTrue);
      expect(result.divergence, isNull);
    });
  });

  group('invariant 5: the empty attempt', () {
    test('agrees on nothing and diverges nowhere', () {
      final result =
          compareToSolution(VariationTree.empty(Chess.initial), solution);

      expect(result.agreementLength, 0);
      expect(result.solutionLength, 6);
      expect(result.divergence, isNull,
          reason: '"I have no idea" is an answer, not a mistake');
      expect(result.ranShort, isTrue);
    });

    test('an empty solution leaves nothing to measure', () {
      final result = compareToSolution(
        treeFromLine(['e4']),
        VariationTree.empty(Chess.initial),
      );

      expect(result.agreementLength, 0);
      expect(result.solutionLength, 0);
      expect(result.divergence, isNull);
      expect(result.isComplete, isTrue);
    });
  });

  group('invariant 6: non-primary branches are never examined', () {
    test('extra branches in the attempt change nothing', () {
      final plain = treeFromLine(['e4', 'e5', 'Nf3']);
      var branched = plain;
      // Two alternatives the solution has never heard of.
      branched = addLine(branched, MovePath.root, ['d4']);
      branched = addLine(branched, pathOfDepth(2), ['Bc4', 'Bc5']);

      expect(compareToSolution(branched, solution),
          compareToSolution(plain, solution));
    });

    test('extra branches in the solution change nothing', () {
      final attempt = treeFromLine(['e4', 'e5', 'Bc4']);
      var richSolution = solution;
      richSolution = addLine(richSolution, MovePath.root, ['d4', 'd5']);
      richSolution = addLine(richSolution, pathOfDepth(2), ['Bc4']);

      expect(compareToSolution(attempt, richSolution),
          compareToSolution(attempt, solution));
    });

    test('a user branch that happens to be the solution is not credited', () {
      // The solution's move is present, but as an alternative rather than the
      // primary line. The match indicator measures primary lines only, which is
      // exactly why the user controls which line is primary (FR-013).
      var attempt = treeFromLine(['e4', 'e5', 'Bc4']);
      attempt = addLine(attempt, pathOfDepth(2), ['Nf3', 'Nc6']);

      final result = compareToSolution(attempt, solution);

      expect(result.divergence!.playedSan, 'Bc4');
      expect(result.agreementLength, 2);

      // Promote it, and the same tree measures differently.
      final promoted = attempt.promote(pathOfDepth(2).child(1));
      expect(compareToSolution(promoted, solution).agreementLength, 4);
    });
  });

  group('value semantics', () {
    test('results with the same numbers are equal', () {
      expect(
        compareToSolution(treeFromLine(['e4', 'e5']), solution),
        compareToSolution(treeFromLine(['e4', 'e5']), solution),
      );
    });
  });
}
