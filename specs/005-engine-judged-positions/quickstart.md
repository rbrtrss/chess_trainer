# Quickstart: Positions With No Author's Line

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

How to build, run and validate this feature. Scenario numbers map to the requirements they prove,
so a scenario that fails names the requirement that broke.

## Before anything else: the measurement gate

**This feature is not authorised until two numbers exist**, and neither does today (research D10).
Do this first, on a scratch branch, before writing a line of the design:

```bash
flutter build apk --release            # record the size now — 75.1 MB on 2026-08-15
# add the candidate package, rebuild, and record the size again
flutter build apk --release
```

Then measure a fixed-depth search on the target phone — a handful of representative positions,
timed — and write both numbers into `research.md` under D10.

**If the app grows more than the project is willing to carry, stop and say so.** The design is
built to be revisited at this point and nowhere later, and finding out in an afternoon is the
whole reason this is first.

## Prerequisites

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$HOME/development/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

flutter pub get
dart run build_runner build --delete-conflicting-outputs   # schema v3 — required
flutter test
```

The `build_runner` step is **not** optional here: this feature moves the schema to v3, so the
generated database code must be rebuilt even on a clone that already worked. CI does this on every
push and is the standing check that these instructions are true.

## What is new in the build

### 1. An engine ships inside the app

The first native binary this project has carried, and the first dependency whose cost is measured
in megabytes rather than in API surface. GPL-3.0, like `dartchess` and `chessground`, and adopted
for the same reason.

It runs **only during import**. If you ever see engine work while a session is open, that is not a
performance problem, it is FR-019 broken — see scenario 6.

### 2. Schema v3

Three columns on `positions`: where the solution came from, what the engine said, and which engine
said it. Existing rows migrate to `author`, which is true of all of them.

### 3. A rejection reason retires and another arrives

`noMoves` is gone — accepting those entries is the feature. `noLegalMoves` replaces it for
positions that are already checkmate or stalemate.

## Run the tests

```bash
flutter test                                              # the whole suite
flutter test test/data/evaluation_import_test.dart        # no-moves entries become positions
flutter test test/data/migration_test.dart                # v2 → v3 with history intact
flutter test test/ui/no_feedback_guard_test.dart          # an engine-judged position, guarded
flutter test test/domain/layering_test.dart               # the engine is confined
dart analyze
```

Every one of these runs against a **fake** evaluator. No test loads the real engine, and none can:
the package is Android/iOS-only and the test VM is neither (research D8). Everything about the
real implementation is settled on a device, in scenarios 1 and 7.

## Validation scenarios

### 1. The study that prompted this feature imports (FR-001, SC-001, US1)

Import **"Probando probando"** — the private study whose single chapter is a position with no
moves, and which on 2026-08-15 imported as *"1 of the 1 entries could not be used: 1 entry has no
moves, so there is no solution."*

It must now import as one trainable position, and the report must not describe it as a problem.

**This is the scenario the feature exists for.** If it passes and nothing else does, the request
has been answered.

### 2. Both kinds import together, and neither is exceptional (FR-005, FR-006)

Import a study mixing chapters with lines and chapters without. Both kinds arrive. The report
counts them together and singles out neither.

### 3. What is still refused (FR-002, FR-003, FR-004, SC-003)

- A chapter with no `[FEN]` — still rejected, same reason, unchanged wording.
- A chapter in a non-standard variant — still rejected.
- A chapter whose moves are illegal — still rejected.
- **A position that is already checkmate or stalemate** — rejected as having nothing to calculate.
  New in this feature; confirm the report says so in words rather than a code.

### 4. Training tells you nothing (FR-016, FR-017, SC-004) — the important one

Build a session mixing engine-judged and authored positions. On each training screen, dump what a
screen reader would announce:

```bash
./tools/device/drive.sh text
```

The two must be **indistinguishable**: same controls, same wording, same everything. No mention of
an engine, an evaluation, a depth or a score.

Then commit each position and time the gap before the next appears. It must not differ between the
two kinds (SC-005). A position that takes longer to accept a commit is telling the player
something about itself.

### 5. Review says what it knows, and where it came from (FR-012, FR-013, FR-014, US2)

Review the session. For the engine-judged position: the engine's line is shown as the solution,
the evaluation of the starting position is shown, and it is stated that the line came from an
engine rather than an author. The comparison says where your line parted from it. Your own grade
is still recorded and still the record that counts.

For the authored position in the same session: identical to before this feature (FR-015).

### 6. No engine runs while a session exists (FR-019, research D2)

With a session open — setup, training, commits, review — watch the device:

```bash
adb shell top -n 1 | head -20            # no engine process
adb shell dumpsys battery                # and nothing draining
```

There must be no engine process at all. Not idle, not waiting: absent. This is the claim that
makes FR-017 structural rather than careful, and the unit test's version of it is contract
invariant 7.

### 7. Import cost, on hardware (research D10, SC-007)

Import a study of twenty hand-made positions and time it. Record it next to feature 003's number —
330 authored positions in under three seconds — because these two numbers are the trade this
feature makes, and the fallback in D2 exists for the day the second one is unacceptable.

Starting a session must never wait for any of it (SC-007).

### 8. Offline, throughout (FR-008, SC-006)

```bash
adb shell cmd connectivity airplane-mode enable
```

Import a **file** containing a no-moves position — no network, and none needed, because the engine
is local. Then train and review it. The engine's line is there. Restore with `airplane-mode
disable`.

This is the first content feature since 002 that adds no network path at all.

### 9. An evaluation that never arrives (FR-010, SC-009)

Force the evaluator to fail — a scratch build returning null is the honest way. The position must
still import, still be trainable, and its review must say that no evaluation could be produced,
distinctly from an author who recorded none.

**Fails if** the position is missing, untrainable, or reviews to a blank pane.

### 10. Upgrading from v2 (FR-021, FR-022)

Install over a build from feature 004 that has collections and played sessions. Every collection,
every position and every session survives; every existing position reads as `author`; nothing is
re-evaluated or re-imported.

## Troubleshooting

**The APK grew more than expected.** That is the gate at the top of this document, not a
packaging problem. Record the number and raise it.

**A test hangs.** Something reached the real engine. No test may: check what the evaluator provider
is overridden with, and see research D8.

**An import takes minutes.** Expected in proportion to the number of no-line entries, and the
reason scenario 7 exists. If it is unacceptable, D2's recorded fallback — evaluate after import,
in the background — changes nothing the player sees.

**The engine answers differently between runs.** `Threads` is not 1, or the search is
time-limited rather than depth-limited. See the contract, §3.
