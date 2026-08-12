import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

TrainingPosition positionNamed(String id) =>
    parseTrainingPosition('[FEN "${Chess.initial.fen}"]\n\n1. e4 e5', id: id);

void main() {
  IList<TrainingPosition> positions(int count) =>
      IList(List.generate(count, (i) => positionNamed('p$i')));

  /// A session that has been through training and is sitting in review.
  TrainingSession reviewing(int count) {
    var session = TrainingSession.start(positions(count));
    for (final position in session.positions) {
      session = session.commitAttempt(
        Attempt(
          positionId: position.id,
          tree: VariationTree.empty(position.initialPosition),
          duration: const Duration(seconds: 1),
          committedAt: DateTime(2026, 8, 12),
        ),
      );
    }
    return session;
  }

  group('recording a grade (FR-026)', () {
    test('a grade is stored against its position', () {
      final session = reviewing(2).recordGrade(
        const Grade(positionId: 'p0', value: GradeValue.hard),
      );

      expect(session.gradeFor('p0')!.value, GradeValue.hard);
      expect(session.gradeFor('p1'), isNull);
    });

    test('re-grading replaces the earlier judgement', () {
      final session = reviewing(2)
          .recordGrade(const Grade(positionId: 'p0', value: GradeValue.failed))
          .recordGrade(const Grade(positionId: 'p0', value: GradeValue.good));

      expect(session.gradeFor('p0')!.value, GradeValue.good);
      expect(session.grades.length, 1);
    });

    test('grading every position completes the session', () {
      var session = reviewing(2);
      expect(session.allPositionsGraded, isFalse);

      session = session
          .recordGrade(const Grade(positionId: 'p0', value: GradeValue.good));
      expect(session.phase, SessionPhase.review);

      session = session
          .recordGrade(const Grade(positionId: 'p1', value: GradeValue.easy));

      expect(session.allPositionsGraded, isTrue);
      expect(session.phase, SessionPhase.complete);
    });

    test('grading is impossible during training', () {
      final training = TrainingSession.start(positions(2));

      expect(
        () => training
            .recordGrade(const Grade(positionId: 'p0', value: GradeValue.good)),
        throwsA(isA<StateError>()),
      );
    });

    test('grading a position outside the session is rejected', () {
      expect(
        () => reviewing(1).recordGrade(
            const Grade(positionId: 'stranger', value: GradeValue.good)),
        throwsA(isA<StateError>()),
      );
    });

    test('the four values match SM-2 bands and carry plain labels', () {
      expect(GradeValue.values,
          [GradeValue.failed, GradeValue.hard, GradeValue.good, GradeValue.easy]);
      expect(GradeValue.failed.label, 'Missed it');
      expect(GradeValue.easy.label, 'Easy');
    });
  });

  group('moving around in review (FR-028)', () {
    test('navigation is free in both directions', () {
      var session = reviewing(3);

      session = session.goToReviewPosition(2);
      expect(session.currentIndex, 2);

      session = session.goToReviewPosition(0);
      expect(session.currentIndex, 0);
    });

    test('navigation does not require a grade first', () {
      final session = reviewing(3).goToReviewPosition(2);

      expect(session.grades, isEmpty);
      expect(session.currentIndex, 2);
    });

    test('navigation still works once the session is complete', () {
      var session = reviewing(2)
          .recordGrade(const Grade(positionId: 'p0', value: GradeValue.good))
          .recordGrade(const Grade(positionId: 'p1', value: GradeValue.good));

      expect(session.phase, SessionPhase.complete);
      session = session.goToReviewPosition(0);
      expect(session.currentIndex, 0);
    });

    test('an index outside the session is rejected', () {
      expect(() => reviewing(2).goToReviewPosition(2),
          throwsA(isA<RangeError>()));
    });

    test('review navigation is unavailable during training', () {
      expect(() => TrainingSession.start(positions(2)).goToReviewPosition(1),
          throwsA(isA<StateError>()));
    });
  });

  group('grades are lost with an abandoned session', () {
    test('abandoning discards grades along with attempts', () {
      final abandoned = reviewing(2)
          .recordGrade(const Grade(positionId: 'p0', value: GradeValue.good))
          .abandon();

      expect(abandoned.grades, isEmpty);
      expect(abandoned.attempts, isEmpty);
    });
  });
}
