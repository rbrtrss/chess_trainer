# Feature Specification: Lichess Login on the Home Screen

**Feature Branch**: `004-home-lichess-login`

**Created**: 2026-08-15

**Status**: Draft

**Input**: User description: "the lichess login should be on the homepage of the app, not when you try to import studies"

## Overview

Feature 003 brought Lichess into the app and put the login where the code needed it rather than
where the player looks for it: two screens deep, behind import, behind "my studies". The
account therefore reads as a property of importing rather than a property of the app. There is
no way to find out whether you are logged in without starting an import you may not want to
make, and no way to log in *before* you need to — the offer arrives at the moment you have
already decided to fetch a study, and answering it means leaving for a browser and coming back.

This feature moves the account to the home screen. Whether an account is connected, which one,
and how to connect or disconnect are all visible on the first screen without navigating
anywhere. Import stops establishing the account and starts assuming it.

Two constraints shape the whole thing.

First, Principle II. The home screen is the first thing drawn on launch, and it must not make a
network request to say whether an account is connected — that answer is already on the device.
An app opened on a plane opens just as fast and still says what it knows. Nothing is fetched at
login either: logging in stores a credential and stops there.

Second, Lichess stays optional. The app trains on bundled samples and on PGN files from the
device with no account at all, and feature 003 was careful that a public study needs no login.
An account control on the home screen must not read as a required step, must never stand
between the player and starting a session, and must not turn the first screen into a login
wall. The player who never connects should be able to use this app for a year without the
question being put to them twice.

Principle I is barely touched here — the home screen is not a training screen, and a username
is not evidence about a position — but the check is still owed, because this feature adds an
element to the screen a session starts from. The account must not follow the player into
training, and nothing about it may vary with what is in the library.

## Amendments

### 2026-08-15 — the login takes two actions, not one

**Changed**: FR-003 and SC-002, both of which required the login to start in *one* action from the
home screen. They now allow two: asking to connect, and confirming after the app has said what the
login grants.

**Why**: FR-007 requires the app to state what the login is for and what it grants *where the
login is offered*. The design put that disclosure in the account bar as small print, which assumed
a two-line bar was free. It is not. Bisecting the bar's height against `resume_test.dart` gives a
hard budget — 56 logical pixels passes, 72 and 88 fail — because above that the **Start** button
drops off a 400×900 phone that is also showing the offer to resume an unfinished session.

So the real choice was never "small print or a sheet". It was **the disclosure or the screen's
primary action**, and a footnote does not outrank the button the screen exists for. The disclosure
moved to a sheet that *Connect* opens, and that sheet costs a tap.

**Why amend rather than fix**: satisfying "one action" means either dropping the disclosure — which
just moves the hole from FR-003 to FR-007 — or making the bar taller and raising the test surface
to a device that can afford it, which trades a known-good layout on small phones for a tap on
every phone. The constitution's bar for added complexity is "a concrete problem, not an
anticipated one", and nobody has met the two-tap login and complained. The disclosure before
leaving the app is worth more than the tap.

