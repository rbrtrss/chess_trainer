# Implementation Plan: Positions With No Author's Line

**Branch**: `005-engine-judged-positions` | **Date**: 2026-08-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-engine-judged-positions/spec.md`

## Summary

A study chapter with a position and no moves becomes trainable. Where no author said what the
answer is, an engine does.

The design rests on three decisions from [research.md](./research.md), and the first two were
settled by facts rather than taste:

- **The engine has to be on the device** (D1). Lichess's cloud evaluation returns the cached
  evaluation *if available* and `404` otherwise, and the positions this feature exists for — set
  up by hand, this afternoon, by one player — are exactly the ones nobody has analysed. The cheap
  option fails for the precise input that prompted the request.
- **It runs at import and never while a session exists** (D2). FR-017 forbids a training screen
  varying by latency and FR-019 forbids the player noticing engine work; a search running while
  someone calculates leaks through timing, battery and heat. Evaluating at import removes the
  question instead of managing it, and import is already the slow, explicit, progress-bearing
  operation the player asked for.
- **The engine's line is stored as the position's `solution`** (D3). `TrainingPosition.solution`
  is already a `VariationTree` and everything downstream consumes it — the review panes,
  `compareTrees`, the match indicator, the self-grade. Deliver the engine's line in that shape and
  review, comparison and grading need no changes at all, which is what keeps a feature with an
  engine in it small.

The rest follows: a fixed-depth single-threaded search so device tests repeat (D4), storage rather
than determinism as what actually satisfies "the same position reviews the same way" (D4), an
interface in front of the engine because the package is Android/iOS-only and host tests cannot
load it (D8), and one directory that nothing outside may import (D7).

**The size gate has been run and passed.** Adding the engine takes the arm64 install from 34.9 MB
to 79.7 MB, almost all of it one embedded neural network, and the owner accepted that in exchange
for a feature that needs no network at all (D10). **Seconds per position is still unmeasured** and
remains the first implementation task — it cannot be answered by a build, only by running the
engine on the phone.

## Technical Context

**Language/Version**: Dart 3.13.0 (bundled with Flutter 3.47.0)

**Primary Dependencies**: existing, unchanged, plus **`multistockfish` ^0.5.0 — adopted
2026-08-15** (lichess.org, GPL-3.0, Android and iOS), the binding published by the same team as
`dartchess` and `chessground`. The licence check the constitution requires passes for the same
reason theirs did. Adopted at the `sf16` flavour, with the neural network embedded, after the cost
was measured rather than estimated: the arm64 split APK goes 34.9 MB → 79.7 MB (research D10).

**Storage**: Drift, schema **v3** — the positions table gains what an evaluation needs. The
credential store and everything from features 002–004 are untouched.

**Testing**: `flutter test`, against a fake evaluator. **No test can load the real engine**: the
package supports Android and iOS only and the test VM is neither (D8). The real engine is
exercised by device tasks, and the seam is an interface, not a mock of a concrete class.

**Target Platform**: Android (phone). iOS must not be precluded, and `multistockfish` supports
both.

**Performance Goals**: unknown, and that is the point of the first task. Import currently does 330
positions in under three seconds; a fixed-depth search is expected to cost on the order of a
second per no-line position, which would be the slowest thing this app has ever asked a player to
wait for. Training and review performance must not change at all, because after import no engine
runs.

**Constraints**: no engine process may exist while a session does (D2). Nothing about an
evaluation may reach `lib/ui/training/`. Review must work with no network, which is free once the
engine is local. App size was the binding constraint and is now a known cost: 34.9 MB → 79.7 MB
per install, paid deliberately (D10).

**Scale/Scope**: one new domain concept (the source of a solution), one new data-layer directory,
one schema version, one widened rejection rule and one new one. No new screens.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | How this design satisfies it |
|---|---|---|
| **I. Delayed feedback (non-negotiable)** | PASS, and it is the whole design | The constitution requires a feature that risks leaking correctness to be **rejected at specification time**, and this feature introduces the strongest correctness the app has ever held. It is confined structurally rather than carefully: the engine runs only during import (D2), so while a session exists there is no engine to leak from — no latency, no battery, no heat. The evaluation is stored as the `solution`, which the training layer has never been able to reach because it consumes only `TrainingProjection` (D3). `layering_test.dart` gains the engine's identifiers for the training directory, and the guard test gains its hardest case. Worth noting the constitution anticipated this: its list of withheld evidence already names **"evaluation glyphs"**. |
| **II. Offline-first** | PASS, and strengthened | An on-device engine needs no network at all, so this feature adds *zero* network paths — the first content feature since 002 that does. Review works on a plane by construction. FR-009 keeps a session from ever waiting on an evaluation. |
| **III. Delegated chess correctness** | PASS, with a genuine addition | Legality, FEN, SAN and PGN stay `dartchess`'s, including the terminal-position test that D9 needs. What is new is a *second* kind of delegated chess authority: not what is legal, but what is good. That is an addition to the project's technology rather than a violation of the principle, and the constitution was **amended to v1.1.0 on 2026-08-15** to say so — which also made D2, D4, D7 and D9 constitutional requirements rather than design preferences. |
| **IV. Layering** | PASS | The engine is platform code and lives in `lib/data/engine/`, which `lib/domain/` and `lib/ui/` may not import — the same confinement, and the same enforcing test, that networking has had since 003. The new domain concept is a plain enum on a pure-Dart type. |
| **V. Testing floor** | PASS, and it grows | Everything on the floor stays covered. The floor's own item — "Study PGN → training position extraction, against real fixture files" — now has a second case, an entry with no moves, and gets a fixture for it. The Principle I guard test gains an engine-judged position alongside the hostile-metadata one. |
| **Licensing** | PASS | `multistockfish` is GPL-3.0, the same licence as this project and as `dartchess` and `chessground`, from the same publisher, adopted for the same reason. Checked before adoption, as the constitution requires. |
| **No secrets** | PASS, not engaged | No credentials, no keys. The engine talks to nothing. |
| **Complexity justified** | PASS, at a price that was measured before it was paid | Bundling a chess engine is the largest single dependency this project has taken on: **+44.8 MB, more than doubling the install**. The constitution's bar is a concrete problem rather than an anticipated one, and the problem is concrete — a study chapter the app refused, on a real device, on 2026-08-15. What makes this a pass rather than a shrug is that the number was obtained *before* anything was built on it, and the alternative that would have cost 1.5 MB was rejected on principle rather than overlooked (D10). |

**Post-design re-check (after Phase 1)**: PASS, and the one condition is now discharged — the size
was measured and the price accepted. Design did not add a network path, a screen, or a way for the
training layer to reach an evaluation. Two things
sharpened: the "no evaluation" case turned out to have somewhere to land already (D6), and the
decision to store the engine's line *as the solution* (D3) removed an entire second review path
that would have carried its own Principle I surface.

## Project Structure

### Documentation (this feature)

```text
specs/005-engine-judged-positions/
├── plan.md                    # This file
├── spec.md                    # Feature specification
├── research.md                # Phase 0 — decisions D1–D11, verified facts
├── data-model.md              # Phase 1 — the solution's source, schema v3
├── quickstart.md              # Phase 1 — how to run and validate
├── contracts/
│   └── evaluation-api.md      # Phase 1 — the evaluator seam and what it promises
├── checklists/
│   └── requirements.md        # Spec quality checklist
└── tasks.md                   # Phase 2 — created by /speckit-tasks, not here
```

### Source Code (repository root)

```text
lib/
├── domain/
│   ├── position/
│   │   └── training_position.dart   # CHANGED — the solution gains a source
│   └── library/
│       └── import_outcome.dart      # CHANGED — one reason retires, one arrives
├── data/
│   ├── engine/                      # NEW — the only directory that knows an engine exists
│   │   ├── evaluator.dart           # NEW — the interface, and the evaluation type
│   │   └── stockfish_evaluator.dart # NEW — the one implementation, UCI over the package
│   ├── pgn_position_parser.dart     # CHANGED — no moves stops being fatal
│   ├── import_parser.dart           # CHANGED — carries entries needing evaluation
│   ├── import_service.dart          # CHANGED — evaluation becomes a step of import
│   └── local/
│       ├── tables.dart              # CHANGED — schema v3
│       └── database.dart            # CHANGED — v2 → v3 migration
└── ui/
    └── review/
        └── tree_comparison_view.dart # CHANGED — say where the solution came from

