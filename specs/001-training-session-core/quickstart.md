# Quickstart: Training Session Core

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

How to run this feature and confirm it does what the spec claims.

## Prerequisites

The toolchain is installed under `$HOME` (no `sudo` was used) and exported from `~/.bashrc`:

```bash
export JAVA_HOME="$HOME/development/jdk-17"          # Temurin 17.0.20
export ANDROID_HOME="$HOME/Android/Sdk"              # cmdline-tools 22.0, platform 36, build-tools 36.0.0
export PATH="$HOME/development/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
```

Confirm the toolchain, then the device:

```bash
flutter doctor          # Android toolchain must be ✓ (Chrome and Linux desktop ✗ are expected and irrelevant)
flutter devices         # an Android device must appear
```

If no Android device is listed: connect the phone by USB, enable Developer options →
USB debugging, and accept the RSA prompt on the handset. `adb devices` should show it as
`device`, not `unauthorized`.

There is no emulator installed, and no network is required by this feature.

## Install dependencies

```bash
cd /home/roberto/chess_trainer
flutter pub get
```

## Run the tests

The domain layer needs no device — this is the fast loop, and most of the feature's
behaviour is verifiable here.

```bash
flutter test                      # everything
flutter test test/domain/         # tree, comparison, session state machine
flutter test test/ui/no_feedback_guard_test.dart   # Principle I
```

Expected: all pass. The guard test is the one to watch — see below.

## Run on the device

```bash
flutter run                       # add -d <device-id> if more than one is attached
```

## Validation scenarios

Each maps to acceptance criteria in the spec. Run them in order; scenario 1 is the one that
matters most.

### 1. Nothing leaks during training (Principle I, FR-003, SC-001)

1. Start a session of 3 positions.
2. On the first position, confirm the screen shows the board, whose turn it is, and a plain
   "1 of 3". Nothing else — no title, no theme, no rating, no goal, no hint of solution
   length.
3. Play a move you are confident is correct. Note the colour, sound, and animation.
4. Step back and play an obviously terrible move — hang a queen.
5. **Confirm the two are presented identically.** No colour change, no sound difference, no
   arrow, no symbol, no delay.
6. Commit. Confirm the next position appears immediately with no result screen in between.

*This is the product's core claim. If anything differs in step 5, stop and fix it before
continuing.*

### 2. Silent branching (FR-007, FR-008, FR-009, SC-002)

1. From the start of a position, play four plies (two moves each side).
2. Tap ◀ twice.
3. Play a *different* move for that side.
4. Confirm a branch was created, the original continuation is intact, and **nothing
   announced it** — no dialog, no toast, no highlight flash.
5. Tap ◀ twice again and replay the *same* move that is already recorded.
6. Confirm this navigated into the existing line rather than creating a duplicate sibling.

### 3. Empty and terminal analyses (spec edge cases)

1. On a position, commit without playing anything. Confirm it is accepted.
2. On another, play a line into checkmate. Confirm the line ends there, no further moves can
   be added to that branch, and the app says nothing about it.

### 4. Review reveals everything, and grades are yours (FR-020 – FR-027)

1. Complete all positions in the session.
2. Confirm review begins only after the final commit.
3. For each position, confirm you can see your tree and the solution, step through both,
   and that the first divergence is identified.
4. Confirm the metadata hidden in scenario 1 — title, themes, goal — is now visible.
5. Confirm the match indicator reads as a measurement ("matched 4 of 6"), not a verdict.
6. Confirm your self-grade is recorded and is not overridden by the match indicator.
7. On a position where you entered a sensible alternative branch the solution does not
   contain, confirm the app does **not** call it wrong.

### 5. Offline (FR-030, SC-003)

1. Put the device in airplane mode.
2. Run a full 5-position session start to finish, including review.
3. Confirm nothing fails or degrades.

### 6. Abandonment (FR-019)

1. Start a session, commit one position, then abandon.
2. Confirm you are warned that no answers will be shown, and that after confirming, none are.

### 7. Responsiveness (SC-006)

1. On one position, build a tree of roughly 40 moves across at least 8 branches.
2. Confirm board interaction and navigation stay smooth.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `flutter devices` shows only "Linux (desktop)" | Phone not connected or USB debugging off. Linux desktop cannot build here anyway — no clang/CMake/GTK installed. |
| Device shows `unauthorized` in `adb devices` | RSA prompt not accepted on the handset. Unplug, replug, accept. |
| Gradle fails on first build | First run downloads a Gradle distribution. Disk was at 98% during setup — check `df -h /` before assuming a code fault. |
| A sample position fails to load | `PositionParseError` — a bundled PGN has a bad FEN header or an illegal mainline move. Deliberately loud; malformed positions must never reach a session. |
