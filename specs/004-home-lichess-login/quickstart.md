# Quickstart: Lichess Login on the Home Screen

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

How to build, run and validate this feature. Scenario numbers map to the requirements they prove,
so a scenario that fails names the requirement that broke.

## Prerequisites

The toolchain, unchanged since 001:

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$HOME/development/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
```

```bash
flutter pub get
flutter test
```

**`build_runner` is not required by this feature.** The Drift schema stays at v2 and no generated
code changes (research D12). A fresh clone still needs
`dart run build_runner build --delete-conflicting-outputs` for features 001–003; a clone that
already builds needs nothing new here.

## What is new in the build

### 1. Nothing in the manifest, the dependencies, or the database

Worth stating, because the three previous features each changed at least one. No permission is
added, no package is added or upgraded, and there is no migration to run or roll back. A device
that ran the 003 build runs this one over the top with no data event of any kind.

### 2. `LichessAuth.current()` is gone

Anything reaching for it wants `lichessAccountProvider`, which answers with a three-case
`LichessAccount` instead of a nullable connection. The split is deliberate and is the subject of
research D1 — the short version is that the object read at startup must not be the object that
opens browsers, so that the startup guard test can keep failing on every method of the latter.

### 3. An expired login now leaves a name behind

Expiry deletes the token and keeps the username and expiry date (research D3), so the app can say
*whose* login ran out. If you are testing expiry by hand, note that clearing the token alone is
now a distinct state from clearing the credential — `Disconnect` does the latter.

## Run the tests

```bash
flutter test                                        # the whole suite
flutter test test/data/account_reader_test.dart     # the three states and the expiry side effect
flutter test test/ui/home_account_test.dart         # the bar, and logging in from it
flutter test test/ui/import_no_login_test.dart      # no login anywhere in import
flutter test test/ui/no_network_during_training_test.dart   # the startup guard, now with an account
flutter test test/domain/layering_test.dart         # the training directory still knows nothing
dart analyze
```

The whole feature is covered without a device except the login itself, which needs real
credentials in a browser (scenario 2).

## Run on the device

```bash
flutter devices
flutter run --release -d <device-id>
# or, over an existing 003 install:
flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Validation scenarios

### 1. The account is legible on the first screen (FR-001, FR-002, SC-001)

Open the app. Without scrolling, tapping or navigating, the foot of the home screen says whether
a Lichess account is connected, and names it if one is. Do this on both body states: with
collections present, and after deleting every collection so the empty-library state shows.

**Fails if** the bar is missing on either state, or the state is only discoverable by tapping.

### 2. Logging in, from the first screen (FR-003, FR-007, FR-008, US1, SC-002)

From a build with no stored login: tap **Connect**. A sheet opens carrying the permissions line —
it should say the app reads studies only, posts nothing, and sends nothing about sessions
anywhere — and a **Log in to Lichess** button. (The sheet exists because the bar has no room for
the line; research D6a.) Tap it. The browser opens on Lichess's authorization page, which names
this repository as the client and `study:read` as the scope. Approve it.

Back in the app, the bar names the account. **No import has happened, and no study has been
fetched** — check `adb logcat` or a proxy: approving the login should produce the token exchange
and the username lookup, and nothing else (FR-019).

**Needs the account holder's credentials in a browser.** This is the one path no test covers.

### 3. Import never asks (FR-015, FR-017, US2, SC-006)

Logged **out**: open Import, tap **My studies**. It must say, without navigating anywhere, that
this needs a connected Lichess account and that the account is on the home screen. No browser
opens. Then paste a public study's address and import it — that must still work, with no mention
of logging in (FR-016).

Logged **in**: open Import, tap **My studies**. The list appears with no login step and nothing
that was not there in 003.

**Fails if** any part of import opens a browser, or if the logged-out path leaves you on a screen
with nothing to do.

### 4. The account is in exactly one place (FR-012, SC-007)

Walk every screen — home, import, study picker, library, history, training, review — and count
the controls that connect or disconnect. The answer must be one, on the home screen. In
particular the library screen no longer carries the Lichess tile it had in 003.

### 5. Disconnecting costs nothing but the login (FR-011, SC-010)

With an account connected and at least one collection imported from Lichess: note the collections
and a past session, tap **Disconnect**, then check both. Every collection, every position and
every session must be exactly as it was — they are local content now, not a view onto the
account. The bar reads `Not connected`.

