import 'package:chess_trainer/data/session_repository.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chess_trainer/ui/training/training_screen.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/repository_harness.dart';

/// Pumps the real training screen over a session built from [positions].
///
/// The screen is pumped through the actual session provider rather than a stub,
/// so the tests exercise the same path the app does — including the projection
/// boundary that keeps the solution out of reach.
Future<void> pumpTrainingScreen(
  WidgetTester tester, {
  required IList<TrainingPosition> positions,
  Size surface = const Size(400, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // Tear down anything pumped earlier in this test, so a second call starts
  // from a genuinely fresh ProviderScope rather than reusing the element tree
  // — otherwise the editor's state would carry over between the two runs a
  // comparison test needs to keep apart.
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _StartedSessionController(positions),
        ),
      ],
      child: const MaterialApp(home: TrainingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _StartedSessionController extends SessionController {
  _StartedSessionController(this.positions);

  final IList<TrainingPosition> positions;

  @override
  TrainingSession? build() => TrainingSession.start(positions);
}

/// Pumps the training screen over a session that was **stored, killed and
/// resumed**, rather than started fresh.
///
/// The session goes through the real repository and the real
/// `SessionController.resume`, so what is compared in the guard test is the app's
/// actual resume path — not a session hand-built to look like a resumed one.
///
/// [committed] positions are committed before the interruption; training then
/// resumes on the position after them, with an empty board, because
/// uncommitted analysis is not stored (research D3).
Future<void> pumpResumedTrainingScreen(
  WidgetTester tester, {
  required IList<TrainingPosition> positions,
  int committed = 0,
  Size surface = const Size(400, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final repository = inMemorySessionRepository();
  final stored = await repository.start(positions);
  for (var i = 0; i < committed; i++) {
    await repository.commitAttempt(stored.id, sampleAttempt(positions[i]));
  }
  final resumable = await repository.loadInProgress();

  await tester.pumpWidget(const SizedBox.shrink());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repository),
        sessionControllerProvider.overrideWith(
          () => _ResumedSessionController(resumable!),
        ),
      ],
      // Deliberately the same widget tree as the fresh harness above: the
      // guard test compares the two, so any structural difference introduced
      // here would be a difference the test then reports as a leak.
      child: const MaterialApp(home: TrainingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _ResumedSessionController extends SessionController {
  _ResumedSessionController(this.stored);

  final StoredSession stored;

  @override
  TrainingSession? build() => resumedSessionFrom(stored);
}

/// Plays [san] on the board by tapping the origin square and then the
/// destination, the way a user does.
Future<void> playSanOnBoard(WidgetTester tester, String san) async {
  final position = currentBoardPosition(tester);
  final move = position.parseSan(san);
  expect(move, isNotNull, reason: '$san is not legal in ${position.fen}');
  final normal = move! as NormalMove;

  await tapSquare(tester, normal.from);
  await tapSquare(tester, normal.to);
  await tester.pumpAndSettle();
}

/// Taps the centre of [square] on the board.
Future<void> tapSquare(WidgetTester tester, Square square) async {
  final board = tester.widget<Chessboard>(find.byType(Chessboard));
  final boardRect = tester.getRect(find.byType(Chessboard));
  final squareSize = board.size / 8;

  // Square implements int: file is the low three bits, rank the high three.
  final fileIndex = square % 8;
  final rankIndex = square ~/ 8;
  final file =
      board.orientation == Side.white ? fileIndex : 7 - fileIndex;
  final rank = board.orientation == Side.white ? 7 - rankIndex : rankIndex;

  await tester.tapAt(
    boardRect.topLeft +
        Offset((file + 0.5) * squareSize, (rank + 0.5) * squareSize),
  );
  await tester.pump();
}

/// The position the board is currently showing.
Position currentBoardPosition(WidgetTester tester) {
  final board = tester.widget<Chessboard>(find.byType(Chessboard));
  return Chess.fromSetup(Setup.parseFen(board.controller.fen));
}