**What this does not excuse**: the requirement went unmet through implementation, the whole device
pass, and a code review, and was noticed only when the requirements were re-read one by one
against the evidence. SC-002 was flagged as a deviation throughout; FR-003 says the same thing in
the section that carries the MUSTs and was never named. Recorded in
[research D6a](./research.md#d6a-the-disclosure-moved-to-a-sheet-because-the-bar-does-not-fit-two-lines)
and in [tasks.md](./tasks.md#what-was-done-and-what-was-not).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Connect my account before I need it (Priority: P1)

The player opens the app, sees on the first screen that no Lichess account is connected, and
connects one — without importing anything, and without having decided yet whether they ever
will. Later, when they do import, the account is already there.

**Why this priority**: This is the feature. Everything else follows from the account being
reachable at the top level; if only this ships, the complaint that prompted the feature is
answered.

**Independent Test**: Launch with no stored credential, log in from the first screen, and
confirm the screen then names the connected account — with no import performed at any point.

**Acceptance Scenarios**:

1. **Given** the app has never been connected to Lichess, **When** the player opens it, **Then**
   the home screen shows that no account is connected and offers to connect one.
2. **Given** the home screen showing no account, **When** the player asks to connect and
   completes the login, **Then** the home screen shows the connected account by name.
3. **Given** the login is under way, **When** the player abandons it without completing it,
   **Then** they return to an unchanged home screen with no error and no account connected.
4. **Given** the login fails, **When** the player returns to the app, **Then** the home screen
   says what went wrong and what to do about it, and remains fully usable.
5. **Given** the player has connected an account, **When** they close the app and open it
   again, **Then** the home screen still shows that account without any network request.

---

### User Story 2 - Import without being asked to log in (Priority: P2)

The player goes to import a study from Lichess. If they are connected, their studies are
listed. If they are not, they are told that this particular path needs an account and where the
account lives — but the import screen never launches a login itself.

**Why this priority**: The other half of the user's sentence. It is separable from US1 —
removing the login from import is testable on its own — but it is worth less alone, because
without US1 there would be nowhere left to log in.

**Independent Test**: From the import screen, in both connected and disconnected states,
exercise every Lichess path and confirm no login is ever started from there.

**Acceptance Scenarios**:

1. **Given** a connected account, **When** the player asks to choose from their own studies,
   **Then** the studies are listed with no login step and no extra confirmation.
2. **Given** no connected account, **When** the player asks to choose from their own studies,
   **Then** they are told this needs a Lichess account and where in the app to connect one, and
   are not sent to a browser.
3. **Given** no connected account, **When** the player pastes a public study's address and
   imports it, **Then** it imports exactly as it did before, with no mention of logging in.
4. **Given** a connected account, **When** the player imports a study, **Then** the collection
   produced is indistinguishable from one produced before this feature.

---

### User Story 3 - Find the account in one place (Priority: P3)

The player wants to check which account is connected, or to disconnect it. There is one place
that answers both, and it is the home screen.

**Why this priority**: Consolidation and correctness of a control that already exists. Real
value — today the disconnect hides in the library while the login hides in import, so the
account has two homes and neither is obvious — but the app is not broken without it.

**Independent Test**: With an account connected, disconnect it from the home screen and confirm
the imported collections and past sessions are untouched, and that no other screen offers a
competing account control.

**Acceptance Scenarios**:

1. **Given** a connected account, **When** the player disconnects it from the home screen,
   **Then** the stored login is forgotten and every imported collection, position and past
   session remains exactly as it was.
2. **Given** an account disconnected a moment ago, **When** the player connects again, **Then**
   they use the same control they used to disconnect.
3. **Given** a stored login the app knows to have expired, **When** the player opens the app,
   **Then** the home screen says the login has expired and offers to log in again, without
   having contacted Lichess to find out.
4. **Given** any screen other than the home screen, **When** the player looks for a way to
   connect or disconnect an account, **Then** there is none.

---

### Edge Cases

#### Launch and offline

- What does the home screen show on first launch with the device offline? The same thing it
  shows online: no account connected, and an offer to connect that will fail with a clear
  message if taken. Connection state is a local fact.
- What happens if the player taps connect with no network? The login fails naming the missing
  connection, and says that everything already imported still works offline.
- Does anything about the account delay the first frame? No. If the home screen ever waits on
  the account, the feature is wrong.

#### The account itself

- What if the token was revoked on lichess.org, or the account deleted? The app cannot know
  without asking, and it does not ask. The home screen shows it as connected until the next
  import fails, which then reports the failure in the terms feature 003 established.
- What if the player logs in as a different account? Disconnecting and connecting again
  replaces it. Two accounts at once is not a state the app has.
- What if the login completes while the app was backgrounded long enough to be killed? The
  player returns to a home screen that reflects whatever was actually stored — connected if the
  credential was saved, not connected if it was not. No half state is shown.

#### Alongside a session

- What if an unfinished session is waiting to be resumed? The offer to resume and the account
  control both appear on the home screen, and neither displaces the other. Nothing about the
  account affects whether a session can be resumed.
- Can the player reach the account from training or review? No. The training screen gains no
  new affordance, for the same reason it gained none in 003.
- Does connecting or disconnecting affect a session in progress? Never. Sessions read local
  content only.

#### Principle I

- Does a username on the home screen leak anything about a position? No — it is not evidence
  about the content, and the home screen is where collection names are already shown.
- Could the account control differ according to what is in the library, or which collection is
  chosen? It must not. It says one thing about the account and nothing about the content.

## Requirements *(mandatory)*

### Functional Requirements

#### The account on the home screen

- **FR-001**: System MUST show, on the home screen, whether a Lichess account is connected,
  without the player navigating anywhere or performing any action to find out.
- **FR-002**: System MUST name the connected account when there is one, so the player knows
  which account is in use.
- **FR-003**: Users MUST be able to reach a Lichess login from the home screen without first
  entering an import, and without hunting for it. Two actions at most: asking to connect, and
  confirming once the app has said what the login grants. *(Amended 2026-08-15 — see
  [Amendments](#amendments). This originally said "in one action", which the disclosure FR-007
  requires turned out to make impossible.)*
- **FR-004**: System MUST derive the displayed connection state from what is already stored on
  the device, and MUST NOT make any network request to render the home screen or to start the
  app.
- **FR-005**: System MUST NOT make the account a precondition of anything else. Starting,
  running, reviewing and resuming a session, and importing from a file, MUST behave identically
  connected and disconnected.
- **FR-006**: System MUST NOT present connecting as required or recommended: no interstitial,
  no repeated prompting, no blocking of the screen a session starts from.
- **FR-007**: System MUST state, where the login is offered, what it is for and what it grants —
  that it reads the player's studies, posts nothing, and sends nothing about their sessions
  anywhere.
- **FR-008**: System MUST start a login only in direct response to the player asking for one.
- **FR-009**: System MUST treat an abandoned or cancelled login as a non-event: the player
  returns to an unchanged home screen, with no error reported.
- **FR-010**: System MUST report a failed login in terms that name what happened and what the
  player can do, and MUST leave them on a working home screen with no account connected.

#### Disconnecting, and a login that has expired

- **FR-011**: Users MUST be able to disconnect the account from the home screen, which forgets
  the stored login and leaves every imported collection, position and past session untouched.
- **FR-012**: System MUST offer connecting and disconnecting in exactly one place. The account
  control that feature 003 placed in the collection library is removed rather than duplicated.
- **FR-013**: System MUST show a login it knows to have expired as an invitation to log in
  again, determined without contacting the service, and MUST NOT attempt to renew it silently.
- **FR-014**: Users MUST be able to connect again, after disconnecting or after an expiry,
  through the same control.

#### Import, after the move

- **FR-015**: System MUST NOT offer or start a login from any part of the import flow.
- **FR-016**: System MUST continue to import a public study from a pasted address with no
  account connected, unchanged from feature 003.
- **FR-017**: System MUST, when the player asks to choose from their own studies with no account
  connected, say that this needs a connected Lichess account and where in the app to connect
  one — rather than failing silently, showing an empty list, or dead-ending.
- **FR-018**: System MUST, when an account is connected, list the player's studies with no login
  step and no step that did not exist in feature 003.
- **FR-019**: System MUST NOT fetch anything as a consequence of logging in. The study list is
  fetched when the player opens the picker, and at no other time.

#### Withholding what the account says

- **FR-020**: System MUST NOT show the account state, the username, or any control derived from
  them on a training screen.
- **FR-021**: System MUST NOT vary the account control by the library's contents, by which
  collection is chosen, or by anything about a session.

#### Environment

- **FR-022**: A connected account MUST survive the app being closed, reopened and updated, as it
  did in feature 003.

### Key Entities

- **Account connection**: what the app knows locally about the player's Lichess account —
  whether one is connected, which account it is, and whether the stored login is known to have
  expired. Already exists; this feature changes where it is surfaced, not what it holds.
- **Home screen**: the first screen after launch, where a session is set up, an unfinished
  session is offered back, and — from this feature — the account is shown.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A player can tell whether a Lichess account is connected in zero navigation steps
  from launch.
- **SC-002**: A player can go from launching the app to a completed Lichess login in no more than
  two actions plus the login itself, without visiting the import screen, and reads what the login
  grants before leaving the app. *(Amended 2026-08-15 — see [Amendments](#amendments); this said
  "one action".)*
- **SC-003**: A player who never connects an account can install the app, import a file, and
  train for as long as they like without the app asking them to log in — the question is put to
  them zero times unprompted.
- **SC-004**: Launching the app and drawing the home screen produces zero network requests, in
  every account state — connected, disconnected, and expired — confirmed by packet inspection
  with the radios on.
- **SC-005**: The home screen's first frame is drawn in the same time online and offline, with
  no spinner, wait or placeholder attributable to the account.
- **SC-006**: The import flow contains zero login prompts in every state a player can reach it
  in.
- **SC-007**: Exactly one control in the app connects or disconnects the account.
- **SC-008**: A player whose login has expired learns of it on the home screen before starting
  an import, in 100% of cases where the app can determine the expiry locally.
- **SC-009**: No training screen contains the username or the account state, confirmed by
  reading everything a screen reader would announce — not by eye.
- **SC-010**: Disconnecting leaves 100% of imported collections, positions and past sessions
  readable and trainable.

## Assumptions

- "The homepage" is the session setup screen — the first screen after launch, the one that
  carries the app's name, the offer to resume an unfinished session, and the ways into import,
  the library and history. There is no separate home screen to build.
- The login control and the disconnect control consolidate onto the home screen, which means the
  library's account section is removed. Two controls for one account invite disagreement about
  which is authoritative, and the library is not where anyone looks for an account.
- Connection state is read from local storage and is not validated against Lichess. A token
  revoked on the website still reads as connected until an import fails. This is accepted
  deliberately: validating it would put a network call behind the first frame, which Principle
  II forbids and which would make the app open slowly on a bad connection.
- The login mechanism itself is unchanged — same browser round trip, same scope, same storage,
  same absence of a refresh path. Only where it starts moves.
- One account at a time. Switching accounts means disconnecting and connecting again.
- The exact visual treatment on the home screen — an app-bar item, a row, a card — is left to
  planning. The specification requires only that it is on the first screen, that it says what
  the state is, and that it does not dominate a screen whose job is to start a session.
- Feature 003's error messages for network and login failures are reused as they stand; this
  feature moves where they can appear, not what they say.

## Out of Scope

- Any change to what is imported, how it is parsed, what is rejected, or what is withheld.
- Any change to the OAuth mechanism, the scopes requested, or how the credential is stored.
- Fetching anything at launch or at login, including refreshing the study list in the
  background.
- Anything on Lichess beyond studies — games, puzzles, profile, ratings. Puzzles are a later
  feature and will bring their own questions.
- Validating a stored login against the service, in any form.
- iOS.
