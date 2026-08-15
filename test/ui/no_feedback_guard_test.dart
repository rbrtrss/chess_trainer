import 'dart:io';

import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
// `File` hidden: dartchess exports the a–h kind, and this file already uses
// dart:io's for reading the hostile fixture.
import 'package:dartchess/dartchess.dart' hide File;
import 'package:chessground/chessground.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

/// The guard test Principle I requires.
///
/// This is the one defect class that destroys the product's value while every
/// other test still passes and the app still looks fine, so the assertions here
/// are about *styling and structure*, not content. The user's own move is of
/// course different in the two runs — that is the move they played. What must
/// not differ is anything the app chose: a colour, a weight, an icon, an extra
/// widget, an arrow, a board annotation.
///
/// Research D8 calls this layer 3. Layers 1 and 2 are the `TrainingProjection`
/// type itself and `training_projection_test.dart`.
void main() {
  /// A position whose solution and metadata are both rich, so that any leak has
  /// something conspicuous to leak.
  final tactic = parseTrainingPosition('''
[Title "Philidor's Legacy"]
[Goal "White to play and force mate"]
[Themes "smothered mate, double check, queen sacrifice"]
[Rating "1500"]
[Source "Classic study"]
[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]

1. Nh6+ {Double check.} Kh8 2. Qg8+ Rxg8 3. Nf7#
''', id: 'guarded');

  final positions = IList([tactic]);

  testWidgets('the board is built with no annotations and no shapes',
      (tester) async {
    await pumpTrainingScreen(tester, positions: positions);

    final board = tester.widget<Chessboard>(find.byType(Chessboard));

    // The two parameters through which solution knowledge could reach the
    // board (research, "Verified package facts").
    expect(board.annotations, isEmpty);
    expect(board.shapes, isEmpty);

    // And they stay empty once the user has played.
    await playSanOnBoard(tester, 'Nh6+');
    final afterMove = tester.widget<Chessboard>(find.byType(Chessboard));
    expect(afterMove.annotations, isEmpty);
    expect(afterMove.shapes, isEmpty);
  });

  testWidgets('a move matching the solution renders exactly like one that does not',
      (tester) async {
    // The solution's move.
    await pumpTrainingScreen(tester, positions: positions);
    await playSanOnBoard(tester, 'Nh6+');
    final matching = renderSnapshot(tester);
    final matchingBoard = boardSnapshot(tester);

    // A move that is legal, pointless, and nowhere in the solution.
    await pumpTrainingScreen(tester, positions: positions);
    await playSanOnBoard(tester, 'Kh1');
    final diverging = renderSnapshot(tester);
    final divergingBoard = boardSnapshot(tester);

    expect(diverging, matching,
        reason: 'the training screen varied with the correctness of the move');
    expect(divergingBoard, matchingBoard,
        reason: 'the board was configured differently for the two moves');
  });

  testWidgets('an empty analysis renders like one with a move in it, structurally',
      (tester) async {
    await pumpTrainingScreen(tester, positions: positions);

    // Before any move there is no move row, so the trees legitimately differ in
    // length. What must hold is that nothing appeared that comments on the
    // position.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(Icon), findsWidgets);

    final before = _moveRowKeys(renderSnapshot(tester)).length;
    await playSanOnBoard(tester, 'Nh6+');
    final after = _moveRowKeys(renderSnapshot(tester)).length;

    expect(before, 0);
    expect(after, 1, reason: 'one move played, one row added, nothing else');
  });

  testWidgets('no withheld metadata is anywhere on the training screen',
      (tester) async {
    await pumpTrainingScreen(tester, positions: positions);
    await playSanOnBoard(tester, 'Nh6+');

    for (final withheld in <String>[
      "Philidor's Legacy",
      'White to play and force mate',
      'smothered',
      'double check',
      'queen sacrifice',
      '1500',
      'Classic study',
      'Double check.', // the solution's annotation
      'mate',
      'Mate',
      'check',
      'best',
      'correct',
      'wrong',
    ]) {
      // findRichText so a leak dressed up as a TextSpan is caught too.
      expect(find.textContaining(withheld, findRichText: true), findsNothing,
          reason: '"$withheld" must not appear during training (FR-003)');
    }
  });

  testWidgets('the progress counter reads the same whatever was played',
      (tester) async {
    await pumpTrainingScreen(tester, positions: positions);
    await playSanOnBoard(tester, 'Nh6+');
    final afterGoodMove =
        tester.widget<Text>(find.byKey(const Key('session-progress')));

    await pumpTrainingScreen(tester, positions: positions);
    await playSanOnBoard(tester, 'Kh1');
    final afterBadMove =
        tester.widget<Text>(find.byKey(const Key('session-progress')));

    expect(afterBadMove.data, afterGoodMove.data);
    expect(afterBadMove.style, afterGoodMove.style);
  });

  test('the training layer opens no sound, haptic or latency channel', () {
    // Three of the channels the constitution names cannot be seen in a widget
    // tree: sound, haptic, and latency. They are checked at the source instead.
    // Nothing in the app uses them at all, which is the cheapest way to be sure
    // none of them varies with correctness.
    final uiFiles = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in uiFiles) {
      final source = file.readAsStringSync();
      for (final channel in const [
        'HapticFeedback',
        'SystemSound',
        'vibrate',
        'AudioPlayer',
        'Future.delayed',
      ]) {
        expect(source, isNot(contains(channel)),
            reason: '${file.path} uses $channel — if it ever varies with the '
                'move played, no widget test will see it');
      }
    }
  });

  testWidgets('the turn indicator states the turn and nothing else',
      (tester) async {
    await pumpTrainingScreen(tester, positions: positions);

    final indicator =
        tester.widget<Text>(find.byKey(const Key('turn-indicator')));

    expect(indicator.data, 'White to move');
  });

  _resumptionGuards();
  _importGuards();
  _engineGuards();
}

