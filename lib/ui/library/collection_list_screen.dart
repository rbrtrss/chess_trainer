/// The library: what has been imported, and what can be done with it.
///
/// Not a training screen, so names, origins and dates are shown freely.
library;

import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/ui/library/import_screen.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CollectionListScreen extends ConsumerWidget {
  const CollectionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Positions'),
        actions: [
          IconButton(
            key: const Key('open-import-from-library'),
            icon: const Icon(Icons.library_add),
            tooltip: 'Import positions',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const ImportScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: collections.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not read your library.\n\n$error'),
            ),
          ),
          data: (all) => ListView(
            children: [
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    key: Key('library-empty'),
                    'Nothing imported yet. Import a PGN file, or a study from '
                    'Lichess.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final collection in all)
                _CollectionTile(collection: collection),
              // The Lichess account used to sit below a divider here. It moved
              // to the home screen in feature 004: the account is a property of
              // the app, not of the library, and two controls for one account
              // invite disagreement about which is authoritative (FR-012).
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: Key('collection-${collection.id}'),
      title: Text(collection.name),
      subtitle: Text(
        '${_originText(collection.origin)} · '
        '${collection.positionCount} '
        '${collection.positionCount == 1 ? 'position' : 'positions'} · '
        'imported ${_when(collection.importedAt)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('rename-${collection.id}'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () => _rename(context, ref),
          ),
          IconButton(
            key: Key('delete-${collection.id}'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  String _originText(CollectionOrigin origin) => switch (origin) {
        BundledOrigin() => 'Included with the app',
        FileOrigin(:final fileName) => fileName,
        LichessOrigin(:final studyName) => 'Lichess: $studyName',
      };

  String _when(DateTime moment) {
    final local = moment.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: collection.name);
    final renamed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('rename-dialog'),
        title: const Text('Rename collection'),
        content: TextField(
          key: const Key('rename-field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('rename-confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (renamed == null || renamed.isEmpty) return;
    await ref.read(collectionRepositoryProvider).rename(collection.id, renamed);
    ref.invalidate(collectionsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Does the unfinished session depend on this collection? If it does,
    // deleting forfeits it, and that carries the same warning as abandoning
    // (FR-038) — the player is giving up answers, not just tidying up.
    // Awaited, not peeked at: `.value` is null until the provider has
    // resolved, and a warning that depends on a race is a warning that
    // sometimes does not appear.
    final inProgress = await ref.read(resumeCandidateProvider.future);
    final affected = inProgress != null &&
        (await ref
                .read(collectionRepositoryProvider)
                .positionsIn(collection.id))
            .map((position) => position.id)
            .toSet()
            .intersection(
              inProgress.positions
                  .map((snapshot) => snapshot.positionId)
                  .toSet(),
            )
            .isNotEmpty;

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-collection-warning'),
        title: Text('Delete "${collection.name}"?'),
        content: Text(
          affected
              ? 'Its positions can no longer be trained, and this cannot be '
                  'undone.\n\n'
                  'The unfinished session uses this collection, so it ends '
                  'here and no answers will be shown — not for the positions '
                  'you have already committed, and not for the rest.'
              : 'Its positions can no longer be trained, and this cannot be '
                  'undone.\n\n'
                  'Sessions you have already played stay readable: each keeps '
                  'its own copy of what it showed you.',
        ),
        actions: [
          TextButton(
            key: const Key('delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (affected) {
      await ref.read(sessionRepositoryProvider).discardInProgress();
      ref.invalidate(resumeCandidateProvider);
    }
    await ref.read(collectionRepositoryProvider).delete(collection.id);
    ref
      ..invalidate(collectionsProvider)
      ..invalidate(availablePositionsProvider);
  }
}

