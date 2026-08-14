import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/ui/history/history_screen.dart';
import 'package:chess_trainer/ui/session/resume_prompt.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a session is chosen and started.
///
/// The only choice offered is how many positions to work through. There is
/// nothing to pick between — no difficulty, no theme — because choosing by
/// theme would be choosing by answer.
///
/// It is also where an unfinished session is offered back (FR-006), and where
/// starting a new one while another is unfinished is warned about in the same
/// terms as abandoning (FR-010).
class SessionSetupScreen extends ConsumerStatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  ConsumerState<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends ConsumerState<SessionSetupScreen> {
  int _length = 3;

  /// Resumes the stored session (FR-007).
  void _continueStored(StoredSession stored) {
    ref.read(sessionControllerProvider.notifier).resume(stored);
  }

  /// Starts a fresh session, discarding an unfinished one under warning.
  Future<void> _start(
    IList<TrainingPosition> available,
    int length, {
    required bool discardFirst,
  }) async {
    if (discardFirst) {
      final confirmed = await confirmDiscardInProgress(context);
      if (!confirmed) return;
      await ref.read(sessionRepositoryProvider).discardInProgress();
      ref.invalidate(resumeCandidateProvider);
    }

    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .start(available, length: length);
    } on StorageWriteError catch (error) {
      _reportStorageFailure(error);
    }
  }

  /// Tells the player their work could not be stored, rather than letting them
  /// believe it was (FR-024).
  void _reportStorageFailure(StorageWriteError error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('storage-failure'),
        content: Text(
          'This device could not save the session, so it has not started. '
          '(${error.operation})',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positions = ref.watch(bundledPositionsProvider);
    final resumable = ref.watch(resumeCandidateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Trainer'),
        actions: [
          // Only ever reachable from setup. The training screen gains no new
          // affordance, which is the cheapest way to keep history away from a
          // player who is still calculating (FR-019).
          IconButton(
            key: const Key('open-history'),
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const HistoryScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: positions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load the bundled positions.\n\n$error'),
            ),
          ),
          data: (available) {
            final maximum = available.length;
            final length = _length > maximum ? maximum : _length;

            // While the lookup is in flight the screen shows the setup form
            // without the prompt; `SessionFlow` holds the first frame back
            // until it resolves, so this is only reached if it is slow.
            final stored = resumable.value;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stored != null) ...[
                    ResumePrompt(
                      stored: stored,
                      onContinue: () => _continueStored(stored),
                      onStartFresh: () =>
                          _start(available, length, discardFirst: true),
                    ),
                    const SizedBox(height: 32),
                  ],
                  const Text(
                    'You will see each position once, with only the side to '
                    'move given. Nothing is revealed until the whole session '
                    'is over.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Text('Positions: $length',
                      key: const Key('session-length'),
                      textAlign: TextAlign.center),
                  Slider(
                    key: const Key('session-length-slider'),
                    value: length.toDouble(),
                    min: 1,
                    max: maximum.toDouble(),
                    divisions: maximum > 1 ? maximum - 1 : null,
                    label: '$length',
                    onChanged: (value) =>
                        setState(() => _length = value.round()),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    key: const Key('start-session'),
                    onPressed: () => _start(
                      available,
                      length,
                      discardFirst: stored != null,
                    ),
                    child: const Text('Start'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
