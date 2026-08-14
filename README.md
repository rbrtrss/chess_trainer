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
bundled sample positions, with no network and no accounts.

Feature 002, *Session persistence*, is implemented: what the loop commits is durable. An
interrupted session is offered back when the app reopens and resumes at the same position
with every committed attempt intact, and finished sessions stay readable afterwards, each
carrying its own frozen copy of the solutions and notes it was played against. Uncommitted
analysis is deliberately not stored — an interruption costs the position you were part way
through, and the app says so rather than presenting an empty board as a fault.

There is still no scheduling, and nothing anywhere shows how a position has gone for you
before. The grades are recorded; displaying them across sessions is the one thing that would
put evidence about a position in front of a player who is still calculating, so it is left to
the feature that has to argue for it.

See [`specs/001-training-session-core/`](specs/001-training-session-core/) and
[`specs/002-session-persistence/`](specs/002-session-persistence/) for the specifications,
plans, and task breakdowns.

## Running it

The toolchain lives under `$HOME` and is exported from `~/.bashrc`:

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$HOME/development/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
```

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test          # the fast loop — no device needed
flutter run           # on a connected Android phone
```

The `build_runner` line is not optional and not a one-off. The database schema in
`lib/data/local/` is code-generated, and the generated files are gitignored on purpose, so
**a fresh clone does not compile until it has been run**. The symptom is an error pointing
at the generated file rather than at the missing step:

```
Target of URI hasn't been generated: 'database.g.dart'
```

Re-run it after any change to `lib/data/local/tables.dart` or `database.dart`; while working
on the schema, `dart run build_runner watch` is less tedious.

Changing the schema also means re-recording it, so the migration test keeps a version to
migrate *from*. Unlike the `build_runner` output, these two are committed:

```bash
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

The quickstarts have the by-hand validation scenarios:
[001](specs/001-training-session-core/quickstart.md) for the training loop and the offline
pass, [002](specs/002-session-persistence/quickstart.md) for killing the app mid-session and
for installing a new build over an existing one.

## Layout

```
lib/domain/   pure Dart — the tree, the comparison, the session state machine.
              Zero Flutter imports; this is where the tests live.
lib/data/     the PGN parser, the bundled-position loader, and the storage
              interface. lib/data/local/ holds the Drift schema and is the only
              place that knows SQLite exists.
lib/ui/       screens and Riverpod notifiers. Depends inward.
assets/positions/   the sample positions, authored as PGN.
drift_schemas/      committed schema snapshots, so a future version has
                    something to migrate from.
```

The layering is enforced by `test/domain/layering_test.dart`, not by convention — including
the rule that nothing under `lib/ui/training/` may read grade data, which is what stops the
stored history growing a display on the one screen it must never reach.

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
   pointless one and asserts the two screens render identically apart from the pieces — and,
   since persistence arrived, that a *resumed* session's training screen is identical to a
   fresh one at the same point.

If a change makes any of those fail, the change is wrong — not the test.

## Licence

GPL-3.0. `chessground` and `dartchess` are the Lichess team's GPL-3.0 packages, and using
them is a deliberate, accepted consequence: they give this project a variation-aware PGN
parser and a production chessboard. Every new dependency must be licence-checked for
GPL-3.0 compatibility before adoption.