/// Feature 003's guards: imported content must reach the training screen with
/// nothing of itself attached (FR-024 – FR-027, SC-003, SC-004).
///
/// Until imports existed, every string that could reach a screen was written by
/// us and reviewed. Now it is arbitrary text from a stranger's study, including
/// headers nobody anticipated — so the fixture fills *every* text-carrying
/// field with a sentinel and the test looks for all of them at once.
void _importGuards() {
  final hostile = parseTrainingPosition(
    File('test/fixtures/hostile_metadata.pgn').readAsStringSync(),
    id: 'imported-hostile',
  );

  /// Every sentinel the fixture plants, read back out of the file itself.
  ///
  /// Derived rather than listed, so that adding a field to the fixture extends
  /// the test automatically. A guard whose fixture and assertions can drift
  /// apart is a guard that quietly stops covering the field somebody just
  /// added.
  final sentinels = RegExp(r'SENTINEL-[A-Z-]+(?:-[A-Za-z]+)?')
      .allMatches(File('test/fixtures/hostile_metadata.pgn').readAsStringSync())
      .map((match) => match.group(0)!)
      .toSet();

  group('an imported position leaks nothing it arrived with', () {
    test('the fixture really does carry sentinels in every field', () {
      // If this fails, the test below is proving nothing.
      expect(sentinels.length, greaterThanOrEqualTo(15));
      expect(hostile.metadata.headers['SomeTagInventedToday'],
          'SENTINEL-UNKNOWNTAG');
    });

    testWidgets('none of them appears anywhere on the training screen',
        (tester) async {
      await pumpTrainingScreen(tester, positions: IList([hostile]));
      await playSanOnBoard(tester, 'Nh6+');

      for (final sentinel in sentinels) {
        expect(find.textContaining(sentinel, findRichText: true), findsNothing,
            reason: '"$sentinel" reached the training screen. Every header, '
                'comment and annotation an imported entry carries is evidence '
                'about the position (FR-024)');
      }
    });

    testWidgets('nor in any semantics label, tooltip or accessibility node',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTrainingScreen(tester, positions: IList([hostile]));
      await playSanOnBoard(tester, 'Nh6+');

      final labels = <String>[];
      void collect(SemanticsNode node) {
        labels
          ..add(node.label)
          ..add(node.tooltip)
          ..add(node.value)
          ..add(node.hint);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(tester.binding.rootElement!
          .findRenderObject()!
          .debugSemantics!);

      for (final sentinel in sentinels) {
        expect(labels.where((label) => label.contains(sentinel)), isEmpty,
            reason: '"$sentinel" is readable by a screen reader. A leak that '
                'only a blind player hears is still a leak');
      }
      handle.dispose();
    });

    testWidgets('an imported position renders like a bundled one (SC-004)',
        (tester) async {
      // Same starting position, same move, different provenance. If the two
      // screens differ, something about *where the position came from* is
      // being drawn.
      final bundled = parseTrainingPosition('''
[FEN "5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1"]

1. Nh6+ Kh8 2. Qg8+ Rxg8 3. Nf7#
''', id: 'bundled-equivalent');

      await pumpTrainingScreen(tester, positions: IList([bundled]));
      await playSanOnBoard(tester, 'Nh6+');
      final bundledRender = renderSnapshot(tester);
      final bundledBoard = boardSnapshot(tester);

      await pumpTrainingScreen(tester, positions: IList([hostile]));
      await playSanOnBoard(tester, 'Nh6+');
      final importedRender = renderSnapshot(tester);
      final importedBoard = boardSnapshot(tester);

      expect(importedRender, bundledRender,
          reason: 'the training screen varied with where the position came '
              'from');
      expect(importedBoard, bundledBoard);
    });
  });
}