test/
├── data/
│   ├── engine/
│   │   └── fake_evaluator.dart      # NEW — what every test uses
│   ├── evaluation_import_test.dart  # NEW — a no-moves entry becomes a position
│   ├── migration_test.dart          # CHANGED — v2 → v3 with history intact
│   └── pgn_position_parser_test.dart # CHANGED — no moves is no longer a rejection
├── domain/
│   └── layering_test.dart           # CHANGED — the engine joins the confined list
└── ui/
    ├── no_feedback_guard_test.dart  # CHANGED — an engine-judged position, guarded
    └── review_screen_test.dart      # CHANGED — provenance, and the empty case
```

**Structure Decision**: unchanged three layers. The engine gets its own directory under `lib/data/`
for the same reason `lichess/` has one — it is platform code with a protocol, and the value of a
single directory is that a test can assert nothing outside it knows.

## Implementation sequence

Ordered so the expensive, uncertain thing is settled first.

1. **Measure before adopting** (D10). Add a candidate package to a scratch build, measure the
   release APK's growth and the wall-clock cost of a fixed-depth search on the target phone.
   **This is a gate.** If the size is unacceptable the design needs revisiting, and that is worth
   knowing before anything else is built.
2. **The seam, with no engine behind it** (D8). Define the evaluator interface and the evaluation
   type; write the fake. Everything after this can be built and tested without a device.
3. **Domain and schema.** The solution's source on `TrainingPosition`; schema v3 and its
   migration, asserting that v2 data survives with its history.
4. **Import accepts no-moves entries** (D9, FR-001–FR-006). The parser stops rejecting them, the
   terminal-position rejection arrives, and the import pipeline gains an evaluation step driven by
   the fake.
5. **The real evaluator** — the one class that speaks UCI, behind the interface built in step 2.
6. **Review tells the truth about provenance** (D5, D6) — where the line came from, and the two
   different empty cases.
7. **Guards.** The training-directory rule gains the engine; the Principle I guard gains an
   engine-judged position; the "no engine while a session exists" claim gets a test.
8. **Device pass.** Import the study that prompted this, train it, review it, and measure what the
   import cost.

## Complexity Tracking

| Violation | Why needed | Simpler alternative rejected because |
|---|---|---|
| **Bundling a chess engine** — the largest dependency this project has taken, more than doubling the install at **+44.8 MB**, measured | The feature cannot exist without a source of correctness for positions that have none, and the only remote source available answers `404` for exactly these positions (D1) | *Lichess cloud eval*: documented to return the cached evaluation "if available", and a position a player invented today is never cached. *Tablebase*: seven pieces or fewer, and needs a network. *Requiring the player to enter a move*: the feature refusing to exist |
| **A second delegated chess authority**, beyond `dartchess` | Principle III delegates what is *legal*; nothing in the project can say what is *good*, and this feature's whole purpose is to say it where an author did not | Nothing else can answer. Hand-rolling evaluation is prohibited by the same principle and would be far worse |
| **A new rejection rule** (terminal positions) inside a feature whose purpose is to reject less | A checkmate position imports to a board the player cannot move on — a trap, discovered after training starts rather than at import where the report can explain it | Importing them and handling emptiness later spreads the special case across training and review instead of stating it once |

## Known risks

| Risk | Where it bites | What is done about it |
|---|---|---|
| ~~App size~~ **Resolved 2026-08-15** | The arm64 install goes 34.9 MB → 79.7 MB | Measured before adoption, and accepted by the owner in exchange for needing no network (D10). What remains is a smaller question for later: whether the two unused flavours, 3.2 MB of Fairy-Stockfish and network-less chess library, can be excluded |
| **Import duration** | A hundred hand-made positions could take a hundred seconds where 330 authored ones take three | Task 1 measures the per-position cost. D2's rejected alternative — evaluate in the background after import — is the recorded fallback, and it changes nothing the player sees |
| **The engine is a leak channel with no pixels** | Latency, battery and heat are noticeable, and no widget test can see any of them | D2 removes the channel rather than managing it: no engine runs while a session exists. Task 7 tests the claim directly |
| **An engine line is correct but not instructive** | The player is shown a machine's first choice where they expected a human's point | D5 records provenance and review says which it is. Not solvable beyond honesty |
| **Host tests cannot touch the engine** | Everything about the real implementation is unverifiable off-device | D8's interface means only one class is unverifiable, and the device pass targets exactly it |
| ~~The constitution does not contemplate an engine~~ **Resolved 2026-08-15** | — | Amended to v1.1.0 with the rationale, version bump and specification review its own procedure requires. Four consequences were found and recorded, including two source comments that become false when this feature lands |
