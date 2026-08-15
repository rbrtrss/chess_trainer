# Phase 0 Research: Lichess Login on the Home Screen

**Feature**: [spec.md](./spec.md) | **Date**: 2026-08-15

The specification asks for a small move — a login that lives on the first screen instead of two
screens into import. The design is small too, with one exception: the app cannot currently *say*
that a login expired, and the guard test that replaced feature 003's lost offline guarantee
forbids the obvious way of asking whether one is connected. Those two are D1–D3 and are most of
the work here.

Decisions are numbered so tasks and code comments can cite them.

---

## D1: Account state is read from the credential store, not from `LichessAuth`

**Decision.** The home screen learns whether an account is connected from a new, network-free
reader built on `CredentialStore` and a clock. `LichessAuth.current()` is deleted, and
`lichessConnectionProvider` — which called it — is replaced by `lichessAccountProvider`.

**Rationale.** `test/ui/no_network_during_training_test.dart` drives the whole training flow
against `_ExplodingAuth`, whose every method fails the test on contact, and asserts that opening
the app touches neither it nor the API. That test is not incidental: it is the behavioural
replacement for the guarantee 003 gave up when the manifest started declaring `INTERNET`, and
its own comment says that weakening it to make something else pass leaves nothing behind.

Putting the account on the home screen means reading account state at startup. If that read goes
through `LichessAuth.current()`, the test fails, and the only ways out are to stop asserting on
`current()` or to teach the fake to answer it — both of which turn "no method of the login object
is touched at startup" into "no method except this one", judged by hand, forever.

Splitting the read out avoids the question. `current()` only ever read the credential store and
checked a date; nothing about it needed to sit on the interface that also opens browsers and
posts to `/api/token`. Moved out, the exploding fake keeps exploding on all its methods, the
startup assertion stays absolute, and the home screen's read is *structurally* incapable of
reaching the network rather than merely believed not to.

**Alternatives considered.**

- *Teach `_ExplodingAuth.current()` to answer from an in-memory store.* Rejected. It is exactly
  the weakening the test warns against, and the exemption would have to be re-justified every
  time someone adds a method.
- *Keep `current()` and have the home screen not use it — cache the state at login.* Rejected:
  a cache that must survive a relaunch is the credential store with extra steps.
- *Read the state in `main()` before `runApp`.* Rejected under D5.

**Consequence.** `LichessAuth` shrinks to `logIn` and `logOut` — the two operations that really
do talk to Lichess. The interface now says what it is.

---

## D2: Three account states, not two

**Decision.** A sealed `LichessAccount` in `lib/domain/lichess/` with three cases:
`AccountDisconnected`, `AccountConnected(LichessConnection)`, `AccountExpired(LichessConnection)`.

**Rationale.** FR-013 requires the home screen to say that a login has expired and offer to log
in again. The app cannot say that today: `current()` returns `LichessConnection?`, and an expired
credential is cleared and reported as `null` — the same answer given to a player who has never
logged in at all. "Log in to Lichess" and "your login expired, log in again" are different
sentences, and only the second one explains why a study that imported last month does not import
today.

Three states also give the *bar* three renderings and the plan a checkable contract
([account-api.md](./contracts/account-api.md)) rather than a boolean and some hedging.

**Alternatives considered.**

- *`LichessConnection?` plus a separate `bool expired`.* Rejected: two fields that can disagree,
  and every reader has to remember the combination that cannot happen.
- *Report expiry only when a request fails with 401.* Rejected: that is the state of affairs
  this feature exists to fix — the player finds out mid-import, which is the worst moment and
  requires a network round trip to reach.

---

## D3: Expiry deletes the token and keeps the name

**Decision.** When the reader finds a stored credential whose expiry has passed, it deletes the
**token** and leaves the username and expiry date in place, then reports `AccountExpired`.
`CredentialStore` gains `expireToken()`. Disconnecting still clears all three keys.

