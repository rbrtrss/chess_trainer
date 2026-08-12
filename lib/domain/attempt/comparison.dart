import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:meta/meta.dart';

/// How far the user's primary line agreed with the solution's main line.
///
/// **Advisory only** (FR-027). The self-grade outranks this, and the reason is
/// structural rather than polite: no engine evaluates anything here, so this
/// type can say where two lines parted company and nothing whatever about
/// which was better.
@immutable
class ComparisonResult {
  const ComparisonResult({
    required this.agreementLength,
    required this.solutionLength,
    this.divergence,
  });

  /// Plies for which the attempt's primary line matched the solution's.
  ///
  /// Never greater than [solutionLength]: an attempt that calculated ten plies
  /// against a four-ply solution agreed for four, and the extra six are neither
  /// credited nor faulted.
  final int agreementLength;

  /// Plies in the solution's main line — the denominator in "matched 4 of 6".
  final int solutionLength;

  /// Where the two first differed, or null if they never did.
  final Divergence? divergence;

  /// The attempt stopped early rather than going wrong.
  ///
  /// This is a different thing from a mistake and must never be shown as one.
  bool get ranShort => divergence == null && agreementLength < solutionLength;

  /// The attempt followed the solution all the way.
  bool get isComplete =>
      divergence == null && agreementLength == solutionLength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComparisonResult &&
          agreementLength == other.agreementLength &&
          solutionLength == other.solutionLength &&
          divergence == other.divergence;

  @override
  int get hashCode =>
      Object.hash(agreementLength, solutionLength, divergence);

  @override
  String toString() =>
      'ComparisonResult($agreementLength/$solutionLength, $divergence)';
}

/// The first ply at which the attempt and the solution part company.
@immutable
class Divergence {
  const Divergence({
    required this.ply,
    required this.playedSan,
    required this.expectedSan,
  });

  /// One-based ply number, so it reads the way a move list does.
  final int ply;

  /// What the user played there.
  final String playedSan;

  /// What the solution records there. Not "the right move" — the recorded one.
  final String expectedSan;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Divergence &&
          ply == other.ply &&
          playedSan == other.playedSan &&
          expectedSan == other.expectedSan;

  @override
  int get hashCode => Object.hash(ply, playedSan, expectedSan);

  @override
  String toString() => 'Divergence(ply $ply: $playedSan vs $expectedSan)';
}

/// Walks the two primary lines in lockstep and reports where they part.
///
/// **Only primary lines are examined** (FR-024). A user's alternative branch is
/// never compared against anything, because there is nothing here that could
/// judge it: the solution records one intended line and some alternatives, not
/// a verdict on every move a person might consider.
ComparisonResult compareToSolution(
  VariationTree attempt,
  VariationTree solution,
) {
  final played = attempt.primaryLine;
  final expected = solution.primaryLine;
  final solutionLength = expected.length;

  final shared = played.length < expected.length ? played.length : expected.length;
  for (var ply = 0; ply < shared; ply++) {
    if (played[ply].san != expected[ply].san) {
      return ComparisonResult(
        agreementLength: ply,
        solutionLength: solutionLength,
        divergence: Divergence(
          ply: ply + 1,
          playedSan: played[ply].san,
          expectedSan: expected[ply].san,
        ),
      );
    }
  }

  // No mismatch. The attempt either stopped early, ended level, or ran on past
  // the end of the solution — and in the last case the agreement is capped,
  // because there is nothing recorded to agree with beyond that point.
  return ComparisonResult(
    agreementLength: shared,
    solutionLength: solutionLength,
  );
}
