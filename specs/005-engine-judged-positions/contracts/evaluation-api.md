# Contract: the evaluator

**Feature**: [spec.md](../spec.md) | **Research**: [research.md](../research.md) |
**Data model**: [data-model.md](../data-model.md)

The seam between the app and a chess engine, and what each side promises. There is one interface,
one real implementation, and one fake — and the fake is what every test uses, because the package
runs on Android and iOS only and the test VM is neither (research D8).

---

## 1. Domain types

```dart
// lib/domain/position/evaluation.dart — pure Dart, no engine types

enum SolutionSource { author, engine, none }

sealed class Score {
  const Score();
}

/// A positional assessment, in centipawns, from [Evaluation.perspective].
final class Centipawns extends Score {
  const Centipawns(this.value);
  final int value;
}

/// A forced mate in [plies]. Not expressible as a number of pawns, which is why
/// Score is sealed rather than an int.
final class MateIn extends Score {
  const MateIn(this.plies);
  final int plies;
}

@immutable
class Evaluation {
  const Evaluation({
    required this.score,
    required this.depth,
    required this.perspective,
  });

  final Score score;
  final int depth;
  final Side perspective;
}
```

No engine type, no UCI string, no process handle reaches the domain. `Side` is `dartchess`'s,
which the domain already depends on.

---

## 2. The evaluator

```dart
// lib/data/engine/evaluator.dart

abstract interface class Evaluator {
  /// The engine's opinion of [position], or null if it has none to give.
  ///
  /// Returning null is a normal outcome (FR-010) — the engine is unavailable,
  /// the platform has none, it failed to start, it timed out. Callers store
  /// SolutionSource.none and carry on. **It must not throw for these**: one
  /// position failing must not cost an import its other entries.
  Future<EngineLine?> bestLine(Position position);

  /// What produced these answers — name, version and search budget — stored
  /// beside them so a position imported by one build is not silently compared
  /// with one imported by another (research D5).
  String get engineId;

  Future<void> dispose();
}

/// A principal variation and what the engine made of the position it starts from.
class EngineLine {
  const EngineLine({required this.moves, required this.evaluation});

  /// The principal variation, capped (§4). Legal from the position asked about.
  final IList<Move> moves;

  final Evaluation evaluation;
}
```

### What the caller may rely on

1. **`bestLine` never throws.** Every failure is a `null`. The import of 330 positions must not
   die because one of them upset the engine.
2. **The moves are legal** from the position given, in order. The caller replays them into a
   `VariationTree` and a replay that fails is a defect in the implementation, not a case to
   handle.
3. **The moves are capped** at the length in §4, so a caller never receives forty plies of engine
   soliloquy to present as "the solution".
4. **Calls are safe to make in sequence.** The package permits one engine instance at a time, so
   the implementation serialises internally; the caller does not coordinate.
5. **`engineId` is stable** for the lifetime of a build and changes when the engine or the budget
   changes.

### What the implementation may rely on

1. **It is never called during a session.** Evaluation happens at import (research D2). An
   implementation may assume it is not competing with a training screen — and if that assumption
   is ever broken, FR-017 is broken with it.
2. **The position is not terminal.** The caller rejects checkmate and stalemate before asking
   (research D9), so the engine is never started for a position with no legal move.

---

## 3. The one real implementation

`lib/data/engine/stockfish_evaluator.dart` — the only file in the project that knows an engine
exists.

| Setting | Value | Why |
|---|---|---|
| `Threads` | `1` | A multi-threaded search is not reproducible even at fixed depth; threads race to fill the shared table. Device tests need to repeat (research D4) |
| Search | fixed **depth**, not time | A time budget returns different lines on a busy phone than on an idle one |
| `Hash` | small, fixed | This is a phone, and one position at a time |

**Reproducibility is not what makes SC-008 true.** Storage is. A stored answer survives an engine
upgrade that would otherwise change what the same position says; determinism only makes the tests
repeatable. See research D4.

---

## 4. Fixed values

| Value | Setting | Rationale |
|---|---|---|
| Principal variation cap | **12 plies** | Authored solutions in this app run to about nine moves. Beyond a dozen plies an engine line is mostly its own hypothesis, and presenting it as "the solution" overstates it |
| Search depth | **set by measurement, not here** | Task 1 measures cost per position on the target device (research D10). A number chosen before that would be a guess with a decimal point |
| Per-position timeout | **yes, and generous** | A hung engine must degrade to `null` and `SolutionSource.none`, not to an import that never finishes |

---

## 5. What review shows

| Position | Solution pane | Also shown |
|---|---|---|
| `author` | the author's line, exactly as before this feature | nothing new (FR-015) |
| `engine` | the engine's line | that it came from an engine, and the evaluation of the starting position (FR-012, D5) |
| `none` | the existing empty state | that no evaluation could be produced — distinct from "the author recorded none" (FR-010, D6) |

`tree_comparison_view.dart` already renders an empty solution as **"No solution was recorded."**
That wording now covers two different situations and must distinguish them: an author who wrote
none, and an engine that could not answer. Same house style as every other message here — what
happened, and what the player can do.

**The comparison itself does not change.** `compareTrees` reports where the attempt's primary line
parts from the solution's, and that is FR-013 whichever produced the solution.

---

## 6. Invariants the tests hold

1. An entry with a starting position and no moves imports as a trainable position (FR-001).
2. An entry with no starting position is still rejected, with the reason unchanged (FR-002, SC-003).
3. A terminal position is rejected as `noLegalMoves` and the engine is **never asked about it**
   (FR-004, D9).
4. An evaluator returning null for one entry leaves the rest of the import untouched, and that
   entry trainable (FR-010).
5. Nothing under `lib/ui/training/` names `SolutionSource`, `Evaluation`, `Score`, `Evaluator`, or
   anything under `lib/data/engine/` (FR-020, D7).
6. Nothing outside `lib/data/engine/` imports the engine package (D7).
7. **No evaluator method is called during a session** — setup, training, commits, review or
   resume — asserted the way `no_network_during_training_test.dart` asserts it of the network: an
   evaluator that fails the test on contact, and a control proving it would fire if called
   (FR-019, D2).
8. A training screen renders identically for an engine-judged and an authored position, compared
   through what a screen reader would announce (FR-016, SC-004).
9. A v2 database migrates with its sessions intact and every existing position reading as
   `author` (FR-021, FR-022).
