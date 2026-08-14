import 'package:chess_trainer/data/session_repository.dart';
import 'package:flutter/material.dart';

/// The offer to carry on with an unfinished session (FR-006).
///
/// **This is where the player is told that the analysis they were part way
/// through was not kept** (FR-003). It has to be here rather than on the
/// training screen, because a resumed training screen must be identical to an
/// uninterrupted one at the same point (FR-008, SC-003) — a banner that appears
/// only after a resume is exactly the kind of difference that requirement
/// forbids. Saying it once, before training resumes, satisfies both: an empty
/// board reads as a known consequence rather than as lost work.
class ResumePrompt extends StatelessWidget {
  const ResumePrompt({
    required this.stored,
    required this.onContinue,
    required this.onStartFresh,
    super.key,
  });

  final StoredSession stored;

  final VoidCallback onContinue;

  /// Discards the unfinished session and starts a new one, under the same
  /// warning as abandoning (FR-011).
  final VoidCallback onStartFresh;

  @override
  Widget build(BuildContext context) {
    final committed = stored.attempts.length;
    final total = stored.positions.length;
    final position = stored.record.currentIndex + 1;

    return Card(
      key: const Key('resume-prompt'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You have a session in progress',
              key: const Key('resume-title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              // Facts about the session, and nothing about how it is going.
              'Position $position of $total, '
              '${committed == 1 ? '1 answer' : '$committed answers'} '
              'committed.',
              key: const Key('resume-summary'),
            ),
            const SizedBox(height: 8),
            const Text(
              'The analysis you had in progress was not kept, so that position '
              'starts again from an empty board. Everything you committed is '
              'still there.',
              key: Key('resume-uncommitted-notice'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('resume-continue'),
              onPressed: onContinue,
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('resume-start-fresh'),
              onPressed: onStartFresh,
              child: const Text('Start a new session instead'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The warning shown before an unfinished session is thrown away.
///
/// Deliberately worded in the same terms as abandoning, because it is the same
/// loss: the answers for that session are forfeited and will never be shown
/// (FR-010, FR-011).
Future<bool> confirmDiscardInProgress(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('discard-warning'),
      title: const Text('Discard the session in progress?'),
      content: const Text(
        'The unfinished session ends here and no answers will be shown — not '
        'for the positions you have already committed, and not for the rest.',
      ),
      actions: [
        TextButton(
          key: const Key('discard-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep it'),
        ),
        TextButton(
          key: const Key('discard-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
