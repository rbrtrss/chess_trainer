import 'package:chess_trainer/domain/attempt/comparison.dart';
import 'package:flutter/material.dart';

/// Reports how far the user's primary line agreed with the solution's main line
/// (FR-023).
///
/// The wording here matters more than it looks. This is a *measurement of one
/// line against one line*, and it is advisory: the self-grade outranks it
/// (FR-027). If it ever reads as a verdict, users will treat it as a score and
/// the self-grade becomes ceremony — so there is no colour, no icon, no
/// percentage and no praise, and running short is worded as stopping rather
/// than as being wrong.
class MatchIndicator extends StatelessWidget {
  const MatchIndicator({super.key, required this.comparison});

  final ComparisonResult comparison;

  String get _text {
    final agreement = comparison.agreementLength;
    final total = comparison.solutionLength;

    if (total == 0) return 'No solution line was recorded to compare against.';

    if (comparison.divergence != null) {
      final divergence = comparison.divergence!;
      return 'Your line followed the solution for $agreement of $total moves, '
          'then went a different way: you played ${divergence.playedSan} '
          'where the solution has ${divergence.expectedSan}.';
    }

    if (comparison.ranShort) {
      return 'Your line followed the solution for $agreement of $total moves, '
          'and stopped there.';
    }

    return 'Your line followed the solution for all $total moves.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('match-indicator'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_text, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            'This compares main lines only. It says nothing about the other '
            'branches you looked at — your own grade is the record that counts.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
