import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/ui/review/review_screen.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/session/session_setup_screen.dart';
import 'package:chess_trainer/ui/training/training_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows whichever screen the session's phase calls for.
///
/// The phases are screens, not routes: there is no back button out of training
/// and into a result, because there is no result to go back to.
class SessionFlow extends ConsumerWidget {
  const SessionFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    if (session == null) {
      // The resume lookup is held for, rather than shown around, so the app
      // does not open on a session-less setup screen that a moment later grows
      // an offer to continue (SC-002). One local read of one row: if this is
      // ever slow enough to see, the database is the problem, not the wait.
      final resumable = ref.watch(resumeCandidateProvider);
      if (resumable.isLoading) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(key: Key('resume-lookup')),
          ),
        );
      }
    }

    return switch (session?.phase) {
      null || SessionPhase.setup => const SessionSetupScreen(),
      SessionPhase.training => const TrainingScreen(),
      SessionPhase.review || SessionPhase.complete => const ReviewScreen(),
      SessionPhase.abandoned => const SessionSetupScreen(),
    };
  }
}
