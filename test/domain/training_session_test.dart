import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

TrainingPosition positionNamed(String id) =>
    parseTrainingPosition('[FEN "${Chess.initial.fen}"]\n\n1. e4 e5', id: id);

IList<TrainingPosition> positions(int count) =>
    IList(List.generate(count, (i) => positionNamed('p$i')));

Attempt emptyAttemptFor(TrainingPosition position) => Attempt(
      positionId: position.id,
      tree: VariationTree.empty(position.initialPosition),
      duration: const Duration(seconds: 5),
      committedAt: DateTime(2026, 8, 12),
    );

void main() {
  group('starting a session', () {
    test('a started session is in training on the first position', () {
      final session = TrainingSession.start(positions(3));

      expect(session.phase, SessionPhase.training);
      expect(session.currentIndex, 0);
      expect(session.attempts, isEmpty);
      expect(session.allPositionsAttempted, isFalse);
    });

    test('a session in setup holds positions but is not training yet', () {
      final session = TrainingSession.setup(positions(3));

      expect(session.phase, SessionPhase.setup);
      expect(session.start().phase, SessionPhase.training);
    });

    test('a session with no positions cannot start', () {
      expect(() => TrainingSession.start(const IList.empty()),
          throwsA(isA<StateError>()));
    });
  });

  group('committing the only position (US1)', () {
    test('commit on the last position enters review, and not before', () {
      final only = positions(1);
      final session = TrainingSession.start(only);

      final reviewing = session.commitAttempt(emptyAttemptFor(only.first));

      expect(reviewing.phase, SessionPhase.review);
      expect(reviewing.allPositionsAttempted, isTrue);
      expect(reviewing.currentIndex, 0);
    });

    test('an empty analysis is a valid commit', () {
      final only = positions(1);
      final attempt = emptyAttemptFor(only.first);

      final reviewing = TrainingSession.start(only).commitAttempt(attempt);

      expect(reviewing.attemptFor('p0'), attempt);
      expect(reviewing.attemptFor('p0')!.tree.isEmpty, isTrue);
    });

    test('a committed attempt is unaffected by later edits to the same tree',
        () {
      final only = positions(1);
      final position = only.first;
      var tree = VariationTree.empty(position.initialPosition);
      tree = tree.play(MovePath.root, position.initialPosition.parseSan('e4')!).tree;

      final attempt = Attempt(
        positionId: position.id,
        tree: tree,
        duration: const Duration(seconds: 30),
        committedAt: DateTime(2026, 8, 12),
      );
      final session = TrainingSession.start(only).commitAttempt(attempt);

      // Keep analysing the same tree value after committing it (FR-015).
      tree.play(MovePath.root, position.initialPosition.parseSan('d4')!).tree;

      expect(session.attemptFor('p0')!.tree.nodeCount, 1);
      expect(session.attemptFor('p0')!.tree, attempt.tree);
    });

    test('committing an attempt for a position not in the session is rejected',
        () {
      final session = TrainingSession.start(positions(1));
      final stranger = positionNamed('not-in-session');

      expect(() => session.commitAttempt(emptyAttemptFor(stranger)),
          throwsA(isA<StateError>()));
    });

    test('committing twice for the same position is rejected', () {
      final only = positions(1);
      final session =
          TrainingSession.start(only).commitAttempt(emptyAttemptFor(only.first));

      expect(() => session.commitAttempt(emptyAttemptFor(only.first)),
          throwsA(isA<StateError>()));
    });

    test('committing outside the training phase is rejected', () {
      final only = positions(1);
      final reviewing =
          TrainingSession.start(only).commitAttempt(emptyAttemptFor(only.first));

      expect(() => reviewing.commitAttempt(emptyAttemptFor(only.first)),
          throwsA(isA<StateError>()));
    });
  });

  group('invariant 8: review begins only after the final commit (US2)', () {
    test('committing a non-final position stays in training and advances', () {
      final all = positions(5);
      var session = TrainingSession.start(all);

      for (var i = 0; i < 4; i++) {
        session = session.commitAttempt(emptyAttemptFor(all[i]));

        expect(session.phase, SessionPhase.training,
            reason: 'review must not begin at position ${i + 1} of 5');
        expect(session.currentIndex, i + 1);
        expect(session.allPositionsAttempted, isFalse);
      }

      session = session.commitAttempt(emptyAttemptFor(all[4]));

      expect(session.phase, SessionPhase.review);
      expect(session.allPositionsAttempted, isTrue);
      expect(session.attempts.length, 5);
    });

    test('every committed attempt survives to review (SC-007)', () {
      final all = positions(3);
      var session = TrainingSession.start(all);
      final committed = <Attempt>[];

      for (final position in all) {
        final attempt = Attempt(
          positionId: position.id,
          tree: VariationTree.empty(position.initialPosition)
              .play(MovePath.root, position.initialPosition.parseSan('e4')!)
              .tree,
          duration: const Duration(seconds: 12),
          committedAt: DateTime(2026, 8, 12),
        );
        committed.add(attempt);
        session = session.commitAttempt(attempt);
      }

      expect(session.phase, SessionPhase.review);
      for (final attempt in committed) {
        expect(session.attemptFor(attempt.positionId), attempt);
      }
    });

    test('the last position is identifiable while training it', () {
      final all = positions(2);
      var session = TrainingSession.start(all);

      expect(session.isLastPosition, isFalse);
      session = session.commitAttempt(emptyAttemptFor(all[0]));
      expect(session.isLastPosition, isTrue);
    });
  });

  group('invariant 9: abandoning reveals nothing (US2)', () {
    test('abandoning from training is terminal', () {
      final session = TrainingSession.start(positions(3));

      final abandoned = session.abandon();

      expect(abandoned.phase, SessionPhase.abandoned);
      expect(abandoned.phase.withholdsFeedback, isFalse,
          reason: 'abandoned is not a phase that continues withholding — '
              'it is a phase in which there is nothing left to withhold');
    });

    test('abandoning mid-session discards the attempts already committed', () {
      final all = positions(3);
      final session =
          TrainingSession.start(all).commitAttempt(emptyAttemptFor(all[0]));

      final abandoned = session.abandon();

      expect(abandoned.attempts, isEmpty);
      expect(abandoned.attemptFor('p0'), isNull);
      expect(abandoned.allPositionsAttempted, isFalse);
    });

    test('nothing can be committed after abandoning', () {
      final all = positions(2);
      final abandoned = TrainingSession.start(all).abandon();

      expect(() => abandoned.commitAttempt(emptyAttemptFor(all[0])),
          throwsA(isA<StateError>()));
    });

    test('abandoning from review is still terminal', () {
      final only = positions(1);
      final reviewing =
          TrainingSession.start(only).commitAttempt(emptyAttemptFor(only.first));

      expect(reviewing.abandon().phase, SessionPhase.abandoned);
    });
  });

  group('the session counter (FR-017)', () {
    test('projections carry a plain index and length', () {
      final all = positions(5);
      var session = TrainingSession.start(all);

      expect(session.projectionFor(session.currentIndex).displayNumber, 1);
      expect(session.projectionFor(session.currentIndex).sessionLength, 5);

      session = session.commitAttempt(emptyAttemptFor(all[0]));
      session = session.commitAttempt(emptyAttemptFor(all[1]));

      expect(session.projectionFor(session.currentIndex).displayNumber, 3);
      expect(session.projectionFor(session.currentIndex).sessionLength, 5);
    });
  });

  group('reading positions', () {
    test('the current position is addressable during training', () {
      final all = positions(3);
      final session = TrainingSession.start(all);

      expect(session.currentPosition, all.first);
      expect(session.positionAt(2), all[2]);
    });
  });
}
