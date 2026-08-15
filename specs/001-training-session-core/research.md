# Research: Training Session Core

**Date**: 2026-08-12 | **Feature**: [spec.md](./spec.md)

Findings are from reading the installed package sources at
`~/.pub-cache/hosted/pub.dev/dartchess-0.13.1` and `chessground-10.1.1`, not from
published documentation, which was too vague to design against.

## Verified package facts

These were confirmed by source inspection and drive several decisions below.

**dartchess 0.13.1**

| API | Signature / behaviour |
|---|---|
| `Position.play(Move)` | Returns a **new** `Position`. Positions are immutable. |
| `Position.parseSan(String)` | `Move?` — null when the SAN is not legal here. |
| `Position.toSan(Move)` | SAN for a legal move in this position. |
| `Position.isLegal(Move)` | Legality check. |
| `Position.isGameOver` / `isCheckmate` / `isStalemate` / `isInsufficientMaterial` | Terminal detection. |
| `makeLegalMoves(Position)` | `Map<Square, Set<Square>>` — in `utils.dart`. Exactly chessground's `ValidMoves` type. |
| `PgnNode<T>.children` | `final List<PgnChildNode<T>>` — the **list is mutable**; `children[0]` is the mainline. |
| `PgnNode<T>.mainline()` | `Iterable<T>` following first children. |
| `PgnNode<T>.transform<U,C>(ctx, f)` | Tree map with a threaded context. |
| `PgnChildNode<T>.data` | Documented as a **mutable** field. |
| `PgnNodeData` | `san`, `startingComments`, `comments`, `nags` — the last three mutable. |
| `PgnGame.parsePgn` / `makePgn()` | Full PGN with variations, comments and NAGs. |

**chessground 10.1.1**

| API | Signature / behaviour |
|---|---|
| `Chessboard({size, controller, orientation, settings, onMove, onTouchedSquare, shapes, annotations})` | The interactive board. |
| `onMove(Move, {bool? viaDragAndDrop})` | Fires **once**, after promotion is resolved internally. |
| `ChessboardController({required GameData game})` | `ChangeNotifier`; `updatePosition(...)`; must be disposed. |
| `GameData({fen, playerSide, sideToMove, validMoves, lastMove, kingSquareInCheck, ...})` | Immutable board snapshot. |
| `PlayerSide.none` | Makes the board non-interactive — used for review. |
| `annotations: Map<Square, Annotation>`, `shapes: Set<Shape>` | Symbols and arrows drawn over the board. |

The last row matters: `annotations` and `shapes` are the two parameters through which
solution knowledge could reach the training board. They are named explicitly in the
Constitution Check.

---

## D1. Representation of a variation tree

**Decision**: Define an immutable `VariationTree` in `lib/domain/`, and convert to and from
dartchess's `PgnNode` at the data boundary.

**Rationale**: Three concrete problems block using `PgnNode` directly as the domain type.

1. FR-015 requires a committed attempt to be immutable. `PgnNode.children` is a mutable
   list and `PgnChildNode.data` is documented as mutable, so any holder of a committed
   attempt could silently alter it. Freezing is not expressible.
2. `PgnNode` has no value equality. Principle V requires unit tests on tree construction,
   branching, and comparison; without value equality those assertions become manual
   recursive walks in every test.
3. The domain type wants a stable notion of "path to a node" for cursor navigation, which
   `PgnNode` does not provide.

These are present problems, not anticipated ones, so the added type clears the
constitution's bar for justified complexity.

**Alternatives considered**:
- *Use `PgnNode` throughout* — rejected for the three reasons above.
- *Wrap `PgnNode` in an immutable facade* — rejected: the mutable interior remains
  reachable, so the guarantee is cosmetic.

**Consequence**: Conversion functions are needed in both directions. They are small (SAN is
the node identity in both representations) and pay for themselves immediately: the solution
side of this feature is authored as PGN and parsed with `PgnGame.parsePgn`, which is the
same code path feature 003 will use for Lichess studies.

## D2. Where positions come from while walking a tree

**Decision**: Nodes store the `Move` and its SAN. Positions are recomputed by replaying
from the root; the current `Position` is held by the cursor, not by the node.

