import 'dart:io';

import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chessground/chessground.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
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
