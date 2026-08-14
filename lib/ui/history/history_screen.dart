import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/session/session_record.dart';
import 'package:chess_trainer/ui/history/past_review_screen.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many sessions are read at a time.
///
/// A page rather than the lot: the list must stay usable, and opening it must
/// not delay the app, with hundreds of sessions stored (SC-009).
const int historyPageSize = 50;

/// Past sessions (FR-013).
///
/// Each row says when the session happened and how many positions it had, and
/// nothing about how any of them went. That is not modesty — a list that ranked
/// or coloured sessions by performance would be evidence about the positions
/// they contained, and the player may meet those positions again.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _limit = historyPageSize;

  Future<void> _confirmDeleteEverything() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-everything-warning'),
        title: const Text('Delete everything?'),
        content: const Text(
          'Every session, every analysis you committed and every grade you '
          'recorded will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('delete-everything-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            key: const Key('delete-everything-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false)) return;

    try {
      await ref.read(sessionRepositoryProvider).deleteEverything();
    } on StorageWriteError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('storage-failure'),
          content: Text('Nothing was deleted: ${error.operation} failed.'),
        ),
      );
      return;
    }

    ref.invalidate(sessionHistoryProvider);
    ref.invalidate(resumeCandidateProvider);
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(sessionHistoryProvider(_limit));

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            key: const Key('delete-everything'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete everything',
            onPressed: _confirmDeleteEverything,
          ),
        ],
      ),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('The history could not be read.\n\n$error'),
            ),
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No finished sessions yet.',
                    key: Key('history-empty'),
                  ),
                ),
              );
            }

            final canLoadMore = sessions.length >= _limit;

            return ListView.separated(
              key: const Key('history-list'),
              itemCount: sessions.length + (canLoadMore ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == sessions.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton(
                      key: const Key('history-show-more'),
                      onPressed: () =>
                          setState(() => _limit += historyPageSize),
                      child: const Text('Show older sessions'),
                    ),
                  );
                }
                return _SessionTile(record: sessions[index]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final abandoned = record.status == SessionStatus.abandoned;

    return ListTile(
      key: Key('history-session-${record.id}'),
      title: Text(_formatDate(record.startedAt.toLocal())),
      subtitle: Text(
        '${record.positionIds.length} '
        '${record.positionIds.length == 1 ? 'position' : 'positions'}'
        '${abandoned ? ' · abandoned' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => PastReviewScreen(sessionId: record.id),
        ),
      ),
    );
  }
}

/// Local time, in the device's own reckoning (spec assumption).
String _formatDate(DateTime local) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hour:$minute';
}
