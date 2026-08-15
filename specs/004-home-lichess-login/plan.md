# Implementation Plan: Lichess Login on the Home Screen

**Branch**: `004-home-lichess-login` | **Date**: 2026-08-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-home-lichess-login/spec.md`

## Summary

The Lichess account moves from two screens inside import to a fixed bar at the foot of the home
screen, where its state is legible without doing anything. Import stops offering logins and
starts assuming them.

Most of this is moving widgets. Two things are not, and they are what
[research.md](./research.md) is mostly about:

- **The app cannot currently say that a login expired.** `LichessAuth.current()` clears an
  expired credential and returns `null` — the same answer a player who never logged in gets.
  FR-013 needs those to be different sentences, so account state becomes a three-case sealed type
  and expiry deletes the *token* while keeping the name and the date (D2, D3). Feature 003's rule
  that the app never holds a token it knows is dead survives intact.
- **Reading the account at startup must not go through `LichessAuth`.**
  `no_network_during_training_test.dart` drives the whole training flow against a login object
  that fails the test on contact, and that test is the behavioural replacement for the offline
  guarantee 003 gave up. Asking it through `LichessAuth.current()` would force the test to be
  weakened. Instead the read moves to a `LichessAccountReader` built on the credential store,
  which holds no HTTP client and therefore *cannot* reach the network (D1). The guard stays
  absolute and gets stronger: the app now shows a username at launch while still touching neither
  the API nor the login.

The rest: a bar that reserves constant height so the first frame never reflows (D5), the
permissions disclosure shown before the browser opens (D6, revised during implementation to a
sheet — see D6a and [tasks.md](./tasks.md#what-was-done-and-what-was-not)), import telling the
player where the account lives instead of dead-ending in a picker (D7), and two error strings
that gain a place (D8).

No database change. No new dependency. No change to OAuth.

## Technical Context

**Language/Version**: Dart 3.13.0 (bundled with Flutter 3.47.0)

**Primary Dependencies**: unchanged. No package is added, removed or upgraded by this feature.
The Lichess side continues to rest on `flutter_web_auth_2`, `flutter_secure_storage`, `http` and
`crypto` as feature 003 adopted them, licence-checked at the time.

**Storage**: unchanged. Drift schema stays at **v2** — no migration (research D12). The credential
keeps its three `flutter_secure_storage` keys; the only new operation is deleting the token while
keeping the username and expiry.

**Testing**: `flutter test`. Everything in this feature is device-free: the account reader against
`InMemoryCredentialStore` and an injected clock, the bar and the import screens as widget tests,
and the guard tests as source-level rules. No test makes a real network request, and no test
touches a platform channel.

**Target Platform**: Android (phone). The one thing that genuinely needs hardware is the login
itself, which needs the account holder's credentials in a browser.

**Project Type**: Mobile app, single Flutter module.

**Performance Goals**: the home screen's first frame is drawn no later than it is today —
nothing waits on the account (SC-005), and the account read is three local reads that overlap the
resume lookup `SessionFlow` already holds for.

**Constraints**: zero network requests on the launch path in every account state (FR-004,
SC-004). Networking stays confined to `lib/data/lichess/` and reachable from exactly one file
under `lib/ui/` (Principle II). The domain layer keeps zero Flutter imports. The token stays
unreadable outside `lib/data/lichess/`, and is deleted the moment it is known to be dead.

**Scale/Scope**: one account. Four files changed in `lib/ui/library/`, one new widget, one new
domain type, one new data-layer reader, one method added to a store and one removed from an
interface. Two screens lose a control.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | How this design satisfies it |
|---|---|---|
| **I. Delayed feedback (non-negotiable)** | PASS | The account says nothing about any position, and the home screen already shows collection names, so a username there leaks nothing new. The exposure this feature creates is *future*: account state becomes watchable from any widget, and "logged in as roberto" is the kind of thing that later gets added to a screen where someone is calculating. D11 answers it now by extending `layering_test.dart`'s training-directory rule to the account identifiers, and contract invariant 7 forbids the bar varying with the library's contents so it can carry no information about the position either way. |
| **II. Offline-first** | PASS, and slightly strengthened | FR-004 forbids a network request to render the home screen, and D1 makes that structural rather than trusted: the object read at startup is built on the credential store and holds no client. The startup guard in `no_network_during_training_test.dart` keeps `_ExplodingAuth` failing on every method — the account is now shown at launch *without* that test being relaxed, which is a stronger statement than the one it made before. Nothing is fetched at login (FR-019); the study list is still fetched only when the picker opens. |
| **III. Delegated chess correctness** | PASS, not engaged | No chess code. No parsing, no position handling, no board. |
| **IV. Layering** | PASS | The new domain type is pure Dart. The new reader is data-layer and takes a `CredentialStore` and a clock. `connection_controller.dart` stays the one file under `lib/ui/` that names the implementation (D9), so the "exactly one" rule stays exactly one rather than becoming "two, for good reasons". The new widget watches a provider and imports nothing from `lib/data/`. |
| **V. Testing floor** | PASS | Nothing on the floor is disturbed: the move tree, comparison, session machine and study extraction tests are untouched. The floor gains no item — account state is not on it — but the feature ships its own: the reader's three states and its expiry side effect, the bar's four renderings, the import screen offering no login in any state, and the two extended guard tests. |
| **Licensing** | PASS, not engaged | No dependency added. |
| **No secrets** | PASS | The token's blast radius shrinks: it is now deleted at the moment expiry is *observed* rather than at the moment it is next used, and the username and date that survive grant nothing. Nothing new reads the token; `LichessAccountReader` deliberately does not call `readToken()` at all. |
| **Complexity justified** | PASS | Nothing speculative. The one structural addition — a reader separate from the auth object — exists to keep an existing test absolute, and it also deletes a method rather than adding one on balance. |

**Post-design re-check (after Phase 1)**: still PASS. Two judgements sharpened during design and
are recorded rather than waved through: expiry now leaves a username in secure storage where
previously it left nothing (D3 — accepted, because the alternative is an app that cannot tell a
player why their imports stopped working), and the bar permanently reserves space a connected
player does not use (D5 — accepted, because the alternative is a reflow on every launch).

## Project Structure

### Documentation (this feature)

```text
specs/004-home-lichess-login/
├── plan.md                  # This file
├── spec.md                  # Feature specification
├── research.md              # Phase 0 — decisions D1–D12
├── data-model.md            # Phase 1 — the account type, storage, state transitions
├── quickstart.md            # Phase 1 — how to run and validate
├── contracts/
│   └── account-api.md       # Phase 1 — types, providers, the bar, what is removed
├── checklists/
│   └── requirements.md      # Spec quality checklist
└── tasks.md                 # Phase 2 — created by /speckit-tasks, not here
```

### Source Code (repository root)

```text
lib/
├── domain/
│   └── lichess/
│       ├── lichess_connection.dart      # unchanged
│       └── account.dart                 # NEW — sealed LichessAccount, three cases
├── data/
│   └── lichess/
│       ├── credential_store.dart        # CHANGED — expireToken() added, both implementations
│       ├── account_reader.dart          # NEW — local-only read, no HTTP client
│       ├── lichess_auth.dart            # CHANGED — current() removed
│       ├── lichess_api.dart             # unchanged
│       ├── lichess_gateway.dart         # unchanged
│       └── study_link.dart              # unchanged
└── ui/
    ├── account/
    │   └── account_bar.dart             # NEW — the four renderings, constant height
    ├── session/
    │   └── session_setup_screen.dart    # CHANGED — mounts the bar below both body states
    └── library/
        ├── connection_controller.dart   # CHANGED — lichessAccountProvider replaces
        │                                #   lichessConnectionProvider; two messages reworded
        ├── collection_list_screen.dart  # CHANGED — _ConnectionTile removed
        ├── study_picker_screen.dart     # CHANGED — _LogInPrompt removed, message kept
        └── import_screen.dart           # CHANGED — My studies gated inline when disconnected

