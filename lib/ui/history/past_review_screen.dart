import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/session/session_record.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/ui/review/review_screen.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A finished session, reopened (FR-014).
///
/// It shows the *same* review the player saw when the session ended, because it
/// is the same screen reading the same shape of session — rebuilt from the
/// snapshot the session stored rather than from the bundled positions, so a
/// later app update cannot rewrite what they were shown and graded against
/// (FR-015, SC-005).
class PastReviewScreen extends ConsumerWidget {
  const PastReviewScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final past = ref.watch(pastSessionProvider(sessionId));

    return past.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _Unavailable(message: 'That session could not be '
          'read.\n\n$error'),
      data: (stored) {
        if (stored == null) {
          return const _Unavailable(message: 'That session is no longer here.');
        }
        if (stored.record.status == SessionStatus.abandoned) {
          return _AbandonedSession(record: stored.record);
        }
        return _PastReview(stored: stored);
      },
    );
  }
}

/// The real review screen, over the stored session.
class _PastReview extends ConsumerWidget {
  const _PastReview({required this.stored});

  final StoredSession stored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _PastSessionController(stored),
        ),
      ],
      child: const _PopWhenFinished(child: ReviewScreen()),
    );
  }
}

/// Drives a past session's review.
///
/// Grades recorded here are written against the past session, replacing
/// whatever grade it held for that position (FR-017).
class _PastSessionController extends SessionController {
  _PastSessionController(this.stored);

  final StoredSession stored;

  @override
  TrainingSession? build() {
    adoptStoredSession(stored.id);
    return pastSessionFrom(stored);
  }
}

/// The review screen's Finish button clears the session; here that means "done
/// reading", so the route goes back to the history.
class _PopWhenFinished extends ConsumerWidget {
  const _PopWhenFinished({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next == null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return child;
  }
}

/// What an abandoned session shows: that it happened, and nothing else.
///
/// Abandoning forfeits the answers permanently rather than until the process
/// dies (FR-016). There is nothing to hide here, because the repository handed
/// this screen no solution, note or metadata to render.
class _AbandonedSession extends StatelessWidget {
  const _AbandonedSession({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abandoned session')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'You abandoned this session of ${record.positionIds.length} '
                'positions.',
                key: const Key('abandoned-summary'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Its answers were forfeited and are not kept — not for the '
                'positions committed before it ended, and not for the rest.',
                key: Key('abandoned-notice'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message,
                key: const Key('session-unavailable'),
                textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

/// Rebuilds a finished session for reading (FR-014).
///
/// Always in [SessionPhase.complete]: it *is* complete, and the review screen's
/// Finish button is then the way back out. Re-grading is allowed from here, and
/// changes which grade counts (FR-017).
TrainingSession pastSessionFrom(StoredSession stored) {
  final positions = stored.positions
      .map((snapshot) => snapshot.toTrainingPosition())
      .toIList();

  return TrainingSession(
    positions: positions,
    attempts: stored.attempts,
    grades: stored.grades,
    phase: SessionPhase.complete,
    currentIndex: 0,
  );
}
