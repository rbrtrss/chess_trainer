# Contract: Domain API

**Feature**: [spec.md](../spec.md) | **Data model**: [data-model.md](../data-model.md)

The public surface of `lib/domain/`. These signatures are the contract the UI layer codes
against and the surface the required unit tests exercise. Bodies are omitted deliberately —
this is a contract, not an implementation.

Everything here is pure: no Flutter, no I/O, no clock reads except where a value is passed in.

```dart
// ---------------------------------------------------------------- tree

@immutable
class MoveNode {
  final Move move;
  final String san;
  final IList<MoveNode> children;   // children.first == primary line
  final IList<String> comments;
  final IList<int> nags;
}

@immutable
class VariationTree {
  final Position initialPosition;
  final IList<MoveNode> children;

  bool get isEmpty;
  IList<MoveNode> get primaryLine;
  int get nodeCount;
  int get depth;

  Position positionAt(MovePath path);
  MoveNode? nodeAt(MovePath path);
  IList<Move> legalMovesAt(MovePath path);

  /// Appends [move] as a child at [at], or navigates to the existing child when
  /// that move is already recorded there (FR-007, FR-008).
  ///
  /// Throws [IllegalMoveError] if [move] is not legal in the position at [at].
  TreeEdit play(MovePath at, Move move);

  /// Moves the node at [path] to index 0 of its parent's children (FR-013).
  VariationTree promote(MovePath path);

  /// Removes the node at [path] and its subtree (FR-011).
  VariationTree delete(MovePath path);
}

/// Result of [VariationTree.play]: the new tree and where the cursor should sit.
/// [createdBranch] is for tests only and MUST NOT reach the UI — surfacing it
/// during training would announce the branch, violating FR-009.
@immutable
class TreeEdit {
  final VariationTree tree;
  final MovePath path;
  final bool createdBranch;
}

@immutable
class MovePath {
  final IList<int> indices;
  static const MovePath root = MovePath._(IList.empty());

  MovePath child(int index);
  MovePath? get parent;
  bool get isRoot;
  int get length;
}

// ------------------------------------------------------------- positions

@immutable
class TrainingPosition {
  final String id;
  final Position initialPosition;
  final VariationTree solution;
  final PositionMetadata metadata;

  Side get sideToMove;
}

@immutable
class PositionMetadata {
  final String? title;
  final String? goal;
  final IList<String> themes;
  final int? rating;
  final String? source;

  static const PositionMetadata empty;
}

/// The leak barrier (research D5). Deliberately has no path to a solution.
///
/// Do not add fields derived from [TrainingPosition.solution] or
/// [TrainingPosition.metadata]. That is the entire purpose of this type.
@immutable
class TrainingProjection {
  final String positionId;
  final Position initialPosition;
  final Side sideToMove;
  final int indexInSession;
  final int sessionLength;
}

// -------------------------------------------------------------- attempts

@immutable
class Attempt {
  final String positionId;
  final VariationTree tree;
  final Duration duration;
  final DateTime committedAt;
}

@immutable
class ComparisonResult {
  final int agreementLength;
  final int solutionLength;
  final Divergence? divergence;

  bool get ranShort;   // agreementLength < solutionLength && divergence == null
  bool get isComplete; // agreementLength == solutionLength && divergence == null
}

@immutable
class Divergence {
  final int ply;
  final String playedSan;
  final String expectedSan;
}

/// Compares primary lines only. Never inspects non-primary branches (FR-024).
ComparisonResult compareToSolution(VariationTree attempt, VariationTree solution);

// -------------------------------------------------------------- sessions

enum SessionPhase { setup, training, review, complete, abandoned }
enum GradeValue { failed, hard, good, easy }

@immutable
class Grade {
  final String positionId;
  final GradeValue value;
}

@immutable
class TrainingSession {
  final IList<TrainingPosition> positions;
  final IMap<String, Attempt> attempts;
  final IMap<String, Grade> grades;
  final SessionPhase phase;
  final int currentIndex;

  /// The ONLY way the training phase may read a position.
  TrainingProjection projectionFor(int index);

  TrainingSession commitAttempt(Attempt attempt);  // advances, or enters review
  TrainingSession abandon();                       // terminal, reveals nothing
  TrainingSession recordGrade(Grade grade);
  TrainingSession goToReviewPosition(int index);

  bool get allPositionsAttempted;
  bool get allPositionsGraded;
}
```

## Loading contract

```dart
/// Parses one bundled PGN into a training position (research D4).
///
/// Expects a [FEN] header for the starting position; falls back to the standard
/// initial position when absent. Mainline becomes the solution's primary line;
/// variations become sibling branches; {comments} become MoveNode.comments.
TrainingPosition parseTrainingPosition(String pgn, {required String id});

/// Converts a parsed dartchess tree into the domain tree, replaying from
/// [initialPosition] so every node's legality is checked at construction.
VariationTree fromPgnNode(PgnNode<PgnNodeData> node, Position initialPosition);

/// Inverse of [fromPgnNode]. Needed for round-trip tests, and by feature 003.
PgnNode<PgnNodeData> toPgnNode(VariationTree tree);
```

## Error contract

| Error | Raised when |
|---|---|
| `IllegalMoveError` | `play` is given a move not legal at the target path. Indicates a caller bug: the UI only offers legal destinations (research D6). |
| `InvalidPathError` | A `MovePath` does not address an existing node, e.g. a stale cursor after `delete`. |
| `PositionParseError` | A bundled PGN has an invalid FEN header or an illegal move in its mainline. Fails at load, loudly — a malformed sample position must never reach a session. |

## Invariants the tests must enforce

1. `play` with a move already recorded at that node returns a tree with the same
   `nodeCount` and a path to the existing child. No duplicate siblings. (FR-008)
2. `play` at a path with an existing different move leaves the original subtree untouched.
   (FR-007, Story 1 scenario 3)
3. `promote` changes only child ordering — `nodeCount` and the set of lines are unchanged.
4. `compareToSolution` distinguishes *diverged*, *ran short*, and *ran long*, and never
   reports a divergence for an attempt that merely stopped early.
5. `compareToSolution` on an empty attempt returns `agreementLength == 0`, no divergence.
6. `compareToSolution` is unaffected by any non-primary branch in either tree.
7. `TrainingProjection` built from a position with a full solution and rich metadata
   contains no value derived from either.
8. `commitAttempt` on the final position moves `phase` to `review`, and not before.
9. `abandon` from any phase yields `abandoned`, and no solution is readable afterwards.
10. Every node in a tree built by `fromPgnNode` holds a move legal in its parent position.
