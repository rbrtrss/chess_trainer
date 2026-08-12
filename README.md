# Chess Trainer

An Android app for calculation training that **withholds all feedback until the session
is over**.

It shows a position and tells you exactly one thing: whose turn it is. You lay out your
whole analysis as a tree of variations — playing moves for both colours, stepping back and
trying other ideas — and commit. Nothing reacts. The next position appears. Only after the
last one does the app reveal anything: your tree beside the solution, where the two first
parted company, the author's notes, and a self-grade you record yourself.

Every mainstream puzzle app does the opposite. The instant green-check/red-cross loop is
the habit this app exists to break.

## Status

Feature 001, *Training session core*, is implemented: the complete training loop over three
bundled sample positions, with no network, no accounts, and no persistence. A session lives
and dies with the process.

See [`specs/001-training-session-core/`](specs/001-training-session-core/) for the
specification, plan, and task breakdown.

## Running it

The toolchain lives under `$HOME` and is exported from `~/.bashrc`:

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$HOME/development/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
```

```bash
flutter pub get
flutter test          # the fast loop — no device needed
flutter run           # on a connected Android phone
```

[`specs/001-training-session-core/quickstart.md`](specs/001-training-session-core/quickstart.md)
has the by-hand validation scenarios, including the offline pass.

## Layout

```
lib/domain/   pure Dart — the tree, the comparison, the session state machine.
              Zero Flutter imports; this is where the tests live.
lib/data/     the PGN parser and the bundled-position loader.
lib/ui/       screens and Riverpod notifiers. Depends inward.
assets/positions/   the sample positions, authored as PGN.
```

The layering is enforced by `test/domain/layering_test.dart`, not by convention.

## Contributing, and the one rule

[`.specify/memory/constitution.md`](.specify/memory/constitution.md) governs this
repository. Principle I is non-negotiable, and it constrains ordinary-looking changes more
than it first appears:

> No part of the training experience may signal whether a move is good, bad, expected, or
> unexpected before the session reaches its review phase.

Concretely, during training nothing may vary with the correctness of the user's input —
not colour, icon, sound, haptic, animation, arrow, board highlight, move-list styling,
progress indicator, latency, or wording. Position metadata is evidence and is withheld
too: themes, ratings, chapter titles, comments, and evaluation glyphs are stored but never
rendered on a training screen. "Chapter 3: Winning the Opposition" tells the user the
answer, and so does a `!!`.

Three things defend that rule, weakest to strongest:

1. **The type system.** The training layer is handed a `TrainingProjection`, which has no
   field derived from the solution or the metadata and no reference back to the position it
   came from. Leaking code does not compile, because the data is not in scope. Do not add a
   field to that type.
2. **`test/domain/training_projection_test.dart`**, which builds two positions differing
   only in solution and metadata and asserts their projections are indistinguishable.
3. **`test/ui/no_feedback_guard_test.dart`**, which plays the solution's move and a
   pointless one and asserts the two screens render identically apart from the pieces.

If a change makes any of those fail, the change is wrong — not the test.

## Licence

GPL-3.0. `chessground` and `dartchess` are the Lichess team's GPL-3.0 packages, and using
them is a deliberate, accepted consequence: they give this project a variation-aware PGN
parser and a production chessboard. Every new dependency must be licence-checked for
GPL-3.0 compatibility before adoption.
