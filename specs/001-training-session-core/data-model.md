# Data Model: Training Session Core

**Date**: 2026-08-12 | **Feature**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

All types live in `lib/domain/` and are pure Dart: no Flutter imports, no I/O. `dartchess`
is permitted here because it is a pure Dart library and is the constitution's designated
authority on chess rules (Principle III).

Everything below is immutable and has value equality. Value equality is not decoration —
Principle V's required tests on tree construction and comparison depend on it.

---

## MoveNode

One move and the alternatives considered after it.

| Field | Type | Notes |
|---|---|---|
| `move` | `Move` | The dartchess move. |
| `san` | `String` | SAN in the *parent's* position. Node identity for comparison. |
| `children` | `IList<MoveNode>` | Continuations. **`children.first` is the primary line.** |
| `comments` | `IList<String>` | Review-only prose (FR-022). Empty for user attempts. |
| `nags` | `IList<int>` | Review-only annotation glyphs. Empty for user attempts. |

**Invariants**
- `san` is legal in the parent position. Enforced at construction by replaying from the
  root; a node cannot be built for an illegal move.
- No two children of the same node share a `san` (FR-008 — replaying an existing move
  navigates rather than duplicates).
- `children` order is meaningful: index 0 is primary (FR-012).

## VariationTree

The root. Holds a starting position and the forest of first moves.

| Field | Type | Notes |
|---|---|---|
| `initialPosition` | `Position` | The position being analysed. |
| `children` | `IList<MoveNode>` | First moves. `children.first` is the primary line. |

**Derived**
- `primaryLine` → `IList<MoveNode>`: follow `children.first` from the root until exhausted.
  This is what FR-021 and FR-023 measure.
- `isEmpty`: no children. A valid committed attempt (spec edge case: "I have no idea").
- `positionAt(MovePath)` → `Position`: replay from `initialPosition` (D2).
- `nodeCount`, `depth`: for SC-006.

**Operations** — all return a new tree.

| Operation | Behaviour |
|---|---|
| `play(MovePath at, Move)` | Appends a child at `at`, **or** returns the path to the existing child when that move is already recorded (FR-007, FR-008). |
| `promote(MovePath)` | Moves the addressed node to index 0 of its parent's children (FR-013). |
| `delete(MovePath)` | Removes the addressed node and its subtree (FR-011). |

## MovePath

Address of a node: `IList<int>` of child indices from the root. The empty path is the root
(D3). Value-comparable, and readable in test failure output.

Paths are invalidated by `promote` and `delete`; the editor recomputes its cursor after any
structural change.

## TrainingPosition

A position to be trained, with everything known about it.

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Stable identifier. |
| `initialPosition` | `Position` | Where training starts. |
| `sideToMove` | `Side` | Derived from `initialPosition`; the **only** fact disclosed during training. |
| `solution` | `VariationTree` | Intended answer. Mainline = `primaryLine`. |
| `metadata` | `PositionMetadata` | **Withheld during training** (FR-003), revealed at review (FR-025). |

## PositionMetadata

Isolated in its own type precisely so that "everything that must be hidden" is one
importable thing rather than a list to remember.

| Field | Type |
|---|---|
| `title` | `String?` |
| `goal` | `String?` |
| `themes` | `IList<String>` |
| `rating` | `int?` |
| `source` | `String?` |

## TrainingProjection

What the training layer is given. **The leak barrier** (D5).

| Field | Type |
|---|---|
| `positionId` | `String` |
| `initialPosition` | `Position` |
| `sideToMove` | `Side` |
| `indexInSession` | `int` |
| `sessionLength` | `int` |

It has no reference to `solution` or `metadata`, and no method that could reach them.
Solution knowledge cannot leak into the training UI because it is not in scope there.

## Attempt

A committed analysis. Immutable by construction, satisfying FR-015.

| Field | Type | Notes |
|---|---|---|
| `positionId` | `String` | |
| `tree` | `VariationTree` | Frozen at commit. |
| `duration` | `Duration` | Time spent. |
| `committedAt` | `DateTime` | |

## ComparisonResult

Derived at review. **Advisory only** (FR-027).

| Field | Type | Notes |
|---|---|---|
| `agreementLength` | `int` | Plies where the attempt's primary line matched the solution's. |
| `solutionLength` | `int` | Plies in the solution mainline. Denominator for "matched 4 of 6". |
| `divergence` | `Divergence?` | Null when the attempt agreed as far as it went. |

`Divergence` carries `ply`, `playedSan`, `expectedSan`.

**Computation** — walk both primary lines in lockstep comparing `san`, stopping at the
first mismatch or when either runs out.

Three outcomes must stay distinguishable, per the spec's edge cases:
- **Diverged**: a move differs → `divergence` set.
- **Ran short**: attempt ended while the solution continued → `divergence` null,
  `agreementLength < solutionLength`. This is *not* a wrong move and must not be shown as one.
- **Ran long**: attempt continued past the solution → `agreementLength` capped at
  `solutionLength`; extra moves neither credited nor faulted.

The empty attempt yields `agreementLength: 0` with no divergence.

Non-primary branches are never examined (FR-024). Without an engine there is no basis to
judge them, which is the whole reason the self-grade outranks this type.

## Grade

The authoritative assessment (FR-027).

| Field | Type | Notes |
|---|---|---|
| `positionId` | `String` | |
| `value` | `GradeValue` | `failed`, `hard`, `good`, `easy`. |

The four values are chosen to match SM-2's grade bands so feature 005 can consume them
without a migration. Nothing in this feature interprets them.

## TrainingSession

| Field | Type | Notes |
|---|---|---|
| `positions` | `IList<TrainingPosition>` | Fixed at start. |
| `attempts` | `IMap<String, Attempt>` | By position id. |
| `grades` | `IMap<String, Grade>` | By position id. |
| `phase` | `SessionPhase` | |
| `currentIndex` | `int` | |

### State machine

```
          start                commit (last position)            all graded
  setup ─────────► training ──────────────────────────► review ──────────────► complete
                      │                                    │
                      │ commit (not last) ──┐              │ next / previous ──┐
                      │ ◄───────────────────┘              │ ◄─────────────────┘
                      │
                      └── abandon ──► abandoned  (no answers revealed — FR-019)
```

**Transition rules**
- `training → review` only when every position has an attempt (FR-018).
- `abandoned` is terminal and reveals nothing.
- Review permits free movement between positions (FR-028); grading does not gate navigation.
- `projectionFor(index)` is the **only** way the training phase reads a position, and it
  returns `TrainingProjection`.

## Relationships

```
TrainingSession
├── positions   ──► TrainingPosition ──┬─► VariationTree (solution) ──► MoveNode*
│                                      └─► PositionMetadata      [hidden until review]
├── attempts    ──► Attempt ──────────────► VariationTree (user)  ──► MoveNode*
└── grades      ──► Grade

TrainingProjection ◄── projectionFor(index)   [no path to solution or metadata]
ComparisonResult   ◄── compare(attempt.tree, position.solution)   [review only]
```

## Not modelled here

No persistence, no schema, no serialisation of sessions — this feature is in-memory only.
`TrainingPosition` is loaded from bundled PGN (D4); everything else lives and dies with the
process. Persistence arrives with a later feature.