**Rationale.** Feature 003's D5 is a rule worth keeping: the app never holds a token it knows is
dead, and never makes a request that is certain to fail. Naming the expired state seems to
require breaking that rule — you cannot say "your login as *roberto* expired" if you threw the
credential away — but only the token is the dangerous half. The username and the expiry date are
not secrets, grant nothing, and cannot be used to make a request. Deleting the token alone keeps
D5 exactly ("`readToken()` returns null, so no request can be made") and makes the state
nameable.

It also means the expired state is derivable from what is already stored: `readConnection()`
returns the name and date, `isExpiredAt` decides. No new key, no second source of truth.

**Alternatives considered.**

- *Keep the whole credential and rely on callers checking state first.* Rejected: it holds a
  dead token indefinitely, and "every caller checks first" is a rule enforced by discipline.
- *Write a separate `lichess_last_username` marker at login.* Rejected: a second record of the
  same fact, which will disagree with the first one eventually.
- *Clear everything and show the generic disconnected state.* Rejected: it is today's behaviour
  and FR-013 exists because it is not good enough.

**Note.** The token is deleted during what is otherwise a read, on the home screen's build path.
It is one local delete, in a case that arises about once a year per player, and it is what
`current()` already did.

---

## D4: The account is a fixed bar at the foot of the home screen

**Decision.** A single element pinned below the scrolling body of the session setup screen, in
every state of that screen including the empty library. Connected: `Lichess · <username>` with
*Disconnect*. Disconnected: `Lichess · Not connected` with *Connect*, plus the permissions line
(D6). Expired: `Lichess · <username> — login expired` with *Log in again* and *Disconnect*.

**Rationale.** FR-001 wants the state legible without any action, which rules out anything
behind a tap; FR-006 wants it not to dominate a screen whose job is to start a session, which
rules out anything in the middle of the body. A footer satisfies both, is visible without
scrolling on a phone, and survives the setup screen's two body states — the normal form and
`_EmptyLibrary` — without being written twice.

**Alternatives considered.**

- *A fourth app-bar icon.* Rejected: an icon cannot say *which* account, and connected versus
  disconnected as two icon variants is a state nobody reads correctly.
- *A card in the body, above the start button.* Rejected: it scrolls away, and on the empty
  library it competes with the one thing the player should do.
- *A drawer or an account screen.* Rejected: the state would be one tap away, which is the
  complaint this feature answers, moved rather than fixed.

---

## D5: The bar occupies the same height in all states, including before it knows

**Decision.** The bar reserves one constant height — the tallest state's — from the first frame.
While the local read is in flight it renders that space empty: no spinner, no text, and no
guess. Nothing else on the screen waits for it.

**Rationale.** SC-005 forbids a spinner or a wait attributable to the account, and FR-004
forbids any network request, but the read is still asynchronous — three `flutter_secure_storage`
reads over a platform channel, usually a few milliseconds, occasionally more while the Android
keystore warms up on a cold start. Three renderings are possible in that window and two are
wrong: a spinner (which is a wait), and a guess at "not connected" (which flips to a username a
frame later and teaches the player that the app does not know what it is saying).

Reserving the space also keeps the launch free of reflow. Features 002 and 003 both spent effort
on this — `SessionFlow` holds the first frame rather than show a setup screen that grows a resume
prompt a moment later — and a bar that appears and shoves the body upward would undo it in the
one place every launch passes through.

**Alternatives considered.**

- *Hold the first frame for the account read, as `SessionFlow` does for the resume lookup.*
  Rejected: that hold exists because the resume prompt changes what the screen is *for*. The
  account changes nothing about starting a session, and putting the keystore on the launch path
  makes a slow device open slowly for a peripheral fact.
- *Read the credential in `main()` before `runApp`.* Rejected for the same reason, more so: it
  delays the first frame of the whole app, and `main()` is currently synchronous.
