# Quickstart: Position Import

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

How to build, run and validate this feature. Scenario numbers map to the requirements they
prove, so a scenario that fails names the requirement that broke.

## Prerequisites

The toolchain, as in features 001 and 002:

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$HOME/development/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
```

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # still not optional
flutter test
```

The `build_runner` step is unchanged from 002 and is still required on a fresh clone. This
feature bumps the schema to v2, so it must be re-run after pulling these changes even on a clone
that already had generated files.

## What is new in the build

### 1. The app now declares INTERNET, and that is a real change

`android/app/src/main/AndroidManifest.xml` gains:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Until this feature the release build was *incapable* of network access, and feature 002's plan
relied on that. It cannot any more. The replacement guarantee is behavioural and is asserted by
tests — see scenario 8 — rather than by the operating system. Anyone reviewing this change should
know they are trading a hard guarantee for a tested one, deliberately (research D14).

The same file gains `android:allowBackup="false"` on `<application>` so the access token cannot
leave the device inside a Google backup (FR-021, research D4). Consequence: the training database
stops being backed up too. Sessions still survive an app update; they do not survive a factory
reset.

### 2. The OAuth redirect scheme

`android/app/src/main/AndroidManifest.xml` gains the callback activity for
`org.chesstrainer://oauth/callback`, matching `redirect_uri` in `lib/data/lichess/lichess_auth.dart`.
If the two disagree, login opens Lichess and then hangs on the return trip with no error — the
first thing to check when a login never completes.

The Lichess `client_id` is a public identifier, is committed on purpose, and is not a secret
(constitution, Secrets). There is no client secret to configure: Lichess does not support one.

### 3. Test fixtures from a real study

The constitution's testing floor requires study PGN → position extraction to be tested against
real fixture files. Fetch them once, commit them, and never let a test reach the network:

```bash
curl -s 'https://lichess.org/api/study/{studyId}.pgn?clocks=false&comments=true&variations=true' \
  -o test/fixtures/study_multi_chapter.pgn
```

At least three fixtures are needed: a study whose chapters all start from a position, a study
mixing those with "analyse this game" chapters that have no `[FEN]` (so the rejection report is
exercised on real content), and one containing a non-standard variant chapter.

**These are already committed** — see `test/fixtures/README.md` for which study each came from
and why. Do not re-fetch them casually: the tests assert exact counts (33 chapters, 7 of 11
usable), and a study whose author has since edited it will fail tests for reasons that have
nothing to do with the code.

### What the real exports changed

Two assumptions in the plan did not survive contact with a real study, and both are now in the
code:

1. **`[Variant "From Position"]` is what Lichess writes for a chapter set up from a FEN** —
   that is, for exactly the chapters this app wants. Treating anything but `"Standard"` as an
   unsupported variant would have rejected every usable chapter of the first fixture we
   fetched.
2. **`[StudyName]` and `[ChapterName]` are real headers**, and `[ChapterName]` is the
   constitution's own example of evidence. Neither was among the five metadata fields feature
   001 knew about, which is the clearest argument for the header bag (research D11): the
   allowlist was already incomplete on the first real file we tried.

## Run the tests

```bash
flutter test                                    # everything, no device needed
flutter test test/data/import_test.dart         # parsing and rejection rules
flutter test test/data/lichess_api_test.dart    # every request, against a fake client
flutter test test/domain/layering_test.dart     # the narrowed network rule (D14)
flutter test test/ui/no_feedback_guard_test.dart
flutter test test/ui/no_network_during_training_test.dart
```

No test in this repository makes a real network request. `LichessApi` is exercised through a fake
`http.Client`; the OAuth flow is exercised without opening a browser.

## Run on the device

```bash
flutter run                     # on a connected Android phone
adb shell am force-stop com.example.chess_trainer   # kill it, as in 002
```

## Validation scenarios

### 1. A study file becomes trainable positions (FR-001 – FR-007, US1)

Put a multi-chapter study PGN on the device. Import it, name it, and read the report: *n* added,
and every rejected chapter listed with a reason. Start a session on the collection and confirm it
draws only from it.

**Expect**: the count of added positions plus rejected entries equals the number of chapters in
the file. Nothing is silently dropped (SC-008).

### 2. A game record is rejected, and says why (FR-003, FR-006, D10)

Export one of your own games from Lichess — a plain game PGN, no `[FEN]` header — and import it.

**Expect**: rejected, with "starts from the standard position and does not say which position to
train". Not imported as a position starting at move 1. If a real study is imported, expect the
same message for every "analyse this game" chapter, grouped rather than repeated.

