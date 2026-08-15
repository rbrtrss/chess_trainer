import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/ui/account/account_bar.dart';
import 'package:chess_trainer/ui/history/history_screen.dart';
import 'package:chess_trainer/ui/library/collection_list_screen.dart';
import 'package:chess_trainer/ui/library/import_screen.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
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
    final positions = ref.watch(availablePositionsProvider);
    final resumable = ref.watch(resumeCandidateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Trainer'),
        actions: [
          // Only ever reachable from setup. The training screen gains no new
          // affordance, which is the cheapest way to keep history away from a
          // player who is still calculating (FR-019).
          IconButton(
            key: const Key('open-import'),
            icon: const Icon(Icons.library_add),
            tooltip: 'Import positions',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const ImportScreen(),
              ),
            ),
          ),
          IconButton(
            key: const Key('open-library'),
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Positions',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const CollectionListScreen(),
              ),
            ),
          ),
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
      // Pinned below the body, so it survives both of this screen's states —
      // the setup form and the empty library — without being written twice, and
      // does not scroll away (FR-001, 004 research D4).
      bottomNavigationBar: const AccountBar(),
      body: SafeArea(
        child: positions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load your positions.\n\n$error'),
            ),
          ),
          data: (available) {
            // An empty library is a normal state now that the samples are
            // deletable (FR-039). It gets a way forward rather than a broken
            // setup form with a zero-length slider.
            if (available.isEmpty) return const _EmptyLibrary();

            final maximum = available.length;
            final length = _length > maximum ? maximum : _length;

            // While the lookup is in flight the screen shows the setup form
            // without the prompt; `SessionFlow` holds the first frame back
            // until it resolves, so this is only reached if it is slow.
            final stored = resumable.value;

            final collections = ref.watch(collectionsProvider).value ??
                const IList<Collection>.empty();
            final chosen = ref.watch(chosenCollectionProvider).value;

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
                  // Which collection this session draws from (FR-029). Shown
                  // here and on no training screen: a collection called
                  // "Back-rank mates" is evidence exactly as a chapter title
                  // is (FR-026).
                  if (collections.length > 1)
                    DropdownButtonFormField<String>(
                      key: const Key('collection-chooser'),
                      initialValue: chosen?.id,
                      decoration: const InputDecoration(
                        labelText: 'Positions from',
                      ),
                      items: [
                        for (final collection in collections)
                          DropdownMenuItem<String>(
                            key: Key('collection-option-${collection.id}'),
                            value: collection.id,
                            child: Text(
                              '${collection.name} '
                              '(${collection.positionCount})',
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        ref
                            .read(selectedCollectionProvider.notifier)
                            .choose(id);
                        setState(() {});
                      },
                    )
                  else if (chosen != null)
                    Text('Positions from ${chosen.name}',
                        key: const Key('collection-name-label'),
                        textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  // A collection with fewer positions than asked for runs
                  // shorter rather than repeating one (FR-031): seeing the
                  // same position twice in a session would be its own kind of
                  // hint.
                  if (_length > maximum)
                    Text(
                      'This collection has $maximum '
                      '${maximum == 1 ? 'position' : 'positions'}, so the '
                      'session will be that long.',
                      key: const Key('short-collection-notice'),
                      textAlign: TextAlign.center,
                    ),
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

/// What the setup screen shows when there is nothing to train (FR-039).
///
/// Reachable in one way only: the player deleted every collection, including
/// the samples. That is allowed, so it needs an answer better than an empty
/// list or an error.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('empty-library'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'There are no positions to train.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Import a PGN file — a study exported from Lichess, or any file '
              'of positions.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('import-from-empty'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const ImportScreen(),
                ),
              ),
              child: const Text('Import positions'),
            ),
          ],
        ),
      ),
    );
  }
}
