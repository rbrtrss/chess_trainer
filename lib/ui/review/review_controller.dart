import 'package:chess_trainer/domain/attempt/comparison.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// Which of the two trees the review cursor is in.
enum ReviewSide { attempt, solution }

/// Where the reviewer is looking: one node, in one of the two trees.
@immutable
class ReviewCursor {
  const ReviewCursor({required this.side, required this.path});

  static const ReviewCursor start =
      ReviewCursor(side: ReviewSide.solution, path: MovePath.root);

  final ReviewSide side;
  final MovePath path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewCursor && side == other.side && path == other.path;

  @override
  int get hashCode => Object.hash(side, path);
}

/// Drives review navigation.
///
/// Resets to the start of the solution whenever the reviewed position changes,
/// so arriving at a position always begins from its board rather than from
/// wherever the last one was left.
class ReviewCursorNotifier extends Notifier<ReviewCursor> {
  @override
  ReviewCursor build() {
    ref.watch(reviewedPositionProvider.select((position) => position?.id));
    return ReviewCursor.start;
  }

  void select(ReviewSide side, MovePath path) {
    state = ReviewCursor(side: side, path: path);
  }

  /// Steps back one ply within the tree the cursor is in.
  void stepBackward() {
    final parent = state.path.parent;
    if (parent == null) return;
    state = ReviewCursor(side: state.side, path: parent);
  }

  /// Steps forward along the primary continuation of the current tree.
  void stepForward(VariationTree tree) {
    if (tree.childrenAt(state.path).isEmpty) return;
    state = ReviewCursor(side: state.side, path: state.path.child(0));
  }

  void reset() {
    state = ReviewCursor(side: state.side, path: MovePath.root);
  }
}

final reviewCursorProvider =
    NotifierProvider<ReviewCursorNotifier, ReviewCursor>(
  ReviewCursorNotifier.new,
  // Declared so that a nested scope overriding the session — which is how a
  // past review is reopened from the history — gets its own cursor rather than
  // sharing the live session's.
  dependencies: [reviewedPositionProvider],
);

/// The position currently under review, with everything about it — this is the
/// phase where that is allowed (FR-025).
final reviewedPositionProvider = Provider<TrainingPosition?>(dependencies: [
  sessionControllerProvider
], (ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session == null || session.phase.withholdsFeedback) return null;
  if (session.phase == SessionPhase.abandoned) return null;
  return session.currentPosition;
});

/// The tree the user committed for the position under review.
final reviewedAttemptTreeProvider = Provider<VariationTree?>(dependencies: [
  sessionControllerProvider,
  reviewedPositionProvider
], (ref) {
  final session = ref.watch(sessionControllerProvider);
  final position = ref.watch(reviewedPositionProvider);
  if (session == null || position == null) return null;
  return session.attemptFor(position.id)?.tree ??
      VariationTree.empty(position.initialPosition);
});

/// The advisory measurement (FR-023, FR-027).
final comparisonProvider = Provider<ComparisonResult?>(dependencies: [
  reviewedPositionProvider,
  reviewedAttemptTreeProvider
], (ref) {
  final position = ref.watch(reviewedPositionProvider);
  final attempt = ref.watch(reviewedAttemptTreeProvider);
  if (position == null || attempt == null) return null;
  return compareToSolution(attempt, position.solution);
});
