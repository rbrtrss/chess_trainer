import 'package:chess_trainer/domain/tree/move_node.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// One frame of the analysis editor: the tree so far, where the cursor sits,
/// and everything the board needs to draw itself.
///
/// The derived values are computed once here rather than on every `build`,
/// because a widget rebuild should not be replaying the whole line.
@immutable
class AnalysisEditorState {
  AnalysisEditorState._({required this.tree, required this.cursor})
      : position = tree.positionAt(cursor),
        currentNode = tree.nodeAt(cursor);

  /// A fresh editor on [initialPosition], with nothing entered.
  factory AnalysisEditorState.initial(Position initialPosition) =>
      AnalysisEditorState._(
        tree: VariationTree.empty(initialPosition),
        cursor: MovePath.root,
      );

  /// The analysis entered so far.
  final VariationTree tree;

  /// Where the user is looking.
  final MovePath cursor;

  /// The position on the board.
  final Position position;

  /// The node the cursor sits on, or null at the starting position.
  final MoveNode? currentNode;

  /// Legal destinations, in the shape chessground wants.
  ///
  /// Handing the board exactly these is what makes illegal moves *unreachable*
  /// rather than rejected (research D6). There is no rejection path to vary
  /// with the position, so FR-005 holds by construction.
  ValidMoves get validMoves => makeLegalMoves(position);

  /// The move that led here, for the board's last-move highlight. It is the
  /// user's own move and looks the same whatever it was.
  Move? get lastMove => currentNode?.move;

  /// True when the game has ended at the cursor and this line can go no further.
  ///
  /// The UI stops offering moves; it must not say why.
  bool get isTerminal => position.isGameOver;

  bool get isAtStart => cursor.isRoot;

  bool get canGoForward => tree.childrenAt(cursor).isNotEmpty;

  /// True when the cursor sits on a node that has siblings — the only place
  /// where promoting or deleting a branch is meaningful.
  bool get cursorIsOnBranch {
    final parent = cursor.parent;
    if (parent == null) return false;
    return tree.childrenAt(parent).length > 1;
  }

  AnalysisEditorState _with({VariationTree? tree, MovePath? cursor}) =>
      AnalysisEditorState._(
        tree: tree ?? this.tree,
        cursor: cursor ?? this.cursor,
      );
}

/// Drives the analysis editor.
///
/// Rebuilt from scratch whenever the position under training changes, so
/// nothing can leak from one position's analysis into the next.
class AnalysisEditorNotifier extends Notifier<AnalysisEditorState> {
  @override
  AnalysisEditorState build() {
    // Watch the whole projection, not just its board. Two positions in a
    // session can share a starting FEN — two puzzles from the same opening,
    // say — and keying the reset on the board alone would carry one position's
    // analysis into the next.
    final projection = ref.watch(currentProjectionProvider);
    return AnalysisEditorState.initial(
      projection?.initialPosition ?? Chess.initial,
    );
  }

  /// Records [move] at the cursor and moves the cursor onto it.
  ///
  /// Whether this continued a line or forked one is deliberately not reported.
  /// `TreeEdit.createdBranch` is dropped on the floor here: branches are
  /// created without confirmation, announcement, or any other interruption
  /// (FR-009), and the way to guarantee that is to not know.
  void play(Move move) {
    final edit = state.tree.play(state.cursor, move);
    state = state._with(tree: edit.tree, cursor: edit.path);
  }

  /// Steps back one ply, to the starting position at the shallowest.
  void stepBackward() {
    final parent = state.cursor.parent;
    if (parent == null) return;
    state = state._with(cursor: parent);
  }

  /// Steps forward along the primary continuation from here.
  void stepForward() {
    if (!state.canGoForward) return;
    state = state._with(cursor: state.cursor.child(0));
  }

  /// Returns to the starting position (FR-006).
  void reset() {
    state = state._with(cursor: MovePath.root);
  }

  /// Moves the cursor anywhere in the tree (FR-010).
  void goTo(MovePath path) {
    // Validate before committing: a tap on a stale row should do nothing
    // rather than break the editor.
    state.tree.nodeAt(path);
    state = state._with(cursor: path);
  }

  /// Makes the branch under the cursor the primary line (FR-013).
  void promoteCurrent() {
    final parent = state.cursor.parent;
    if (parent == null) return;
    state = state._with(
      tree: state.tree.promote(state.cursor),
      // Promotion renumbers siblings; the node the cursor was on is now first.
      cursor: parent.child(0),
    );
  }

  /// Deletes the branch under the cursor (FR-011).
  void deleteCurrent() {
    final parent = state.cursor.parent;
    if (parent == null) return;
    state = state._with(
      tree: state.tree.delete(state.cursor),
      // Everything below the deleted node is gone, so retreat to its parent.
      cursor: parent,
    );
  }
}

final analysisEditorProvider =
    NotifierProvider<AnalysisEditorNotifier, AnalysisEditorState>(
  AnalysisEditorNotifier.new,
);
