import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_projection.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/training/analysis_editor.dart';
import 'package:chess_trainer/ui/training/analysis_editor_state.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The training phase.
///
/// This screen is given a [TrainingProjection] and has no other way to reach a
/// position. It cannot show a title, a theme, a rating, a goal, or the length
/// of the solution (FR-003) because it has none of them — that is research D5
/// doing its work, and it is why this file is short.
class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key});

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  /// When the user arrived at this position, for the attempt's duration.
  DateTime _startedAt = DateTime.now();
  String? _positionId;

  Future<void> _commit(TrainingProjection projection) async {
    final tree = ref.read(analysisEditorProvider).tree;
    try {
      await ref.read(sessionControllerProvider.notifier).commit(
            tree,
            duration: DateTime.now().difference(_startedAt),
          );
    } on StorageWriteError catch (error) {
      // The session does not move on, and the player is told. Letting them
      // believe a committed analysis was stored when it was not is the one
      // failure this feature must never produce (FR-024).
      _reportStorageFailure(error);
    }
  }

  void _reportStorageFailure(StorageWriteError error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('storage-failure'),
        content: Text(
          'This device could not save your analysis, so this position has not '
          'been committed. (${error.operation})',
        ),
      ),
    );
  }

  /// Warns before abandoning that the review is forfeited (FR-019).
  ///
  /// The warning is the point: leaving is cheap, but the answers are the thing
  /// being given up, and a user who leaves by accident loses the session.
  Future<void> _confirmAbandon() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('abandon-warning'),
        title: const Text('Abandon this session?'),
        content: const Text(
          'The session ends here and no answers will be shown — not for the '
          'positions you have already committed, and not for this one.',
        ),
        actions: [
          TextButton(
            key: const Key('abandon-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            key: const Key('abandon-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        await ref.read(sessionControllerProvider.notifier).abandon();
      } on StorageWriteError catch (error) {
        _reportStorageFailure(error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projection = ref.watch(currentProjectionProvider);
    if (projection == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    // A new position restarts the clock. No result of the previous one appears
    // in between (FR-016): this is the same screen, showing the next board.
    if (_positionId != projection.positionId) {
      _positionId = projection.positionId;
      _startedAt = DateTime.now();
    }

    return Scaffold(
      appBar: AppBar(
        // A plain count, fixed in style, that never varies with performance
        // (FR-017).
        title: Text(
          '${projection.displayNumber} of ${projection.sessionLength}',
          key: const Key('session-progress'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('abandon-session'),
            icon: const Icon(Icons.close),
            tooltip: 'Abandon session',
            onPressed: _confirmAbandon,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TurnIndicator(),
              const SizedBox(height: 8),
              Expanded(
                child: AnalysisEditor(orientation: projection.sideToMove),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('commit-attempt'),
                // Always enabled: committing with nothing entered is a valid
                // answer (FR-014), not an error to be prevented.
                onPressed: () => _commit(projection),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one thing the user is told about the position.
///
/// It tracks the board rather than the position's starting turn, and that is
/// the point: it is the answer to research's open item on SC-005, where a
/// first-time user has to understand that entering the opponent's reply is
/// expected of them rather than a malfunction. A label frozen at "White to
/// move" while the board waits for Black would teach the opposite.
///
/// Following the board leaks nothing. Whose turn it is after a move is a
/// consequence of the move the user just made, not of whether it was a good
/// one.
class _TurnIndicator extends ConsumerWidget {
  const _TurnIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final side = ref.watch(analysisEditorProvider).position.turn;

    return Text(
      side == Side.white ? 'White to move' : 'Black to move',
      key: const Key('turn-indicator'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16),
    );
  }
}