test/
├── domain/
│   └── layering_test.dart               # CHANGED — training rule gains account identifiers
├── data/
│   ├── account_reader_test.dart         # NEW — three states, expiry side effect, bad data
│   └── lichess_auth_test.dart           # CHANGED — current() tests move out
└── ui/
    ├── home_account_test.dart           # NEW — the bar, in every state, and the login flow
    ├── import_no_login_test.dart        # NEW — no login anywhere in import, in any state
    ├── no_network_during_training_test.dart  # CHANGED — a connected launch, still no contact
    ├── collection_list_test.dart        # CHANGED — connection group removed
    └── import_failure_messages_test.dart     # CHANGED — two reworded messages
```

**Structure Decision**: the three-layer structure is unchanged. The one new directory,
`lib/ui/account/`, holds the widget; its providers stay in `lib/ui/library/connection_controller.dart`
because that file is the single permitted exception to the no-screen-names-the-network rule and
splitting it would make the rule "exactly two" (D9). The comment at the top of that file gains a
line saying why it did not move.

## Implementation sequence

Ordered so each step leaves the suite green.

1. **Domain and data, no UI.** Add `LichessAccount`; add `expireToken()` to both credential
   stores; add `LichessAccountReader` with its tests. `LichessAuth.current()` still exists at this
   point, so nothing breaks.
2. **Swap the provider.** `lichessAccountProvider` replaces `lichessConnectionProvider`; the two
   existing readers (`collection_list_screen.dart`, `study_picker_screen.dart`) are updated to the
   new type; `myStudiesProvider` gates on `AccountConnected`. Then delete `LichessAuth.current()`
   and the tests that covered it there.
3. **The bar.** `account_bar.dart` with its four renderings, mounted on the home screen below both
   body states. `home_account_test.dart` alongside it.
4. **Take the login out of import.** Delete `_LogInPrompt`; gate *My studies* inline; reword the
   two messages; delete `_ConnectionTile` from the library screen and move its two tests to the
   bar's test.
5. **Guards and prose.** Extend the training-directory rule with the account identifiers; add the
   connected-launch case to the no-network test; update `README.md` where it describes logging in
   from import.
6. **Device pass.** The login itself, which no test can cover — see quickstart scenarios 2 and 6.

## Complexity Tracking

No constitution violations to justify. The feature adds no dependency, no layer, no schema
version and no screen, and removes two controls and one interface method.

## Known risks

| Risk | Where it bites | What is done about it |
|---|---|---|
| The account read is asynchronous on the launch path | A slow Android keystore makes the bar arrive a frame or two late | The space is reserved and empty, never a spinner and never a guess (D5). Nothing else on the screen waits for it, so a slow read delays nothing but the bar's own contents. |
| `expireToken()` writes during a read | The home screen's build path performs a delete | One local delete, in a case that arises about once a year per player, and it is what `current()` already did on the same path. |
| A revoked token still reads as connected | The bar says "Connected as roberto" when Lichess disagrees | Accepted and specified (Assumptions). Finding out costs a network request on the launch path, which FR-004 forbids. The next import fails with 003's message. |
| Deleting `LichessAuth.current()` touches a well-tested file | `lichess_auth_test.dart` has four assertions on it | They move to `account_reader_test.dart` rather than being dropped, and gain the expired case they could not express before. |
| The bar is one more thing on the screen a session starts from | Principle I creep, later rather than now | D11's rule, and contract invariant 7 (the bar cannot vary with the library). |
| The device pass depends on the account holder | The login is the one path no test covers, and it needs real credentials in a browser | Left explicitly to the owner in quickstart scenario 2, as it was in 003. |
| **Materialised**: the bar had no room for the disclosure | D6 assumed a two-line footer was free; at 72px and above the Start button leaves the screen on a 400×900 phone showing the resume offer | Bar cut to one line at 56, disclosure moved to a sheet (D6a). Cost FR-003 and SC-002 as originally worded; both amended on 2026-08-15 by the owner's decision, with the reasoning recorded in [spec.md, Amendments](./spec.md#amendments). |