**Rationale**: Keeps nodes small, value-comparable, and trivially serialisable later.
`Position.play` is cheap and trees in this feature are bounded by SC-006 at roughly 40
moves. Caching positions in nodes would trade a real invariant (nodes are plain values) for
a performance gain nothing has asked for.

**Alternatives considered**: storing a FEN or a `Position` per node — rejected as premature,
and FEN-per-node introduces a second source of truth that can disagree with the move list.

## D3. Node addressing

**Decision**: A node is addressed by `MovePath` — the list of child indices from the root.

**Rationale**: Cheap to compute, value-comparable, human-readable in test failures, and
promotion (FR-013) is expressible as reordering a child list, which is exactly what a
"primary line = `children[0]`" model needs.

**Trade-off, accepted**: paths shift when a branch is promoted or deleted. The editor holds
one cursor, and it is recomputed after any structural edit. This is simpler than stable node
ids and the tree is small.

## D4. How the solution is authored for bundled positions

**Decision**: Each bundled position is a **PGN string** with a `[FEN]` header, variations,
and `{}` comments, parsed at load with `PgnGame.parsePgn`.

**Rationale**: This is the strongest reuse decision available. Feature 003 imports Lichess
studies, which are PGN with exactly these constructs. Authoring the sample positions as PGN
means the parse-and-convert path is built, exercised, and unit-tested in feature 001, and
feature 003 becomes a fetch plus a chapter split rather than new parsing work. Comments in
the PGN become the review annotations required by FR-022 at no extra cost.

**Alternatives considered**: a bespoke JSON schema for positions — rejected; it would need
its own parser, its own tests, and would be thrown away when feature 003 arrived.

## D5. Preventing feedback leaks structurally

**Decision**: The training screen's state object **does not contain the solution**. The
session holds solutions; it hands the training layer a projection carrying only the starting
position, the side to move, and the session counter.

**Rationale**: Principle I is the requirement most likely to be violated accidentally, months
later, by a well-meaning change — and a violation leaves every test green and the app
looking fine. Making the solution unreachable from the training layer converts a discipline
problem into a compile-time one: leaking code will not compile because the data is not in
scope.

The accompanying guard test then has something narrow and durable to assert: that the
training projection type exposes no solution-derived field, and that the board is
constructed with empty `annotations` and `shapes`.

**Alternatives considered**: passing the full position and relying on review discipline —
rejected; this is precisely the failure mode Principle I exists to prevent.

## D6. Illegal move handling

**Decision**: Illegal moves are not rejected — they are unreachable. The board receives
`validMoves` from `makeLegalMoves(position)`, so illegal destinations cannot be dropped on.

**Rationale**: Satisfies FR-005 by construction. A rejection message is a channel that could
vary with the position; having no rejection at all removes the channel. This also means
FR-005's "identically in all cases" is trivially true.

## D7. State management

**Decision**: Riverpod, with the tree editor as a `Notifier` exposing an immutable
`AnalysisEditorState` (tree, cursor path, current position, legal moves).

**Rationale**: Mandated by the constitution's stack section; also what Lichess Mobile uses,
so their open-source app is a usable reference. An immutable state object per frame pairs
naturally with D1.

## D8. Testing the "no leak" property

**Decision**: Three layers, weakest to strongest.

1. **Type-level** (strongest): D5 makes solution data absent from the training layer.
2. **Unit**: assert the training projection built from a position with a rich solution and
   metadata contains none of it.
3. **Widget**: pump the training screen, play a move matching the solution and a move that
   does not, and assert the two resulting widget trees are identical apart from the piece
   placement — plus that `annotations` and `shapes` are empty.

**Rationale**: Layer 3 alone is brittle and easy to weaken over time. Layer 1 alone is
invisible to a reviewer. Together they make the property both enforced and legible.

## Open items carried from the spec checklist

- **SC-005** (nine of ten first-time users understand they must move for the opponent) is
  not verifiable with one user. It is retained as a design prompt. The plan's answer is a
  neutral, always-present turn indicator on the training screen; whether that is sufficient
  can only be settled by watching someone use it.
- **FR-013 (branch promotion)** is load-bearing, not polish: the match indicator in FR-023
  compares *primary* lines, so the user's control over which line is primary determines
  what gets measured. It is scheduled in the same slice as the comparison, not after it.