- *Let the bar size itself per state.* Rejected: the connected state is shorter than the
  disconnected one, so every launch by a connected player would reflow once.

**Cost, recorded.** A connected player permanently sees a little empty space where the
permissions line would be. That is the price of a stable first frame and it is worth it.

---

## D6: The permissions line is small print in the bar, not a confirmation step

> **Reversed during implementation. The bar has no room for it — see D6a below.**
> This entry is kept because the reasoning was sound and only the measurement was missing.

**Decision.** The disconnected bar carries the disclosure — that the app reads studies only,
posts nothing, and sends nothing about sessions anywhere — as a second, smaller line. *Connect*
starts the browser round trip immediately.

**Rationale.** FR-007 requires the disclosure where the login is offered, and SC-002 puts the
whole login at one action plus the login itself. A confirmation sheet carrying the same sentences
would satisfy the first and break the second. The wording already exists, in
`study_picker_screen.dart`'s log-in prompt, and moves across unchanged.

Lichess's own authorization page is the authoritative disclosure — it lists the scope being
granted, under the client id, which 003 deliberately set to this repository's URL so the player
can go and read what they are granting to. The bar's line is a summary shown before the player
leaves the app, not a replacement for it.

---

## D6a: The disclosure moved to a sheet, because the bar does not fit two lines

**Decision, taken during implementation on 2026-08-15.** The bar is one line, 56 logical pixels,
in every state. *Connect* opens a compact sheet carrying the disclosure and a **Log in to
Lichess** button; that button starts the browser round trip.

**What forced it.** D6 assumed a two-line bar was free. It is not. `resume_test.dart` failed on
the first run with the bar in place, and bisecting the bar's height against it gives a hard
budget:

| Bar height | `resume_test.dart` |
|---|---|
| 0, 40, 56 | passes |
| 72, 88 | **fails** — the Start button is no longer reachable |

The failing case is a 400×900 phone showing the offer to resume an unfinished session, which is
the screen's tallest state and an entirely ordinary one. A two-line bar needs about 88. So the
choice was never "small print or a sheet"; it was **small print or the screen's primary action**,
and a footnote does not outrank the Start button.