### 3. Nothing from the file reaches the training screen (FR-024 – FR-027, SC-003, SC-004)

Import the deliberately hostile fixture — a chapter whose `[Event]`, `[Site]`, `[Annotator]`,
`[Result]`, comments and NAGs all contain distinctive strings, in a collection named
"Mate in three, back rank", from a file called `answers.pgn`. Train it.

**Expect**: none of those strings appears anywhere on the training screen, including in
semantics, tooltips or accessibility labels. The screen is identical to one showing a bundled
position apart from the pieces. This is the scenario this whole feature is riskiest on: check it
by hand once, and then trust the automated version of it.

### 4. Log in and import a private study (FR-011 – FR-014, US2, SC-002)

Import a public study by URL with no login. Then log in and import a private one.

**Expect**: the public import needs no login. The login opens a Chrome Custom Tab showing a real
`lichess.org` address bar — not an embedded WebView. The private import produces a collection
indistinguishable from a file-imported one.

### 5. The imported study works with no signal (FR-016, SC-010)

Immediately after scenario 4, enable airplane mode. Run a full session on the imported
collection, review it, and reopen it from history.

**Expect**: everything works. No spinner, no timeout, no degraded screen.

### 6. Network failures are all honest (FR-018 – FR-020, SC-011)

Work through each, offline or with a fake:

| Provoke | Expect |
|---|---|
| Airplane mode, then import | "needs a connection"; the rest of the app unaffected |
| Import a study id that does not exist | "not available to this account" |
| Paste a game URL instead of a study URL | says what kind of address was expected |
| Revoke the token at <https://lichess.org/account/oauth/token>, then import | asked to log in again — **not** a silent failure, and no refresh attempted |
| Kill the network mid-fetch | no collection created; retrying works |

**Expect** in every case: no partial collection, and a message naming what to do.

### 7. Deleting a collection does not rewrite history (FR-036 – FR-038, SC-012)

Play a full session on an imported collection, grade it, then delete the collection. Reopen the
session from history.

**Expect**: the review shows every position, solution, note and grade exactly as before. Then try
deleting a collection the *unfinished* session depends on: expect the abandon-style warning
about forfeiting answers.

### 8. The app makes no request unless asked (FR-015, SC-009)

With a proxy or `adb shell` packet inspection running, open the app, start a session, commit
attempts, review, resume, browse history, open the collection list.

**Expect**: zero requests to `lichess.org`. The automated form of this is
`test/ui/no_network_during_training_test.dart`, which drives the same flow against a `LichessApi`
that fails the test if touched.

### 9. The samples are an ordinary collection (FR-033, FR-039)

On a fresh install, confirm the three samples appear as a collection. Delete it, restart the app.

**Expect**: it does not come back. With no collections at all, the app offers import rather than
showing a broken session setup.

### 10. Schema v2 upgrades cleanly (FR-040)

Install the 002 build, play a session, then install this build over it.

```bash
git stash && flutter run          # 002 build: play and finish a session
git stash pop && flutter run      # this build, over the top
```

**Expect**: the old session is still in history with its review intact, and the sample collection
appears. `flutter test test/data/migration_test.dart` asserts the same thing without a device.

### 11. A big import stays responsive (SC-007, D15, D16)

Measured on the development machine while implementing: 297 positions parsed in 61 ms from a
438 KiB source, which is three orders of magnitude inside the 10 s budget. A phone is slower,
but not by that much — this is very unlikely to be where the feature struggles. What still
needs a device is the *responsiveness* half of the claim, since the isolate hop (D15) is what
keeps frames drawing and that cannot be observed in a widget test.

Import a 300-chapter study, or the largest study you have.

**Expect**: determinate progress, a UI that still scrolls, and completion. A source past the cap
is refused with the limit named — not a hang.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Target of URI hasn't been generated: 'database.g.dart'` | `dart run build_runner build --delete-conflicting-outputs` has not been run |
| Login opens Lichess, then nothing happens on return | `redirect_uri` and the manifest's callback scheme disagree |
| Every chapter of a real study is rejected | Expected for "analyse this game" studies — they have no `[FEN]` (D10). Check the reasons in the report before assuming a bug |
| The picker shows no `.pgn` files | Expected and handled: the picker accepts any file because Android providers report inconsistent MIME types for PGN (D1). Pick the file anyway; the content is validated |
| `layering_test.dart` fails on `package:http/` | Something outside `lib/data/lichess/` reached for the network. That is the rule, not a false positive |
| Tests pass but the training screen shows a chapter title | The guard test's fixture does not cover that field. Add the string to the hostile fixture and fix the leak — in that order |
