# Contract: the Lichess account

**Feature**: [spec.md](../spec.md) | **Research**: [research.md](../research.md) |
**Data model**: [data-model.md](../data-model.md)

What the account surface is after this feature, in the two places it has one: the types and
providers the app is built from, and the pixels the player is answerable to. Feature 003's
[lichess-api.md](../../003-position-import/contracts/lichess-api.md) still describes the network
surface and is unchanged by this feature.

---

## 1. Domain

```dart
// lib/domain/lichess/account.dart — pure Dart

sealed class LichessAccount {
  const LichessAccount();
}

final class AccountDisconnected extends LichessAccount {
  const AccountDisconnected();
}

final class AccountConnected extends LichessAccount {
  const AccountConnected(this.connection);
  final LichessConnection connection;
}

final class AccountExpired extends LichessAccount {
  const AccountExpired(this.connection);
  final LichessConnection connection;
}
```

Sealed so that every `switch` over it is exhaustive and a fourth state cannot be added without
the compiler naming every place that must handle it.

No token, here or anywhere reachable from the domain layer (003 FR-021).

---

## 2. Data layer

### `CredentialStore` — one addition

```dart
abstract interface class CredentialStore {
  Future<String?> readToken();
  Future<LichessConnection?> readConnection();
  Future<void> write({required String token, required DateTime expiresAt, required String username});
  Future<void> clear();

  /// Deletes the token and keeps the username and expiry (research D3).
  ///
  /// After this, [readToken] returns null — no request that is certain to fail
  /// can be made — while [readConnection] still answers "whose login, and when
  /// it ran out", which is what the expired state needs to be sayable.
  Future<void> expireToken();
}
```

`InMemoryCredentialStore` implements it the same way for tests.

### `LichessAccountReader` — new, and network-free by construction

```dart
// lib/data/lichess/account_reader.dart

class LichessAccountReader {
  LichessAccountReader({required CredentialStore credentials, DateTime Function()? now});

  /// Reads local storage and nothing else.
  Future<LichessAccount> read();
}
```

Behaviour:

| Stored | Returns | Side effect |
|---|---|---|
| nothing | `AccountDisconnected` | none |
| a credential, expiry in the future | `AccountConnected(connection)` | none |
| a credential, expiry passed | `AccountExpired(connection)` | `expireToken()` |
| a credential whose expiry will not parse | `AccountDisconnected` | `clear()`, inside `readConnection` — a credential nothing can date is not a credential, and leaving it orphans a usable token behind an account reported as disconnected |

It holds no HTTP client and takes none. This is the whole point of research D1: the object the
home screen reads at startup *cannot* reach the network, rather than being trusted not to.

### `LichessAuth` — shrinks

```dart
abstract interface class LichessAuth {
  Future<LichessConnection> logIn();
  Future<void> logOut();
  // current() is gone — see research D1.
}
```

`PkceLichessAuth` loses `current()` with it. Its two remaining methods are the two that really do
talk to Lichess, which is what lets `_ExplodingAuth` keep failing the test on every one of them.

---

## 3. Providers

In `lib/ui/library/connection_controller.dart`, which stays the single file under `lib/ui/`
allowed to name the Lichess implementation (research D9).

| Provider | Type | Notes |
|---|---|---|
| `credentialStoreProvider` | `Provider<CredentialStore>` | unchanged |
| `lichessGatewayProvider` | `Provider<LichessGateway>` | unchanged |
| `lichessApiProvider` | `Provider<LichessApi>` | unchanged |
| `lichessAuthProvider` | `Provider<LichessAuth>` | unchanged shape, two methods fewer |
| **`lichessAccountProvider`** | `FutureProvider<LichessAccount>` | **new** — built from `credentialStoreProvider`, never from `lichessAuthProvider`. Reads local storage. Replaces `lichessConnectionProvider`. |
| `myStudiesProvider` | `FutureProvider<List<StudySummary>>` | now gated on `lichessAccountProvider`; throws `NotLoggedInError` when disconnected and `LoginExpiredError` when expired — the two have different fixes and deserve different sentences |
| `connectionControllerProvider` | `Provider<ConnectionController>` | `logIn()` and `logOut()` unchanged in behaviour; both invalidate `lichessAccountProvider` |

`lichessConnectionProvider` is deleted. Nothing may reintroduce a provider that answers this
question through `LichessAuth`.

---

## 4. The home screen's account bar

`lib/ui/account/account_bar.dart`, rendered below the scrolling body of `SessionSetupScreen` in
both of that screen's body states — the setup form and the empty library.

### States

| Account state | Key | Shows | Actions |
|---|---|---|---|
| still reading | `account-bar-unknown` | nothing — reserved space only | none |
| `AccountDisconnected` | `account-disconnected` | `Lichess · Not connected` | `connect-lichess` |
| `AccountConnected` | `account-connected` | `Lichess · Connected as <username>` | `disconnect-lichess` |
| `AccountExpired` | `account-expired` | `Lichess · <username> — your login has expired` | `log-in-again`, `disconnect-lichess` |

