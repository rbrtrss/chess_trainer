---

description: "Task list for 004: Lichess login on the home screen"
---

# Tasks: Lichess Login on the Home Screen

**Input**: Design documents from `/specs/004-home-lichess-login/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/account-api.md](./contracts/account-api.md)

**Tests**: included. The constitution's Principle V makes tests part of "complete", and this
feature's two structural changes — the account reader (D1) and the expired state (D3) — are
exactly the kind that pass review and fail on a device a year later.

**Organization**: grouped by user story, so each can be built, tested and shown on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel — different files, no dependency on an unfinished task
- **[Story]**: which user story the task serves (US1, US2, US3)
- Every task names the file it touches

## Path Conventions

Single Flutter module. `lib/domain/`, `lib/data/`, `lib/ui/`, tests mirroring them under `test/`.

---

## Phase 1: Setup

**Purpose**: establish the baseline this feature is measured against.

There is unusually little here: no dependency is added, no permission, no schema version, and
`build_runner` does not need to run (research D12). That is worth confirming rather than assuming.

- [X] T001 Run `flutter test` and `dart analyze` on `004-home-lichess-login` before changing anything, and record that both are clean — every later "still green" claim is relative to this

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the account type, the local reader, and the provider swap. Every user story reads
account state, so none can start until this is done.

**⚠️ CRITICAL**: no user story work begins until Phase 2 is complete.

- [X] T002 [P] Create `lib/domain/lichess/account.dart` — sealed `LichessAccount` with `AccountDisconnected`, `AccountConnected(LichessConnection)` and `AccountExpired(LichessConnection)`, pure Dart, no token ([account-api.md §1](./contracts/account-api.md), data-model "Entities")
- [X] T003 [P] Add `expireToken()` to `CredentialStore` in `lib/data/lichess/credential_store.dart` and implement it in both `SecureCredentialStore` (delete the token key, keep username and expiry) and `InMemoryCredentialStore`
- [X] T004 Create `lib/data/lichess/account_reader.dart` — `LichessAccountReader({required CredentialStore credentials, DateTime Function()? now})` with `Future<LichessAccount> read()`, following the four-row behaviour table in [account-api.md §2](./contracts/account-api.md). It must hold no HTTP client and take none: that is the whole point of research D1
- [X] T005 [P] Create `test/data/account_reader_test.dart` — nothing stored → disconnected; live credential → connected; passed expiry → expired *and* `readToken()` now null; unparseable expiry → disconnected with everything cleared. Inject the clock rather than waiting a year
- [X] T006 Replace `lichessConnectionProvider` with `lichessAccountProvider` (`FutureProvider<LichessAccount>`) in `lib/ui/library/connection_controller.dart`, built from `credentialStoreProvider` and **never** from `lichessAuthProvider`; have `ConnectionController.logIn`/`logOut` invalidate it
- [X] T007 Update `myStudiesProvider` in `lib/ui/library/connection_controller.dart` to gate on `AccountConnected`, still throwing `NotLoggedInError` otherwise
- [X] T008 Update the two existing readers — `lib/ui/library/collection_list_screen.dart` and `lib/ui/library/study_picker_screen.dart` — to switch on `LichessAccount` so the suite compiles again. Both lose their controls later; this task only keeps the tree buildable
- [X] T009 Delete `current()` from `LichessAuth` and `PkceLichessAuth` in `lib/data/lichess/lichess_auth.dart`, and move its four assertions out of `test/data/lichess_auth_test.dart` into `test/data/account_reader_test.dart` rather than dropping them (research D1, plan "Known risks")
- [X] T010 Add a line to the header comment of `lib/ui/library/connection_controller.dart` recording why the file did not move to `lib/ui/account/` when the account did (research D9)

**Checkpoint**: the app behaves exactly as it did in 003, but account state comes from a reader that cannot reach the network, and the expired state exists in the model with nothing yet displaying it.

---

## Phase 3: User Story 1 — Connect my account before I need it (Priority: P1) 🎯 MVP

**Goal**: the player sees on the first screen whether an account is connected, and can connect
one there, without importing anything.

**Independent test**: launch with no stored credential, log in from the first screen, and confirm
the screen then names the account — with no import performed at any point.

- [X] T011 [US1] Create `lib/ui/account/account_bar.dart` — a `ConsumerWidget` watching `lichessAccountProvider`, rendering the states and keys in [account-api.md §4](./contracts/account-api.md). ~~Handle `AccountExpired` by falling through to the disconnected rendering for now~~ — **done differently**: the expired rendering was written straight away rather than left provisional. The fall-through existed only to keep US1 and US3 separable, and the exhaustive `switch` made writing the real thing cheaper than writing a placeholder with a comment explaining itself
- [X] T012 [US1] Give the bar one constant height across all four states including `account-bar-unknown`, which renders reserved space and nothing else — no spinner, no guessed state (research D5, SC-005)
- [X] T013 [US1] ~~Put the permissions line in the disconnected state of the bar~~ — **reversed by measurement**: the line does not fit. It moved to the disclosure sheet that `connect-lichess` opens, and the bar is one line in every state (research D6a; the bisection is in "What was done, and what was not" below). FR-007 is met, SC-002 is not — see below
- [X] T014 [US1] Mount the bar in `lib/ui/session/session_setup_screen.dart` below the scrolling body, so it appears in both body states — the setup form and `_EmptyLibrary` (FR-001)
- [X] T015 [US1] Wire **Connect** in `lib/ui/account/account_bar.dart` to `connectionControllerProvider.logIn()`: disable the button while it runs, report nothing when it returns null, and show `messageForNetworkError` in a snackbar keyed `account-login-failure` when it throws (FR-009, FR-010, research D10)
- [X] T016 [P] [US1] Create `test/ui/home_account_test.dart` — the bar renders `account-disconnected` with no stored credential and `account-connected` naming the user with one; **Connect** reaches the login; a cancelled login leaves the screen unchanged with no message; a failed login shows the snackbar and leaves the bar disconnected
- [X] T017 [P] [US1] Add to `test/ui/home_account_test.dart`: the bar occupies the same height in every state, measured including the still-reading state (SC-005)
- [X] T018 [US1] Add a case to `test/ui/no_network_during_training_test.dart`: launch with a credential already in the `InMemoryCredentialStore`, assert the username is on screen **and** that `_ExplodingAuth` and `_ExplodingApi` were both untouched. `_ExplodingAuth` keeps failing on every method — if this task tempts you to relax it, research D1 was not followed (FR-004, SC-004)
- [X] T019 [US1] Verify on device: quickstart scenario 2 — **done by the account holder on 2026-08-15**. Logged in from the home screen; the bar named the account. The round trip cost 9,239 bytes, and the study list was proved *not* prefetched by opening the picker afterwards and watching it cost the full 11,448 (FR-019)

**Checkpoint**: the feature's central complaint is answered. The account is on the first screen and can be connected there. Import still works exactly as 003 left it.

---

## Phase 4: User Story 2 — Import without being asked to log in (Priority: P2)

**Goal**: no part of import offers or starts a login.

**Independent test**: from the import screen, connected and disconnected, exercise every Lichess
path and confirm no login is ever started from there.

- [X] T020 [US2] Delete `_LogInPrompt` from `lib/ui/library/study_picker_screen.dart`, along with its keys `lichess-login-prompt` and `log-in-to-lichess`, leaving a message-only disconnected state that names the home screen (research D7, FR-015)
- [X] T021 [US2] Gate **My studies** in `lib/ui/library/import_screen.dart`: with no connected account it does not navigate, and shows an inline message keyed `studies-need-account` saying an account is needed and that it lives on the home screen (FR-017)
- [X] T022 [P] [US2] Reword exactly two branches of `messageForNetworkError` in `lib/ui/library/connection_controller.dart` — `NotLoggedInError` and `LoginExpiredError` — to name where the account is, per [account-api.md §5](./contracts/account-api.md). Leave every other branch alone (research D8)
- [X] T023 [P] [US2] Update the two changed strings in `test/ui/import_failure_messages_test.dart` and confirm the other branches are still asserted unchanged
- [X] T024 [P] [US2] Create `test/ui/import_no_login_test.dart` — the import screen offers no login connected or disconnected; **My studies** disconnected shows `studies-need-account` and does not navigate; the picker reached while disconnected shows a message and no login button; a pasted public study still imports with no account (FR-016)
- [X] T025 [US2] Verify on device: quickstart scenario 3 — **logged-in half done on 2026-08-15**: My studies opened the picker and listed the account's real studies with no login step, and the fetch showed as 11,651 bytes against 0 for four cold starts. The logged-out half needs the account disconnected, which revokes the owner's real token — not done, see the pass record

**Checkpoint**: both halves of the user's sentence are done. The login is on the home screen and gone from import.

---

## Phase 5: User Story 3 — Find the account in one place (Priority: P3)

**Goal**: one control for the account, and an expired login that says so where the player will
see it.

**Independent test**: disconnect from the home screen and confirm collections and sessions are
untouched, and that no other screen offers a competing account control.

- [X] T026 [US3] Give `AccountExpired` its own rendering in `lib/ui/account/account_bar.dart` — `<username> — your login has expired`, with **Log in again** and **Disconnect** — replacing the fall-through left by T011 (FR-013, FR-014)
- [X] T027 [US3] Wire **Disconnect** in `lib/ui/account/account_bar.dart` to `connectionControllerProvider.logOut()`, available from both the connected and expired states (FR-011)
- [X] T028 [US3] Delete `_ConnectionTile` from `lib/ui/library/collection_list_screen.dart` and the now-unused import of the connection controller (FR-012)
- [X] T029 [P] [US3] Move the two connection tests out of `test/ui/collection_list_test.dart` into `test/ui/home_account_test.dart` — "shows as not connected when there is no login" and "disconnecting forgets the login and keeps the collections" — retargeted at the bar, keeping the collections-survive assertion intact (SC-010)
- [X] T030 [P] [US3] Add to `test/ui/home_account_test.dart`: the expired state renders and names the account; **Log in again** reaches the login; **Disconnect** from the expired state clears it to disconnected
- [X] T031 [US3] Add a source-level rule to `test/domain/layering_test.dart`: no file under `lib/ui/` other than `lib/ui/account/account_bar.dart` calls `logIn()` or `logOut()` on the connection controller — the "exactly one control" claim, checked rather than walked (FR-012, SC-007)
- [X] T032 [US3] Verify on device: quickstart scenarios 4, 5 and 6. **Scenarios 4 and 5 done** (2026-08-15): only the home screen carries a connect/disconnect control, and disconnecting left both collections, all six sessions and a past review of the Lichess-imported collection completely intact. **Scenario 6 (expiry) is not done** — it needs a build with a shifted clock, and the unit tests cover the transition; what is untested is only that it looks right on the phone

**Checkpoint**: all three user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T033 [P] Extend the training-directory rule in `test/domain/layering_test.dart` with `LichessAccount`, `LichessConnection`, `lichessAccountProvider`, `connectionController` and `username` — the account may not reach a screen where someone is calculating (FR-020, research D11)
- [X] T034 [P] Add to `test/ui/home_account_test.dart`: the bar renders identically with no collections and with several, and does not change when the chosen collection changes (FR-021, contract invariant 7)
- [X] T035 [P] Update `README.md` where it describes logging in to Lichess from the import screen, and note that the account now lives on the home screen
- [X] T036 Run `dart analyze` and `flutter test` — both clean, and the suite no smaller than the T001 baseline except where tests were deliberately moved
- [X] T037 Verify on device: quickstart scenario 7 — **connected state done on 2026-08-15**: four cold starts, each showing "Connected as rbrtrss", **0 bytes** on the app's uid measured through `dumpsys netstats`, then a whole session with 0 more. The other three account states need the login destroyed to reach, so they are not covered (SC-004)
- [X] T038 Verify on device: quickstart scenario 8 — done 2026-08-15 on a 1080×2460 TECNO KJ6. The bar renders correctly below Start, no spinner, and **Start stays fully on screen with the resume prompt showing** — the worst-case layout that set the 56px budget. No reflow seen across eight cold starts (SC-005)
- [X] T039 Verify on device: quickstart scenario 9 — **done 2026-08-15 on a genuinely fresh install, and without destroying anything**: a throwaway Android user was created and the package installed into it, which gives its own data directory and therefore a first-ever launch, leaving user 0's two collections and six sessions untouched. Full record below (FR-005, FR-006, SC-003)
- [X] T040 Verify on device: quickstart scenario 10 — done 2026-08-15, **with a real account connected**, which is the first time this assertion has had a username available to leak. The training screen's tree contains no `rbrtrss`, no "Lichess", no "connected", no collection name; review likewise carries no account control (FR-020, SC-009)
- [X] T041 Verify on device: quickstart scenario 11 — done 2026-08-15. Installed over the 003 build of 2026-08-14 that had a live login and 2 collections. The account survived with no re-login and no request, both collections and all four past sessions are intact, and there was no migration to run (FR-022)

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks every user story**
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on Foundational. Independent of US1 in code, but shipping it alone
  would leave the app with no way to log in at all, so it follows US1 in practice
- **US3 (Phase 5)**: depends on Foundational and on US1's `account_bar.dart` (T011), which it
  extends rather than duplicates
- **Polish (Phase 6)**: depends on everything it asserts about

### Task dependencies worth naming

- T004 depends on T002 and T003 — the reader returns the type and calls the new store method
- T009 depends on T006, T007 and T008: `current()` cannot be deleted until nothing calls it
- T012 and T013 both edit `account_bar.dart` after T011 creates it, so they are sequential
- T026 and T027 replace what T011 left provisional, so US3 must not start before T011 lands
- T031 depends on T028 — the rule fails while `_ConnectionTile` still exists
- T036 depends on every code task; the device tasks (T037–T041) depend on T036

## Parallel Example: Phase 2

```bash
# Independent files, no shared edits:
Task: "Create lib/domain/lichess/account.dart"                    # T002
Task: "Add expireToken() to lib/data/lichess/credential_store.dart"  # T003
# then, once both land:
Task: "Create lib/data/lichess/account_reader.dart"               # T004
Task: "Create test/data/account_reader_test.dart"                 # T005
```

## Parallel Example: US2 tests

```bash
# Three files, none of which the others touch:
Task: "Reword two branches in connection_controller.dart"     # T022
Task: "Update test/ui/import_failure_messages_test.dart"      # T023
Task: "Create test/ui/import_no_login_test.dart"              # T024
```

## Implementation Strategy

**MVP is Phase 1 + Phase 2 + US1** (T001–T019). At that point the account is on the first screen,
can be connected and named there, and the launch is proven to make no request. Import still
carries its 003 login, which is redundant rather than broken — the app is shippable and the
original complaint is answered.

**Increment 2 is US2** (T020–T025): the redundant login comes out of import.

**Increment 3 is US3** (T026–T032): one control, and the expired state gets its own words.

**Phase 6 last**, because most of it asserts things the earlier phases must already be doing.

### The one thing no test covers

The login itself needs the account holder's credentials in a browser (T019). Feature 003 left the
same gap and recorded it rather than pretending otherwise; the same applies here, and it is the
first task to hand to whoever owns the account.

---

## What was done, and what was not

Recorded at implementation time, on 2026-08-15, rather than left to be inferred from the
checkboxes.

**All 41 tasks are done.** `flutter test` passes 406 tests, up from the 369 of the T001
baseline; `dart analyze` is clean; the release APK builds. The device pass of 2026-08-15 is
recorded below and closed five of the eight verification tasks. The account holder then ran the
two that needed their credentials, and T039 was done last, on a throwaway Android user rather
than by wiping the device.

### The one thing the design got wrong

**A two-line account bar does not fit.** D6 put the permissions disclosure in the bar as small
print, on the assumption that a footer has room for two lines. `resume_test.dart` failed on the
first run with the bar mounted, and bisecting the height against it gave a hard budget:

| Bar height | `resume_test.dart` |
|---|---|
| 0, 40, 56 | passes |
| 72, 88 | fails — the Start button is out of reach |

The failing case is a 400×900 phone showing the offer to resume an unfinished session: the
screen's tallest state, and an ordinary one. So the real choice was never "small print or a
sheet", it was **small print or the screen's primary action**. The disclosure moved to a sheet
that `connect-lichess` opens, the bar is one line at 56, and D6a records the alternatives that
were rejected.

**This costs SC-002.** "A player can go from launching the app to a completed Lichess login in
one action plus the login itself" is now two actions plus the login — Connect, then Log in to
Lichess. It is recorded here rather than reinterpreted, because the criterion was written to mean
something. If it matters more than the disclosure does, the fix is to drop the sheet and rely on
Lichess's own authorization page, which names the scope under a client id pointing at this
repository; that is a decision for whoever owns the requirement, not for the implementation.

### What went better than planned

- **The expired state came free.** D2 and D3 were written expecting a fight between "name the
  expired login" and 003's rule that no dead token is ever held. Deleting the token while keeping
  the username and date satisfies both exactly, and `readConnection` already returned everything
  needed — no new key, no second source of truth, no migration.
- **The startup guard got stronger, not weaker.** The worry in D1 was that showing an account at
  launch would force `no_network_during_training_test.dart` to let one method of `_ExplodingAuth`
  through. With the read moved to `LichessAccountReader`, the fake now has no method that is not a
  network call, every one still fails on contact, and the suite gained a case that launches
  *logged in*, shows the username, and still asserts zero contact.
- **A bug the plan did not anticipate, found while writing the reader.** A credential whose stored
  expiry will not parse used to be reported as "no account" while its token stayed readable — an
  orphaned, usable token behind an account the app called disconnected. `readConnection` now
  clears the whole credential in that case, with a test using `FlutterSecureStorage`'s mock, since
  the in-memory store cannot represent a corrupt date.

### Still not verified, and why

- **The login itself (T019).** It needs the account holder's Lichess credentials in a browser.
  Not something to do on someone's behalf. Everything up to and including the disclosure sheet is
  covered by tests; the browser round trip and what comes back from it are not.
- **Everything else on the device (T025, T032, T037–T041).** No device was attached during this
  implementation. Four of these are worth doing before this is believed:
  - **T038**, the reflow check, is the one a test cannot really make. `home_account_test.dart`
    asserts the heights match, which is the mechanism; whether a cold Android keystore makes the
    bar visibly late is a thing to watch on hardware.
  - **T037**, packet-level confirmation that four cold starts produce no request. The unit-level
    version of this claim is strong — the reader takes no client — but the claim is about a whole
    app, and only a proxy can say so.
  - **T040**, the accessibility-tree dump on the training screen. `layering_test.dart` forbids the
    account identifiers in `lib/ui/training/`, which is a source rule; the tree is what a screen
    reader would actually announce. Feature 003's device pass found its one real defect this way.
  - **T041**, upgrading over a 003 install with a connected account. There is no migration, so
    the expectation is that nothing happens at all — which is exactly the kind of expectation
    worth checking once.

---

## The device pass, 2026-08-15, TECNO KJ6 (Android 13, 1080×2460)

Run once a device was attached, over `adb`, on a release build installed on top of the 003 build
of 2026-08-14.

**The device turned out to have a live Lichess login** — `rbrtrss`, connected by the account
holder after 003's pass ended. That changed what was testable: every assertion about a *connected*
account could be made for real, and for the first time the Principle I check had an actual
username available to leak.

### How the pass was driven, given what happened last time

003's pass was stopped after a back-press left the app twice and the next capture caught the
device owner's personal messages. This pass therefore captured nothing without a guard: a helper
read `topResumedActivity` immediately before every screenshot and every UI dump and refused if
the foreground was not `dev.chesstrainer.chess_trainer`. The guard was proved non-vacuous before
it was trusted — HOME was pressed, the guard refused with the launcher in front, and nothing was
captured. One screenshot was taken, of our own home screen, and it was deleted from host and
device at the end along with every `ui.xml`.

### What passed

- **T041 — upgrade over 003 with a live login: PASS.** `adb install -r` over the 2026-08-14
  build. The account survived with no re-login, both collections ("Lichess study", 7 positions;
  "Sample positions", 3) are intact, all four past sessions are still in the history, and there
  was no migration to run. The bar read `Lichess · Connected as rbrtrss` on the first launch.
- **T037 — no request at launch: PASS, measured.** Four cold starts, each showing the connected
  account, with the app's uid byte counter read from `dumpsys netstats` before and after:
  **0 bytes**. Then a whole session, still 0. The control is in the same numbers — tapping *My
  studies* moved 11,651 bytes, so the counter does register this app's traffic. This is the
  strongest form the offline claim has ever been given: the unit test proves the reader holds no
  client, and this proves the whole app sent nothing while showing a username.
- **T040 — Principle I with a real username: PASS.** The training screen's accessibility tree —
  everything a screen reader would announce — contains no `rbrtrss`, no "Lichess", no
  "connected", no "account", and no collection name. The review screen carries no account control
  either.
- **T038 — layout: PASS, including the case that set the budget.** With the resume prompt showing,
  the **Start** button is fully on screen at `[72,2112]–[1008,2256]` of a 2352px window, with the
  bar below it. No reflow was seen across eight cold starts. Worth recording that the 56px budget
  came from a 400×900 test surface and this device has more room than that — the constraint is
  real but it is not tight here.
- **T025 (logged-in half) — PASS.** *My studies* opened the picker directly and listed the
  account's real studies, with no login step anywhere.
- **T032 (scenario 4) — PASS.** Home, import, study picker, library, history, training and review
  were each walked: exactly one connect/disconnect control, on the home screen. The library's 003
  tile is gone.

### What the pass found that the tests did not

The import screen still carried 003's line: **"Paste a study address, or pick one of your own
after logging in. A public study needs no login."**

That sentence tells the player to log in, on the one screen this feature removed the login from,
and does not say where the account went. Every test passed: `import_no_login_test.dart` asserted
that no login *widget* exists in any state, and nobody asserted the prose. The screen offered no
login and simultaneously instructed the player to perform one.

Fixed — the line now says a public study needs no account and that picking your own uses the
account connected on the home screen — with a regression test that reads every `Text` on the
import screen in all three account states and requires any mention of logging in to also name the
home screen. The test was confirmed to fail against the old string before the fix was kept, and
the corrected copy was re-verified on the device it was found on.

This is the second feature running where the device pass produced exactly one defect and it was a
sentence. Both times the assertion was about widgets and the defect was about words.

### Still not verified, and why

- **The login itself (T019).** The account was already connected, and the only way to test
  logging in is to disconnect first — which calls `revokeToken()` against the owner's real
  Lichess account. Not something to do on someone's behalf, and the same wall 003 hit from the
  other side.
- **Disconnect, and the expired state (T032 scenarios 5 and 6).** Same reason for disconnect.
  Forcing an expiry needs a build with a shifted clock installed over the owner's data; the unit
  tests cover the transition thoroughly, and the device-level claim is untested.
- **A fresh install that never connects (T039).** Would destroy the owner's collections and four
  sessions of history. What was checked instead, on the existing install: a session ran
  start-to-review and the library, import and history screens were walked with the app never
  asking about Lichess.

All three need the account holder, and all three are cheap once they choose to spend the login.

### The account holder's half of the pass, 2026-08-15

Three things needed the owner's Lichess credentials, and they ran them on the same device
immediately after. Driven by hand; the readings below were taken from the host between steps.

**Disconnect (T032 scenario 5): PASS.** The bar went to `Lichess · Not connected`. Both
collections, all six sessions, and a past review of the *Lichess-imported* collection — solution,
study title and source URL — were all untouched. Disconnecting sent 7,727 bytes, which is
`revokeToken()` doing what it is meant to do. This is SC-010 on hardware: an imported study is
local content, not a view onto the account, and a session played against one stays readable with
the account gone.

**Logging in from the home screen (T019): PASS.** The disclosure sheet appeared before the
browser did, Lichess's page named this repository and `study:read`, and the bar came back naming
the account. The round trip cost 9,239 bytes.

**FR-019, tested from both sides rather than inferred.** The byte count alone would only have
suggested that nothing extra was fetched. The direct version: if logging in had prefetched the
study list, opening the picker afterwards would have been free. It cost 11,448 bytes — within 2%
of the 11,651 measured earlier — so the list is fetched when the player opens the picker and at
no other time. Then three cold starts on the newly written credential: **0 bytes**, which extends
the launch guarantee from a credential planted by a test to one written by the real OAuth flow.

**Still not done: T039**, the fresh install, and **T032 scenario 6**, the expired state. The first
would destroy two collections and six sessions of real history to prove something already
half-covered; the second needs a clock-shifted build and would delete a working token. Both were
judged not worth their cost, which is a different thing from being unverified by accident.

### T039 on a throwaway user, 2026-08-15

T039 asks for a fresh install, and the phone held two collections and six sessions of real
history. Rather than trade those for the test, Android's multi-user support was used: a secondary
user was created, the package was installed into it with `pm install-existing --user 10`, and the
device was switched to that user. A secondary user gets its own data directory, so this is a
first-ever launch in every sense the app can detect, with user 0 untouched throughout.

**What was confirmed on the fresh install:**

- **First launch.** The bundled samples were seeded as an ordinary collection (003 FR-033), the
  bar read `Lichess · Not connected`, and nothing prompted, nagged or blocked.
- **A whole session.** Start, three commits, review, three grades, finish. Then history, showing
  the one session just played.
- **Deleting the last collection.** The warning was the cannot-be-undone one, deleting worked,
  and the home screen fell back to the empty-library state — **with the account bar still on it**,
  which is the second body state FR-001 has to cover and the state a player is most likely to want
  an account in.
- **Importing again with no account** (FR-016). A public study by pasted address: 7 positions, on
  a profile that had never connected to anything. Tapping the button twice produced the duplicate
  warning, which is 003 FR-010 confirming itself by accident.
- **The app never asked about Lichess.** Every mention of it across the whole run was one the
  player had gone looking for.

**What could not be done there, and why.** The file-picker leg needs a PGN in that user's
storage, and `adb push` writes to user 0 whatever the foreground user is — `adb shell` is bound to
user 0 by design, and copying across users is refused. So `file_selector` through the Storage
Access Framework is *still* unexercised on device, which was already 003's known gap (its T034).
The picker itself was opened and driven far enough to confirm it launches
`com.android.documentsui` and returns cleanly; only choosing a file was impossible.

**Cleanup.** The device was switched back to user 0, the throwaway user removed, and the fixture
deleted from the host and from both the device paths it had been written to. Switching users
leaves the phone on its lock screen, which is expected and needs the owner's PIN.

### The second defect the device found

Asking for **My studies** on a never-connected install said:

> That study is not public, so it needs a connected Lichess account. Connect one on the home
> screen.

The player named no study. That is `NotLoggedInError`'s wording — written for someone who pasted
the address of a private study — reused in a place where its first clause is not about anything.
The message named the right fix and was still about the wrong thing, and FR-017 only asked for
the fix, so nothing caught it.

Now a `studiesNeedAccountMessage` of its own, used by both the import screen and the picker's
defensive state: "Picking from your own studies needs a connected Lichess account. Connect one on
the home screen." The expired case keeps its own sentence, because an expired login and no login
are different problems. Regression assertions added for both halves — that the message names your
own studies, and that it does not begin by talking about "that study".

Two features, two device passes, three defects between them, and every one was a sentence.
