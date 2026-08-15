# Phase 1 Data Model: Lichess Login on the Home Screen

**Feature**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

## The short version

**The database does not change.** Schema stays at v2, no migration, no new table, no new column
(research D12). Every feature since 001 has moved the schema, so the absence of a migration here
is worth stating rather than leaving to be noticed.

What changes is one domain type, one storage operation, and which layer answers the question
"is an account connected".

---

## Entities

### `LichessAccount` — new, `lib/domain/lichess/account.dart`

A sealed type with three cases. Replaces the `LichessConnection?` that the UI has been reading,
because `null` was doing the work of two different answers (research D2).

| Case | Carries | Means |
|---|---|---|
| `AccountDisconnected` | nothing | No credential is stored. Either the player never logged in, or they disconnected. |
| `AccountConnected` | `LichessConnection` | A credential is stored and its expiry has not passed. |
| `AccountExpired` | `LichessConnection` | A credential was stored, its expiry has passed, and the token has been deleted. The username and date survive so the app can say whose login expired (research D3). |

Pure Dart, no Flutter, no I/O — it is a domain type and `layering_test.dart` holds it to that.

`LichessConnection` itself is unchanged: `username`, `expiresAt`, `isExpiredAt`, and
deliberately no token.

### `LichessConnection` — unchanged, `lib/domain/lichess/lichess_connection.dart`

Kept exactly as feature 003 left it. It is now carried by two of the three account cases rather
than being the whole answer.

---

## Stored state

### Secure storage — same three keys, one new operation

`flutter_secure_storage`, unchanged keys:

| Key | Holds |
|---|---|
| `lichess_access_token` | the access token — readable only from `lib/data/lichess/` |
| `lichess_token_expires_at` | absolute expiry, ISO-8601 UTC |
| `lichess_username` | the account name |

`CredentialStore` gains one method:

```
Future<void> expireToken();   // deletes the token, keeps username and expiry
```

`clear()` keeps its existing meaning — delete all three — and remains what disconnecting does.

The invariant this preserves is feature 003's D5, stated there as "the app never holds a token it
knows is dead". After `expireToken()`, `readToken()` returns `null`, so no request that is
certain to fail can be made; what survives is a name and a date, which grant nothing.

### The database

Untouched. Collections, positions, sessions and settings are exactly as feature 003 left them,
and disconnecting continues not to touch any of them (FR-011).

---

## State transitions

```text
                    ┌──────────────────────┐
                    │   AccountDisconnected │◄──────────────┐
                    └───────────┬──────────┘               │
                                │                          │
                  player taps Connect                      │
                  and completes the login          player taps Disconnect
                                │                  (clear(): all three keys)
                                ▼                          │
                    ┌──────────────────────┐               │
          ┌────────►│    AccountConnected   ├───────────────┤
          │         └───────────┬──────────┘               │
          │                     │                          │
   player logs in       expiry passes, observed             │
   again from the       on the next read                    │
   expired state        (expireToken(): token only)         │
          │                     ▼                          │
          │         ┌──────────────────────┐               │
          └─────────┤     AccountExpired    ├───────────────┘
                    └──────────────────────┘
```

Notes on the edges:

- **There is no refresh edge, and there must never be one.** Lichess issues no refresh tokens
  (constitution, Lichess API constraint 1; 003 research D5). `AccountExpired → AccountConnected`
  runs through the same login as a first connection.
- **Expiry is observed, not scheduled.** No timer watches the date. The transition happens on the
  next read of account state, which in practice is the next launch. A session running when the
  date passes is unaffected, because sessions read local content only.
- **A revoked or deleted account is not a state.** The app cannot know without asking, and it
  does not ask (spec, Assumptions). Such an account reads as `AccountConnected` until an import
  fails, which then reports the failure in 003's terms.
- **Disconnect is available from both `AccountConnected` and `AccountExpired`.** A player who
  does not want to log in again needs a way to clear the expired notice.

---

## Who may read what

| Reader | Sees | Must not see |
|---|---|---|
| `lib/domain/` | `LichessAccount`, `LichessConnection` | the token, the store, the network |
| `lib/data/lichess/` | everything, including the token | — |
| `lib/ui/library/connection_controller.dart` | the store and the auth object, to build providers | — |
| every other file in `lib/ui/` | `LichessAccount` through `lichessAccountProvider` | `lib/data/lichess/` |
| `lib/ui/training/` | **nothing about the account** (FR-020, research D11) | all of it |

The last row is enforced by `layering_test.dart`, which gains the account identifiers to its
forbidden list for the training directory.

---

## What is deliberately not modelled

- **A "last checked" timestamp.** Nothing checks, so there is nothing to stamp.
- **A dismissal flag for the expired notice.** Disconnecting clears it, and that is the
  disposal path.
- **More than one account.** One at a time; switching is disconnect then connect.
- **Anything about the Lichess profile.** Only the name, and only so the player knows which
  account is in use.
