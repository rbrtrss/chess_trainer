# Quickstart: Session Persistence

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

How to run this feature and confirm it does what the spec claims.

## Prerequisites

The toolchain is the same as feature 001 — see
[its quickstart](../001-training-session-core/quickstart.md#prerequisites) for the `JAVA_HOME`,
`ANDROID_HOME` and `PATH` exports and the device setup.

## The build step that is new

This feature introduces code generation. **`flutter test` and `flutter run` will fail on a
fresh clone until the generated database code exists**, with errors that point at a missing
`database.g.dart` rather than at the missing step (research D8).

```bash
cd /home/roberto/chess_trainer
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Re-run that whenever `lib/data/local/tables.dart` or `database.dart` changes. While working on
the schema, `dart run build_runner watch` is less tedious. (`--delete-conflicting-outputs` is
accepted but ignored by build_runner 2.16; it is kept in the README because it is harmless and
still what older setups need.)

Generated files are gitignored on purpose, so this step is part of every clone and every CI
run, not a one-off.

**Changing the schema** additionally means re-recording it, because the migration test needs a
version to migrate *from*:

```bash
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

Unlike the `build_runner` output, `drift_schemas/` and `test/generated/` **are committed**.

## Run the tests

Persistence runs against an in-memory database, so the fast loop still needs no device.

```bash
flutter test                                  # everything
flutter test test/data/                       # repositories, codec, migrations
flutter test test/domain/layering_test.dart   # the training layer stays history-free
flutter test test/ui/no_feedback_guard_test.dart   # Principle I, including resumption
```

Expected: all pass. The two to watch are the layering test and the guard test — see below.

## Run on the device

```bash
flutter run
```

## Validation scenarios

Run them in order. Scenario 1 is the reason this feature exists; scenarios 4 and 5 are the
reason it is dangerous.

### 1. A killed session comes back (FR-001 – FR-007, SC-001, SC-002)

1. Start a session of 3 positions.
2. Commit the first.
3. On the second, play four plies, step back two, and play a different move so there is a
   branch.
4. Kill the app outright — not backgrounded, killed:

   ```bash
   adb shell am force-stop dev.chesstrainer.chess_trainer
   ```

5. Reopen it. Confirm you are offered to continue.
6. Continue, and confirm: it is position 2 of 3, the first position's attempt is still
   recorded, the board is back at position 2's starting point with no moves entered, and you
   are **told** that the analysis in progress was not kept.
7. Commit the rest and confirm review shows all three attempts, including the one committed
   before the kill.

*Step 6 is the decision made in clarification: uncommitted work is not stored. The thing to
check is that the app says so — an empty board with no explanation reads as a bug.*

### 2. Interruption at the worst moment (FR-005, SC-001)

1. Start a session. On position 1, tap Done and immediately kill the app.
2. Reopen. Confirm the session is at either position 1 with no attempt, or position 2 with the
   attempt stored — and never at position 2 with position 1 unattempted.

*The second state is unrecoverable: the session could never enter review. That is what the
transaction in research D6 exists to prevent.*

### 3. Nothing leaks across a restart (FR-008, SC-003)

1. Start a session and note exactly what is on the training screen.
2. Play the move you believe is correct. Kill and reopen the app; continue.
3. Confirm the screen is identical to an uninterrupted session at the same point: same board,
   same "N of M", same turn indicator, no title, theme, rating or goal, no marks of any kind.
4. Repeat having played an obviously terrible move, and confirm the two are still identical.

### 4. History does not leak into training (FR-019, SC-004)

1. Complete a session containing a position, and grade it **Missed it**.
2. Start a new session containing that same position.
3. **Confirm nothing on the training screen mentions it**: no previous grade, no "seen 2 times",
   no date, no icon, no ordering difference, nothing.
4. Reach review and confirm it is not shown there either — this feature stores grades but shows
   no cross-session history anywhere.

*The grades are in the database, so the ingredients for this leak exist even though nothing
displays them. If step 3 ever shows anything, it tells the player the position is one they got
wrong, which is knowledge about the position.*

### 5. Abandoning forfeits the answers permanently (FR-015)

1. Start a session, commit one position, then abandon.
2. Confirm no answers are shown, as in feature 001.
3. Reopen the app, go to the history, and open that session.
4. **Confirm it is shown as abandoned and no solution, note, or metadata appears** — not for the
   position you committed, not for any of them.

*Feature 001 could only forfeit the answers until the process died. This is the check that it
now means what it says.*

### 6. Finished sessions stay readable (FR-012 – FR-015, SC-005)

1. Complete a session and note the review of one position.
2. Kill the app, reopen, open the history, and open that session.
3. Confirm the review is identical: same tree, same solution, same divergence, same notes, same
   metadata, same grade.
4. Change the grade and confirm the new one sticks and replaces the old (FR-017).

### 7. One session at a time (FR-010, FR-011)

1. Start a session and commit one position.
2. Without finishing, try to start a new session.
3. Confirm you are warned that the unfinished one will be discarded and its answers forfeited,
   in the same terms as abandoning, and that declining leaves it untouched.

### 8. Survives an app update (FR-025, SC-008)

1. With history stored, build and install a new build over the existing one:

   ```bash
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

   Do **not** uninstall first — that would delete the data and prove nothing.
2. Reopen and confirm the history and grades are all still there.

### 9. Offline (FR-021, FR-022, SC-007)

1. Put the device in airplane mode.
2. Run a full session including an interruption, a resumption, review, and a visit to the
   history.
3. Confirm nothing fails or degrades. The release build declares no `INTERNET` permission at
   all, so there is nothing to fall back from.

### 10. Storage failure is admitted (FR-024)

1. Simulate a write failure (the repository test harness does this; on device, filling the disk
   is the honest way).
2. Confirm the player is told their work could not be saved, rather than the app carrying on as
   though it had been.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Target of URI hasn't been generated: 'database.g.dart'` | `build_runner` has not been run. See "The build step that is new". |
| Generated file is stale after a schema edit | Re-run with `--delete-conflicting-outputs`. |
| Resume offers nothing after killing the app | A session is stored when it starts, so it should be offered even with nothing committed. If it is not, the session row is not being written at `start`. |
| History empty after reinstalling | `adb install -r` preserves data; a plain `adb install` after an uninstall does not. |
| Analysis in progress is gone after a resume | Expected — uncommitted work is not stored (research D3). The defect would be the app failing to say so. |