/// The distinct move rows in a snapshot.
///
/// A keyed list child appears twice in the element tree — once as the widget
/// and once as the `KeyedSubtree` the sliver wraps it in — so the keys are
/// counted as a set.
Set<String> _moveRowKeys(List<String> snapshot) => snapshot
    .map((entry) => RegExp(r'tree-node-[\d.]+').firstMatch(entry)?.group(0))
    .nonNulls
    .toSet();

/// Invariant 11: resuming reveals exactly as much as never having been
/// interrupted, which is nothing (FR-008, SC-003).
///
/// Persistence gave the app a way to know something a fresh session does not —
/// which positions have already been committed, and what was in them. The
/// training screen still sees only a `TrainingProjection`, so the barrier built
/// in feature 001 covers this for free; that is the claim, and this is the test
/// of it.
///
/// The notice that an in-progress analysis was not kept deliberately lives on
/// the resume prompt rather than here (FR-003). Anything that appeared on this
/// screen only after a resume would be a difference this test would catch, and
/// should.
void _resumptionGuards() {
  /// Three positions from the standard starting position, so the same move is
  /// playable on the fresh screen and the resumed one, with metadata rich
  /// enough for a leak to be conspicuous.
  final positions = IList(
    List.generate(
      3,
      (i) => parseTrainingPosition('''
[Title "Secret chapter $i"]
[Goal "White to play and win"]
[Themes "fork, pin"]
[Rating "${1200 + i}"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]

1. d4 d5 2. c4
''', id: 'resumable-$i'),
    ),
  );

  group('a resumed session looks exactly like an uninterrupted one', () {
    testWidgets('at the same point in the session', (tester) async {
      // Fresh: start and commit two positions to arrive at the third.
      await pumpTrainingScreen(tester, positions: positions);
      await tester.tap(find.byKey(const Key('commit-attempt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('commit-attempt')));
      await tester.pumpAndSettle();
      final fresh = renderSnapshot(tester);
      final freshBoard = boardSnapshot(tester);

      // Resumed: the same two positions committed, then the app was killed.
      await pumpResumedTrainingScreen(tester,
          positions: positions, committed: 2);
      final resumed = renderSnapshot(tester);
      final resumedBoard = boardSnapshot(tester);

      expect(resumed, fresh,
          reason: 'the resumed training screen differs from a fresh one');
      expect(resumedBoard, freshBoard,
          reason: 'the board was configured differently after a resume');
    });

    testWidgets('after the same move has been played on it', (tester) async {
      await pumpTrainingScreen(tester, positions: positions);
      await tester.tap(find.byKey(const Key('commit-attempt')));
      await tester.pumpAndSettle();
      await playSanOnBoard(tester, 'e4');
      final fresh = renderSnapshot(tester);
      final freshBoard = boardSnapshot(tester);

      await pumpResumedTrainingScreen(tester,
          positions: positions, committed: 1);
      await playSanOnBoard(tester, 'e4');
      final resumed = renderSnapshot(tester);
      final resumedBoard = boardSnapshot(tester);

      expect(resumed, fresh);
      expect(resumedBoard, freshBoard);
    });

    testWidgets('and shows no notice, banner or dialog of its own',
        (tester) async {
      await pumpResumedTrainingScreen(tester,
          positions: positions, committed: 2);

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
      // The count is a plain count, exactly as in a fresh session.
      final progress =
          tester.widget<Text>(find.byKey(const Key('session-progress')));
      expect(progress.data, '3 of 3');
    });
  });
}


/// A description of everything the app chose about how to draw the screen,
/// with the content the user supplied deliberately left out.
///
/// Text *strings* are excluded because the user's own move is one; text
/// *styles* are included because a colour or a weight that varies with
/// correctness is exactly the defect this test exists to catch. The board's
/// interior is not descended into — piece placement is the user's move — and is
/// covered by [boardSnapshot] instead.
List<String> renderSnapshot(WidgetTester tester) {
  final entries = <String>[];

  void visit(Element element) {
    final widget = element.widget;
    entries.add(_describe(widget));
    if (widget is Chessboard) return;
    element.visitChildren(visit);
  }

  visit(tester.element(find.byType(MaterialApp)));
  return entries;
}

/// Everything the board was configured with, excluding the position itself.
String boardSnapshot(WidgetTester tester) {
  final board = tester.widget<Chessboard>(find.byType(Chessboard));
  return [
    'orientation=${board.orientation}',
    'shapes=${board.shapes}',
    'annotations=${board.annotations}',
    'interactive=${board.interactive}',
    'playerSide=${board.controller.game.playerSide}',
    'kingSquareInCheck=${board.controller.game.kingSquareInCheck}',
    'animationDuration=${board.settings.animationDuration}',
    'showLastMove=${board.settings.showLastMove}',
    'showValidMoves=${board.settings.showValidMoves}',
    'colorScheme=${board.settings.colorScheme.hashCode}',
    'brightness=${board.settings.brightness}',
    'hue=${board.settings.hue}',
    'blindfold=${board.settings.blindfoldMode}',
  ].join(', ');
}

/// Framework keys embed object identity hashes (`_MaterialAppState#44d96`),
/// which differ between two pumps for reasons that have nothing to do with the
/// app. They are normalised away so the comparison is about what was drawn.
final _objectHash = RegExp(r'#[0-9a-f]{5,}');

String _describe(Widget widget) {
  final key =
      widget.key == null ? '' : ' key=${widget.key}'.replaceAll(_objectHash, '#');
  return switch (widget) {
    Chessboard() => 'Chessboard$key',
    // The string is the user's move; the style is the app's choice.
    Text(:final style, :final textAlign) =>
      'Text$key style=$style align=$textAlign',
    Icon(:final icon, :final color, :final size) =>
      'Icon$key icon=${icon?.codePoint} color=$color size=$size',
    IconButton(:final onPressed, :final color) =>
      'IconButton$key enabled=${onPressed != null} color=$color',
    TextButton(:final onPressed) => 'TextButton$key enabled=${onPressed != null}',
    FilledButton(:final onPressed) =>
      'FilledButton$key enabled=${onPressed != null}',
    ColoredBox(:final color) => 'ColoredBox$key color=$color',
    DecoratedBox(:final decoration) => 'DecoratedBox$key decoration=$decoration',
    Padding(:final padding) => 'Padding$key padding=$padding',
    InkWell() => 'InkWell$key',
    _ => '${widget.runtimeType}$key',
  };
}

/// Feature 005's guard: an engine's evaluation is not evidence *about* the
/// answer, it **is** the answer, and it must never reach a training screen
/// (FR-016, FR-018, FR-020, SC-004, SC-010).
///
/// The hardest case this guard has had. Everything it withheld before — titles,
/// comments, NAGs — described a position. This describes how good the move is.
void _engineGuards() {
  group('an engine-judged position gives nothing away (005 FR-016, FR-018)', () {
    /// The same position, once with an author's line and once with an engine's
    /// — and an evaluation that says, in a number, exactly how good it is.
    ///
    /// This is the hardest case this guard has ever had. Everything it withheld
    /// before was *evidence* about a position: a title, a comment, a NAG. An
    /// evaluation is the answer.
    IList<TrainingPosition> pair({required bool judged}) {
      final start = Chess.fromSetup(
          Setup.parseFen('5rk1/5Npp/8/8/8/1Q6/6PP/6K1 w - - 0 1'));
      var tree = VariationTree.empty(start);
      tree = tree
          .play(MovePath.root, const NormalMove(from: Square.f7, to: Square.h6))
          .tree;

      return IList([
        TrainingPosition(
          id: judged ? 'judged' : 'authored',
          initialPosition: start,
          solution: tree,
          solutionSource:
              judged ? SolutionSource.engine : SolutionSource.author,
          evaluation: judged
              ? const PositionEvaluation(
                  score: MateIn(5),
                  depth: 12,
                  perspective: Side.white,
                )
              : null,
        ),
      ]);
    }

    /// Everything the screen would say out loud, plus every string in its tree.
    List<String> everythingOnScreen(WidgetTester tester) => [
          ...tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? ''),
          ...tester
              .widgetList<Semantics>(find.byType(Semantics))
              .map((widget) => widget.properties.label ?? ''),
          ...tester
              .widgetList<Tooltip>(find.byType(Tooltip))
              .map((widget) => widget.message ?? ''),
        ];

    testWidgets('no evaluation, score or depth is reachable', (tester) async {
      await pumpTrainingScreen(tester, positions: pair(judged: true));

      final said = everythingOnScreen(tester).join(' ').toLowerCase();

      for (final forbidden in const [
        'mate',
        'engine',
        'evaluation',
        'centipawn',
        'depth',
        'stockfish',
        '+',
        'best',
      ]) {
        expect(said, isNot(contains(forbidden)),
            reason: 'the training screen said "$forbidden" for a position the '
                'engine has judged as a forced mate. An evaluation is not '
                'evidence about the answer, it *is* the answer');
      }
    });

    testWidgets('it renders identically to the same position authored (SC-004)',
        (tester) async {
      // The two differ only in where their solution came from — same board,
      // same line, same everything the player is allowed to see. If the screens
      // differ at all, the difference is the leak.
      await pumpTrainingScreen(tester, positions: pair(judged: false));
      final authored = everythingOnScreen(tester);

      await pumpTrainingScreen(tester, positions: pair(judged: true));
      final judged = everythingOnScreen(tester);

      expect(judged, authored,
          reason: 'a player must not be able to tell which positions in a '
              'session have an engine behind them');
    });
  });
}