Every state is one line and **56 logical pixels tall**, a budget measured rather than chosen
(research D6a). `connect-lichess` and `log-in-again` both open the disclosure sheet below rather
than starting a login directly.

### The disclosure sheet, keyed `connect-lichess-sheet`

Opened by `connect-lichess` or `log-in-again`; carries the permissions line and a
`confirm-log-in` button, which is what starts the browser round trip. Dismissing it asks Lichess
for nothing.

### Fixed strings

- Permissions line (moved verbatim from `study_picker_screen.dart`, shown in the sheet — research
  D6a):
  *"The app asks only to read your studies. It never posts anything, and nothing about your
  sessions is sent anywhere."*
- Connect: *"Connect"* · Log in again: *"Log in again"* · Disconnect: *"Disconnect"*

### Invariants

1. **Constant height in every state, including `account-bar-unknown`** (research D5). The first
   frame does not reflow when the read lands. The height is `accountBarHeight`, and raising it
   puts the Start button below the fold — `resume_test.dart` is what notices (research D6a).
2. **No progress indicator, ever.** Not while reading, not while logging in. A login that is
   under way disables its own button; it does not spin (SC-005).
3. **No network request on any build path** (FR-004). The bar watches
   `lichessAccountProvider` and nothing else.
4. **A cancelled login reports nothing** — no snackbar, no message, no state change (FR-009).
5. **A failed login shows `messageForNetworkError(error)` in a snackbar** keyed
   `account-login-failure`, and leaves the bar in its previous state (FR-010).
6. **Disconnect touches no collection, position or session** (FR-011, SC-010).
7. **The bar renders identically whatever the library holds** — same words, same height, same
   actions, whether there are 0 collections or 40, and whichever is chosen (FR-021).
8. **The bar exists on the home screen and nowhere else** (FR-012, FR-020). No training screen,
   no review screen, no library screen, no import screen carries an account control.

---

## 5. Import, after the move

| Situation | Before (003) | After (004) |
|---|---|---|
| *My studies*, connected | opens the picker, lists studies | unchanged |
| *My studies*, disconnected | opens the picker, which offers a login | does not navigate; says inline that this needs a connected account and that it is on the home screen (`studies-need-account`) — research D7 |
| Study picker reached while disconnected | `_LogInPrompt` with a log-in button | message only, no login button (defensive; reachable if a login expires between opening and reading) |
| Pasted address, public study, disconnected | imports | unchanged |
| Pasted address, private study, disconnected | fails with `NotLoggedInError` | same failure, message now names where to connect (research D8) |

`_LogInPrompt` is deleted, along with its key `lichess-login-prompt` and its button
`log-in-to-lichess`.

### Message changes

Exactly two branches of `messageForNetworkError` change:

| Error | After |
|---|---|
| `NotLoggedInError` | "That study is not public, so it needs a connected Lichess account. Connect one on the home screen." |
| `LoginExpiredError` | "Your Lichess login has expired. Log in again from the home screen." |

Every other branch is unchanged, including the offline, rate-limit, not-a-study-link, unavailable
and storage-write messages.

---

## 6. What is removed

| Removed | Where it was | Why |
|---|---|---|
| `_ConnectionTile` | `lib/ui/library/collection_list_screen.dart` | FR-012 — one account control, and the library is not where anyone looks for it |
| `_LogInPrompt` | `lib/ui/library/study_picker_screen.dart` | FR-015 — import does not offer logins |
| `lichessConnectionProvider` | `connection_controller.dart` | research D1 — replaced by `lichessAccountProvider` |
| `LichessAuth.current()` | `lib/data/lichess/lichess_auth.dart` | research D1 — a local read on an object whose other methods are network calls |

Keys `lichess-connected` and `lichess-disconnected` move from the library screen to the bar with
their meanings intact; `disconnect-lichess` keeps its name in its new home.

---

## 7. Invariants the tests hold

1. Opening the app makes **zero** calls to `LichessApi` and **zero** to `LichessAuth`, in every
   account state — including connected, where the username is on screen (FR-004, SC-004). This
   is `no_network_during_training_test.dart` with `_ExplodingAuth` intact, which is only possible
   because of research D1.
2. No file under `lib/ui/training/` mentions `LichessAccount`, `LichessConnection`,
   `lichessAccountProvider`, `connectionController` or `username` (FR-020, research D11).
3. Exactly one file under `lib/ui/` imports `lib/data/lichess/` — still
   `connection_controller.dart` (Principle II, unchanged from 003).
4. No source file mentions `refresh_token` (003 FR-017, still asserted).
5. The import flow contains no login prompt in any reachable state (FR-015, SC-006).
6. Every account state renders a bar of the same height (SC-005).
7. A player who never connects can start, run and review a session with the account bar showing
   `Not connected` throughout, and is asked to log in zero times (FR-005, FR-006, SC-003).