### 6. An expired login says so, on the home screen (FR-013, FR-014, SC-008)

The honest version needs a token past its expiry, which takes a year. To force it, temporarily
build with a clock offset in `LichessAccountReader` (it takes a `now` function precisely so this
is possible) or write a credential with a past expiry through the store.

The bar must read *"<username> — your login has expired"* and offer **Log in again** and
**Disconnect**. Check with `adb logcat` that discovering this made **no request** — the date is
read from the device. Confirm the stored token is gone: an import by pasted address of a private
study must fail with "Your Lichess login has expired. Log in again from the home screen." rather
than with a 401 from Lichess.

**Fails if** the expired state is indistinguishable from never having logged in — that is the
003 behaviour this feature replaces.

### 7. The launch makes no request, connected or not (FR-004, SC-004)

With the radios on and a proxy or `adb logcat` watching, cold-start the app four times: never
connected, connected, expired, and disconnected-after-having-been-connected. Zero requests to
`lichess.org` in all four. Then start and finish a session, still with zero.

This is the device half of `no_network_during_training_test.dart`, and the one that would catch a
future "just check the token is still good" on the launch path.

### 8. The first frame does not move (SC-005, D5)

Cold-start with an account connected and watch the bottom of the screen. The bar must not appear
late and shove the body upward, and must never show a spinner. Repeat with the app killed and the
device cold, which is when the keystore is slowest.

**Fails if** the layout reflows once per launch, or if a progress indicator is visible anywhere in
the bar in any state.

Also confirm the **Start** button is reachable without scrolling while the resume offer is
showing. That is the constraint that set the bar's height at 56, and it is measured by
`resume_test.dart` — but the number came from a 400×900 test surface, and a device with a
different aspect ratio or text scale deserves a look.

### 9. Lichess stays optional (FR-005, FR-006, SC-003)

**Do not wipe the device for this.** Android's multi-user support gives a genuinely fresh install
without touching anything, and it is what this scenario was run on:

```bash
adb shell pm create-user t039                 # returns a user id, e.g. 10
adb shell am start-user 10
adb shell pm install-existing --user 10 dev.chesstrainer.chess_trainer
adb shell am switch-user 10                   # takes over the screen; reversible
# ... run the scenario ...
adb shell am switch-user 0
adb shell pm remove-user 10
```

A secondary user gets its own data directory, so the app cannot tell the difference from a first
install. Switching back leaves the phone on its lock screen, which is expected.

**One thing this cannot cover:** the file picker. `adb push` writes to user 0 whatever the
foreground user is, and copying across users is refused, so there is no way to put a PGN where
the picker in the secondary user can see it. Exercising `file_selector` needs a file already on
the device in the profile being tested.

Fresh install, never connect. Import a PGN file from the device, run a session, review it, browse
history, delete a collection, import again. The app must not ask about Lichess once, must not
block anything, and the bar must sit quietly saying `Not connected` throughout.

**Fails if** anything is disabled, prompted, or hedged because there is no account.

### 10. The account does not follow the player into training (FR-020, SC-009)

Start a session while connected. On the training screen, read the **accessibility tree** rather
than looking at it:

```bash
adb shell uiautomator dump /sdcard/window_dump.xml && adb pull /sdcard/window_dump.xml -
```

Neither the username nor any account wording may appear. Repeat for the review screen — the
account has no business there either, though review is where content is revealed.

### 11. A 003 install upgrades with nothing to say (FR-022)

Install this build over a 003 build that has a connected account. The account must survive: the
bar names it on first launch, with no re-login and no request. Collections and history are
untouched, as there is no migration.

## Troubleshooting

**The bar shows `Not connected` on a device that was logged in.** Check whether the credential
was written by a build with a different application id or signing key —
`flutter_secure_storage` is scoped to the app, and a debug build cannot read a release build's
credential.

**`Log in again` does nothing.** The redirect scheme must still match the intent filter in
`android/app/src/main/AndroidManifest.xml` exactly. This feature does not touch either, so a
failure here means something else moved — 003's note stands: a login that opens Lichess and then
hangs on the return trip is almost always this.

**The startup guard test fails with "LichessAuth.current was called".** Something reintroduced
the old provider. The account is read through `lichessAccountProvider`, which is built from the
credential store and never from `lichessAuthProvider` (research D1).

**The bar's height changes between states.** The reserved height must be the tallest state's, in
all four including the still-reading one. See D5 — this is the difference between a stable launch
and a reflow on every cold start.
