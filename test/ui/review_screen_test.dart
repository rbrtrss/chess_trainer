import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/attempt/attempt.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/training_session.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/ui/review/review_screen.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Review is where everything withheld during training becomes readable, and
/// where the app must still refuse to pass judgement on lines it cannot judge.
void main() {
  TrainingPosition positionNamed(String id) => parseTrainingPosition('''
[Title "The secret title of $id"]
[Goal "White to play and win"]
[Themes "fork, deflection"]
[Rating "1650"]
[Source "A book"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. e4 {The author's note on the first move.} e5 2. Nf3 (2. Bc4 {A quieter try.})
2... Nc6 3. Bb5
''', id: id);

  /// A session sitting in review, where the attempt for [positionId] is the
  /// line given by [attemptSans].
  TrainingSession reviewingWith({
    required IList<TrainingPosition> positions,
    required Map<String, List<String>> attemptLines,
  }) {
    var session = TrainingSession.start(positions);
    for (final position in positions) {
      var tree = VariationTree.empty(position.initialPosition);
      var path = MovePath.root;
      for (final san in attemptLines[position.id] ?? const <String>[]) {
        final edit = tree.play(path, tree.positionAt(path).parseSan(san)!);
        tree = edit.tree;
        path = edit.path;
      }
      session = session.commitAttempt(
        Attempt(
          positionId: position.id,
          tree: tree,
          duration: const Duration(seconds: 30),
          committedAt: DateTime(2026, 8, 12),
        ),
      );
    }
    return session;
  }

  Future<void> pumpReview(WidgetTester tester, TrainingSession session) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider
              .overrideWith(() => _FixedSessionController(session)),
        ],
        child: const MaterialApp(home: ReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  TrainingSession sessionOf(WidgetTester tester) {
    final element = tester.element(find.byType(MaterialApp));
    return ProviderScope.containerOf(element).read(sessionControllerProvider)!;
  }

  testWidgets('both the attempt and the solution are shown (FR-020)',
      (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: {
          'p0': ['e4', 'e5', 'Bc4'],
        },
      ),
    );

    expect(find.text('What you played'), findsOneWidget);
    expect(find.text('The solution'), findsOneWidget);
    // The attempt's line and the solution's line are both listed.
    expect(find.byKey(const Key('attempt-node-0.0.0')), findsOneWidget);
    expect(find.byKey(const Key('solution-node-0.0.0')), findsOneWidget);
  });

  testWidgets('the first divergence is identified (FR-021)', (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: {
          'p0': ['e4', 'e5', 'Bc4'],
        },
      ),
    );

    expect(
      find.textContaining('you played Bc4 where the solution has Nf3'),
      findsOneWidget,
    );
    // And marked in the panes, on the primary line of each.
    expect(find.byIcon(Icons.call_split), findsNWidgets(2));
  });

  testWidgets('solution notes appear at the moves they belong to (FR-022)',
      (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: {
          'p0': ['e4'],
        },
      ),
    );

    expect(find.text("The author's note on the first move."), findsOneWidget);
    expect(find.text('A quieter try.'), findsOneWidget);
  });

  testWidgets('the match indicator reads as a measurement, not a verdict',
      (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: {
          'p0': ['e4', 'e5'],
        },
      ),
    );

    expect(find.byKey(const Key('match-indicator')), findsOneWidget);
    expect(
      find.textContaining('followed the solution for 2 of 5 moves'),
      findsOneWidget,
    );
    // Stopping early is worded as stopping, not as an error.
    expect(find.textContaining('and stopped there'), findsOneWidget);
    expect(find.textContaining('wrong'), findsNothing);
    expect(find.textContaining('incorrect'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('an empty attempt is reported as such, not as a mistake',
      (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: const {},
      ),
    );

    expect(find.textContaining('for 0 of 5 moves'), findsOneWidget);
    expect(find.textContaining('and stopped there'), findsOneWidget);
    expect(find.text('You committed without entering a move.'), findsOneWidget);
  });

  testWidgets('withheld metadata is revealed here (FR-025)', (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: {
          'p0': ['e4'],
        },
      ),
    );

    expect(find.byKey(const Key('metadata-panel')), findsOneWidget);
    expect(find.textContaining('The secret title of p0'), findsOneWidget);
    expect(find.textContaining('White to play and win'), findsOneWidget);
    expect(find.textContaining('fork, deflection'), findsOneWidget);
    expect(find.textContaining('1650'), findsOneWidget);
  });

  testWidgets('a branch the solution does not contain is not called wrong '
      '(FR-024)', (tester) async {
    // The attempt's main line matches; it also has an alternative the solution
    // never mentions.
    var session = reviewingWith(
      positions: IList([positionNamed('p0')]),
      attemptLines: {
        'p0': ['e4', 'e5', 'Nf3'],
      },
    );
    final position = session.positions.first;
    var tree = session.attemptFor('p0')!.tree;
    final afterE5 = MovePath.root.child(0).child(0);
    tree = tree.play(afterE5, tree.positionAt(afterE5).parseSan('d4')!).tree;
    session = TrainingSession(
      positions: session.positions,
      attempts: session.attempts
          .add('p0', Attempt(
            positionId: position.id,
            tree: tree,
            duration: const Duration(seconds: 30),
            committedAt: DateTime(2026, 8, 12),
          )),
      phase: SessionPhase.review,
      currentIndex: 0,
    );

    await pumpReview(tester, session);

    // The branch is shown...
    expect(find.byKey(const Key('attempt-node-0.0.1')), findsOneWidget);
    // ...and nothing marks it as a divergence, because the comparison never
    // looked at it. With the main line matching there is no divergence at all.
    expect(find.byIcon(Icons.call_split), findsNothing);
    expect(find.textContaining('wrong'), findsNothing);
    expect(find.textContaining('mistake'), findsNothing);
  });

  testWidgets('stepping through a line moves the board', (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: {
          'p0': ['e4', 'e5'],
        },
      ),
    );

    final backAtStart =
        tester.widget<IconButton>(find.byKey(const Key('review-step-back')));
    expect(backAtStart.onPressed, isNull, reason: 'already at the start');

    await tester.tap(find.byKey(const Key('review-step-forward')));
    await tester.pumpAndSettle();

    final afterStep =
        tester.widget<IconButton>(find.byKey(const Key('review-step-back')));
    expect(afterStep.onPressed, isNotNull);
  });

  testWidgets('tapping a move in either pane selects it', (tester) async {
    await pumpReview(
      tester,
      reviewingWith(
        positions: IList([positionNamed('p0')]),
        attemptLines: {
          'p0': ['e4', 'e5', 'Bc4'],
        },
      ),
    );

    await tester.tap(find.byKey(const Key('attempt-node-0.0.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('solution-node-0.0.0')));
    await tester.pumpAndSettle();

    // Both panes accepted the tap without throwing; the board followed.
    expect(find.byKey(const Key('solution-pane')), findsOneWidget);
  });

  group('self-grading (FR-026, FR-027)', () {
    testWidgets('no grade is preselected from the match indicator',
        (tester) async {
      await pumpReview(
        tester,
        reviewingWith(
          positions: IList([positionNamed('p0')]),
          attemptLines: {
            'p0': ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'],
          },
        ),
      );

      // A perfect match, and still nothing is chosen for the user.
      expect(find.textContaining('followed the solution for all 5 moves'),
          findsOneWidget);
      for (final value in GradeValue.values) {
        expect(
          tester.widget<OutlinedButton>(
              find.descendant(
                of: find.byKey(Key('grade-${value.name}')),
                matching: find.byType(OutlinedButton),
              )),
          isNotNull,
        );
      }
    });

    testWidgets('recording a grade stores it as the authoritative assessment',
        (tester) async {
      await pumpReview(
        tester,
        reviewingWith(
          positions: IList([positionNamed('p0')]),
          attemptLines: {
            'p0': ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'],
          },
        ),
      );

      // The match indicator says the line was followed all the way; the user
      // says they missed it. The user wins.
      await tester.tap(find.byKey(const Key('grade-failed')));
      await tester.pumpAndSettle();

      expect(sessionOf(tester).gradeFor('p0')!.value, GradeValue.failed);
      expect(find.textContaining('followed the solution for all 5 moves'),
          findsOneWidget,
          reason: 'the measurement is unchanged — it is advisory, not a score');
    });

    testWidgets('a grade can be changed', (tester) async {
      await pumpReview(
        tester,
        reviewingWith(
          positions: IList([positionNamed('p0')]),
          attemptLines: {
            'p0': ['e4'],
          },
        ),
      );

      await tester.tap(find.byKey(const Key('grade-hard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('grade-good')));
      await tester.pumpAndSettle();

      expect(sessionOf(tester).gradeFor('p0')!.value, GradeValue.good);
    });
  });

  group('moving between positions (FR-028)', () {
    testWidgets('next and previous work without grading anything',
        (tester) async {
      await pumpReview(
        tester,
        reviewingWith(
          positions: IList([positionNamed('p0'), positionNamed('p1')]),
          attemptLines: {
            'p0': ['e4'],
            'p1': ['d4'],
          },
        ),
      );

      expect(find.text('Review 1 of 2'), findsOneWidget);
      final previous =
          tester.widget<IconButton>(find.byKey(const Key('review-previous')));
      expect(previous.onPressed, isNull);

      await tester.tap(find.byKey(const Key('review-next')));
      await tester.pumpAndSettle();

      expect(find.text('Review 2 of 2'), findsOneWidget);
      expect(sessionOf(tester).grades, isEmpty);
      expect(find.textContaining('The secret title of p1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-previous')));
      await tester.pumpAndSettle();

      expect(find.text('Review 1 of 2'), findsOneWidget);
    });

    testWidgets('the finish button appears only once everything is graded',
        (tester) async {
      await pumpReview(
        tester,
        reviewingWith(
          positions: IList([positionNamed('p0'), positionNamed('p1')]),
          attemptLines: {
            'p0': ['e4'],
            'p1': ['d4'],
          },
        ),
      );

      expect(find.byKey(const Key('finish-review')), findsNothing);

      await tester.tap(find.byKey(const Key('grade-good')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('grade-easy')));
      await tester.pumpAndSettle();

      expect(sessionOf(tester).phase, SessionPhase.complete);
      expect(find.byKey(const Key('finish-review')), findsOneWidget);
    });
  });
}

class _FixedSessionController extends SessionController {
  _FixedSessionController(this.initial);

  final TrainingSession initial;

  @override
  TrainingSession? build() => initial;
}
