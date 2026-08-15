# Phase 1 Data Model: Positions With No Author's Line

**Feature**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

## The short version

A position gains **where its solution came from**, and an engine-judged one gains **what the
engine said**. The solution itself does not change shape: an engine's principal variation is
stored as the same `VariationTree` an author's line produces, which is what lets review,
comparison and grading stay exactly as they are (research D3).

Schema goes to **v3**. Features 002's four tables and 003's three are otherwise untouched.

---

## Entities

### `SolutionSource` — new, `lib/domain/position/evaluation.dart`

An enum on the position, saying what standard the attempt is measured against.

| Value | Means |
|---|---|
| `author` | The source PGN contained moves. Everything behaves as it did before this feature. |
| `engine` | The source declared a position and no moves; the line stored is an engine's. |
| `none` | The source declared a position and no moves, and no evaluation could be produced (FR-010). The solution tree is empty. |

`none` is a state, not an error. It is what the player has when the engine could not answer, and
FR-010 requires the position to remain trainable in it.

### `PositionEvaluation` — new, `lib/domain/position/evaluation.dart`

What the engine determined about the starting position. Pure Dart; no engine types leak into the
domain.

| Field | Holds |
|---|---|
| `score` | Either a centipawn assessment or a forced mate in *n*. One type that can be both, because "+1.4" and "mate in 3" are different kinds of claim and a single number cannot carry the second. |
| `depth` | The search depth the line came from — the instrument, recorded with the reading (research D5). |
| `perspective` | Whose advantage the score describes. Stored explicitly rather than implied by side to move, because a stored value read a year later should not need a convention to interpret. |

Held with the position, read only at review. Not on `TrainingProjection`, which is the type the
training screen consumes and which gains nothing in this feature.

### `TrainingPosition` — changed

Gains `solutionSource` and an optional `evaluation`. `solution` keeps its type and meaning: the
standard this attempt is measured against.

### `RejectionReason` — changed

| Change | Value | Why |
|---|---|---|
| **Retires** | `noMoves` | This feature exists to stop rejecting these (FR-001). The value is removed rather than left unused, so nothing can produce it by accident |
| **Arrives** | `noLegalMoves` | Checkmate, stalemate or any terminal position: nothing to calculate, and importing it would produce a board the player cannot move on (FR-004, research D9) |

`noStartingPosition`, `illegalMove`, `unsupportedVariant` and `unparseable` are unchanged, which
is what SC-003 asserts.

---

## Stored schema v3

### `positions` — three columns added

| Column | Type | Holds |
|---|---|---|
| `solution_source` | text, not null | `author`, `engine` or `none`. Existing rows migrate to `author` |
| `evaluation_json` | text, nullable | The evaluation, or null. Null for every authored position and for `none` |
| `engine_id` | text, nullable | What produced it — the engine's name and version, and the search budget |

`engine_id` exists so a position imported by one build is not silently compared with one imported
by another. It is the same instinct as `depth` on the evaluation, one level up: a stored answer
should say what produced it.

Nothing else in the table changes. `solution_pgn` still holds the whole tree, and an engine's line
is a tree like any other.

### The v2 → v3 migration

- Add the three columns.
- Set `solution_source` to `author` for every existing row. That is true of all of them: before
  this feature, a stored position could only exist if the source had moves.
- Touch nothing else. No re-parse, no re-evaluation, no re-import.

**What the migration test must assert** (FR-021, FR-022): a v2 database with played sessions
upgrades with its history intact, every existing position reads back identically, and every one
of them reads as `author`.

### What is deliberately not stored

- **Evaluations of the player's moves.** The player's line is not known at import, and evaluating
  it at review would mean running an engine after training — the thing D2 exists to avoid. Review
  says where the two lines part, which is what FR-013 asks for, using the comparison built in 001.
- **An evaluation per node of the solution.** One assessment of the starting position, and the
  line from it. Anything more is an analysis board, which is out of scope.
- **Anything for authored positions.** FR-011. Where an author said what they intended, that
  remains the standard, and `evaluation_json` stays null.

---

## How a position gets its source

```text
                        entry parsed from PGN
                                 │
                   ┌─────────────┴─────────────┐
              has moves                   no moves
                   │                           │
            SolutionSource                position terminal?
              .author                    ┌──────┴──────┐
        (evaluation null)              yes             no
                                         │              │
                                  REJECTED as      ask the evaluator
                                 noLegalMoves           │
                                              ┌─────────┴─────────┐
                                        answered            could not answer
                                              │                    │
                                   SolutionSource.engine   SolutionSource.none
                                   solution = the PV       solution = empty
                                   evaluation = stored     evaluation = null
```

Two properties of this diagram are the feature:

- **The terminal check happens before the engine is asked.** `dartchess` answers it and the engine
  is not started for a position that cannot be trained anyway (research D9).
- **"Could not answer" is a normal outcome with a defined resting place**, not an exception that
  fails the import. One position failing to evaluate must not cost the player the other 329.

---

## Who may read what

| Reader | Sees | Must not see |
|---|---|---|
| `lib/domain/` | `SolutionSource`, `PositionEvaluation`, `TrainingPosition` | the engine, the package, UCI, any of it |
| `lib/data/engine/` | everything about the engine | — |
| rest of `lib/data/` | the evaluator **interface** only | the implementation |
| `lib/ui/review/` | the solution, its source, the evaluation | — |
| **`lib/ui/training/`** | **none of it** | `SolutionSource`, `PositionEvaluation`, the solution, the engine |

The last row is the one that matters, and it is enforced rather than intended:
`layering_test.dart` already forbids the training directory from naming the solution, metadata,
grades, collections and the account. The engine's identifiers join that list.