**What it costs.** FR-003 ("in one action") and SC-002 ("one action plus the login itself") as
originally worded are not met: connecting is two taps plus the login. Both were **amended on
2026-08-15**, by the owner's decision, to allow two — see
[spec.md, Amendments](./spec.md#amendments). The amendment records the reasoning rather than
quietly restating the requirement, and it does not excuse the fact that FR-003 went unnoticed
through implementation, the device pass and a code review, while SC-002 was flagged throughout.

The alternatives, and why each is worse:

- *Drop the disclosure and rely on Lichess's authorization page.* It is the authoritative
  disclosure and it does name the scope — but FR-007 asks for it **where the login is offered**,
  which means before the player leaves the app, and satisfying a requirement by pointing at
  someone else's page is not satisfying it.
- *Ellipsise the disclosure onto one line.* A truncated disclosure is not a disclosure.
- *Let the bar be tall and let the body scroll.* The body does scroll. The Start button being
  below the fold on a normal phone in a normal state is still a regression in the thing the
  screen exists to do.
- *Shrink something else on the home screen to make room.* Out of scope, and it would trade a
  known-good layout for a footnote.

---

## D7: Import stops short of the picker rather than dead-ending in it

**Decision.** On the import screen, *My studies* with no connected account does not navigate. It
says, inline, that this needs a connected Lichess account and that the account is on the home
screen. The study picker keeps an equivalent message with no login button, for the case where a
login expires between opening the picker and reading it.

**Rationale.** FR-015 removes the login from import; FR-017 requires the player be told what is
needed and where, rather than meeting an empty list. Navigating to a screen whose only content is
an explanation is a dead end that has to be backed out of — worse than never leaving. The
picker's message stays as a defensive fallback because a screen that assumes it can only be
reached in one state eventually gets reached in another.

The picker's `_LogInPrompt` is deleted. It is the thing this feature is about.

---

## D8: Two error strings gain a place; the rest of the vocabulary is untouched

**Decision.** `messageForNetworkError` changes exactly two branches:

- `NotLoggedInError` → "That study is not public, so it needs a connected Lichess account.
  Connect one on the home screen."
- `LoginExpiredError` → "Your Lichess login has expired. Log in again from the home screen."

**Rationale.** The specification assumed 003's messages would be reused as they stand, and every
other branch is. These two named an action — logging in — whose location has moved, so a message
that does not say where now leaves the player looking for a button that is no longer there. Every
message in this app names what happened *and* what to do; that is the standard SC-011 set in 003
and it is what makes these two need editing rather than exempting.

`import_failure_messages_test.dart` asserts both strings and moves with them.

---

## D9: `connection_controller.dart` stays where it is

**Decision.** The Lichess providers stay in `lib/ui/library/connection_controller.dart`. The new
widget goes in `lib/ui/account/account_bar.dart`.

**Rationale.** The account is no longer a library concern, so the tidy move is to
`lib/ui/account/`. Against that: `layering_test.dart` permits exactly one file under `lib/ui/` to
import `lib/data/lichess/`, and that file also holds `StudyImporter`, which is genuinely an
import concern. Moving the file drags the study importer into an account directory; splitting it
makes two files that may name the network client, which is a real loosening of a rule that
currently reads "exactly one".

One rule enforced by a test beats one path that reads better. The comment at the top of the file
already explains why it is the single exception; it gains a line about why it did not move.

---

## D10: Failures are a snackbar, cancellation is nothing

**Decision.** A login that fails shows `messageForNetworkError` in a snackbar on the home screen,
following the `storage-failure` snackbar the setup screen already uses. A login the player backs
out of shows nothing at all.

**Rationale.** FR-010 wants the failure named and the screen still usable; FR-009 wants
cancellation treated as a non-event. `ConnectionController.logIn()` already returns `null` for
cancellation and throws for everything else (003), so both behaviours are already available and
this is a matter of where the message lands. The bar itself is one line and cannot hold a
sentence; the setup screen already knows how to say something transient.

---

## D11: The training-layer rule grows to cover the account

**Decision.** `layering_test.dart`'s forbidden-identifier list for `lib/ui/training/` gains
`LichessAccount`, `LichessConnection`, `lichessAccountProvider`, `connectionController` and
`username`.

**Rationale.** FR-020 says the account may not appear on a training screen. Nothing puts it there
today, and the reason to write the rule now is the same reason 002 and 003 wrote theirs: this
feature creates the ingredients — an account state watchable from any widget — and the rule is
what stops a later feature from adding "logged in as roberto" to a screen where the player is
calculating. A username is not evidence about the position, so this is not a Principle I
emergency; it is the standing rule that training screens gain no affordances.

---

## D12: Nothing about storage changes

**Decision.** The Drift schema stays at v2. No migration, no new table, no new column. The secure
store keeps its three existing keys.

**Rationale.** Worth stating because every feature since 001 has changed the schema and the
absence of a migration here is a fact to check rather than assume. This feature moves a control
and adds a domain type; the only persistent state involved — the credential — already exists in
the shape it needs.

---

## What this feature does not research

- **The OAuth flow.** Unchanged: same PKCE, same `S256`, same scope, same client id, same absence
  of a refresh path. 003's research D3, D5 and D6 stand.
- **Where the token lives.** Unchanged: `flutter_secure_storage`, `allowBackup="false"` (003 D4).
- **Validating a stored login against the service.** Out of scope by the specification, and
  forbidden on the home screen's path by FR-004.
- **Fetching studies.** Unchanged. The study list is still fetched when the picker opens and at
  no other time (FR-019).
