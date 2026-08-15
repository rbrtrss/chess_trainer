/// What an import added, and what it refused.
///
/// The refusals are the interesting half. A real Lichess study often yields
/// nine chapters rejected for the same reason — Lichess omits `[FEN]` for a
/// chapter that starts from the standard position, so every "analyse this game"
/// chapter fails the rule that a trainable position must say where it starts.
/// Nine near-identical lines is a wall, not a report, and a player reading it
/// concludes the app is broken. So they are grouped, and the common case is
/// explained in a sentence (003 research D10).
library;

import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:flutter/material.dart';

class ImportReportView extends StatelessWidget {
  const ImportReportView({required this.outcome, super.key});

  final ImportOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = outcome.rejectionsByReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          outcome.positions.isEmpty
              ? 'Nothing here could be trained.'
              : '${outcome.positions.length} '
                  '${outcome.positions.length == 1 ? 'position' : 'positions'} '
                  'added.',
          key: const Key('import-added-count'),
          style: theme.textTheme.titleMedium,
        ),
        if (outcome.rejections.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${outcome.rejections.length} of the '
            '${outcome.entryCount} entries could not be used:',
            key: const Key('import-rejected-count'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          for (final reason in grouped.keys)
            _ReasonGroup(reason: reason, entries: grouped[reason]!.toList()),
        ],
      ],
    );
  }
}

class _ReasonGroup extends StatelessWidget {
  const _ReasonGroup({required this.reason, required this.entries});

  final RejectionReason reason;
  final List<RejectedEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = entries.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count ${count == 1 ? 'entry' : 'entries'} '
            '${reason.summaryFor(count)}.',
            key: Key('rejection-group-${reason.name}'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (reason == RejectionReason.noStartingPosition)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'A chapter that starts from the opening position does not say '
                'which moment is the exercise, so there is nothing to '
                'calculate from. Studies of whole games are mostly like this.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          // Named individually so the player can find them in their own file.
          // Capped, because the point of grouping is not to print a wall.
          for (final entry in entries.take(5))
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text('• ${entry.reference}',
                  style: theme.textTheme.bodySmall),
            ),
          if (entries.length > 5)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text('• and ${entries.length - 5} more',
                  style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
