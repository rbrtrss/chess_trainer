# Contract: Lichess API

**Feature**: [spec.md](../spec.md) | **Research**: [research.md](../research.md) |
**Companion**: [library-api.md](./library-api.md)

The app's entire network surface. Everything here lives in `lib/data/lichess/`, which is the
**only** directory in `lib/` permitted to mention an HTTP client (D2, D14). `lib/domain/` and
`lib/ui/` never import it; the UI reaches it through `ImportService` and `ConnectionController`.

Endpoint facts below were verified against the Lichess OpenAPI spec on 2026-08-14 and are
tabulated in [research.md](../research.md#verified-lichess-api-facts).

```dart
// ------------------------------------------------------------------- the API

/// Every request this app makes. Four methods; there will not be a fifth
/// without a specification that argues for it.
///
/// Requests are serialised — one at a time, as Lichess asks (D6). Every method
/// is called only as the direct result of the player asking for something
/// (FR-015): nothing here may be invoked from a build method, a provider
/// initialiser, an app-start path, or a timer.
abstract interface class LichessApi {
  /// `GET /api/account` — the logged-in user's profile, for their username (D9).
  /// Any valid token; no particular scope.
  Future<String> username();

  /// `GET /api/study/by/{username}` — NDJSON, one study per line (FR-013).
  ///
  /// Includes private and unlisted studies when authenticated. A malformed line
  /// is skipped, not fatal: one bad row must not cost the player their list.
  Future<IList<StudySummary>> listStudies(String username);

  /// `GET /api/study/{studyId}.pgn?clocks=false&comments=true&variations=true`
  /// (FR-011, D7).
  ///
  /// Returns the whole study as one PGN of many games. Works unauthenticated
  /// for a public study; needs `study:read` for a private one.
  Future<String> exportStudy(String studyId);

  /// `DELETE /api/token` — revokes the token server-side (FR-022).
  ///
  /// Best effort: if the request fails, the local credential is deleted anyway.
  /// A player who asked to disconnect must end up disconnected on their own
  /// device regardless of what the network did.
  Future<void> revokeToken();
}

/// One row of the study list (D9).
@immutable
class StudySummary {
  final String id;       // exactly 8 characters
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}

// ----------------------------------------------------------------- the login

/// The OAuth 2.0 Authorization Code flow with PKCE (D3).
///
/// There is deliberately no `refresh()`. Lichess issues no refresh tokens, so a
/// refresh path cannot work, and a method that cannot work is worse than a
/// missing one — it invites a caller.
abstract interface class LichessAuth {
  /// Runs the full flow: verifier and state from `Random.secure()`, challenge
  /// as unpadded base64url of SHA-256, authorization in a Chrome Custom Tab,
  /// `state` checked on return, then the token exchange.
  ///
  /// Throws [LoginCancelledError] when the player backs out — which is a normal
  /// outcome, not an error to report as a failure.
  Future<LichessConnection> logIn();

  /// Revokes server-side, then deletes the local credential (FR-022).
  ///
  /// Imported collections are untouched: they are local content now, not a view
  /// onto the account.
  Future<void> logOut();

  /// The current connection, or null. Null **also** when the stored expiry has
  /// passed — an expired credential is deleted rather than reported (D5).
  Future<LichessConnection?> current();
}

/// Where the token lives, and the only thing that can read it.
///
/// `flutter_secure_storage`, plus `android:allowBackup="false"` so the
/// credential cannot leave the device inside a Google backup (FR-021, D4).
abstract interface class CredentialStore {
  Future<String?> readToken();
  Future<void> write({required String token, required DateTime expiresAt, required String username});
  Future<void> clear();
}

// --------------------------------------------------------------- study links

/// Extracts an 8-character study id from a study URL, a chapter URL, or a bare
/// id (D8).
///
/// Returns null for anything else — a game link, a profile, another site — so
/// the caller can say what kind of address was expected (US2, edge cases).
String? parseStudyId(String input);
```

## Error contract

Every one of these must produce a message naming what happened and what the player can do
(SC-011), and must leave no partial collection behind (FR-019).

| Error | Raised when | What the player is told |
|---|---|---|
| `NoConnectionError` | The device is offline, or the request timed out | Importing needs a connection; everything else still works |
| `NotLoggedInError` | A private study was requested without a credential | Offer to log in, then resume the import |
| `LoginExpiredError` | `401`, or the stored expiry has passed | Log in again. **No refresh is attempted** (FR-017, D5) |
| `LoginCancelledError` | The player dismissed the authorization page | Nothing — a cancelled login is not a failure |
| `RateLimitedError` | `429` | Try again in a minute. **No automatic retry** (FR-018, D6) |
| `StudyNotAvailableError` | `404`, or `403` for a study since made private | Not available to this account |
| `NotAStudyLinkError` | `parseStudyId` returned null | What kind of address was expected |
| `LichessUnavailableError` | `5xx`, or a malformed response | Lichess had a problem; try again later |

## Invariants the tests must enforce

Every one of these runs against a fake `http.Client` — no test in this repository makes a real
network request.

1. The PKCE flow sends `code_challenge_method=S256`, a `code_challenge` equal to unpadded
   base64url of SHA-256 of the verifier, and a verifier of 43–128 unreserved characters. (D3)
2. A `state` that does not match the one sent aborts the login and stores no token. (D3)
3. The token exchange posts `grant_type=authorization_code`, `code`, `code_verifier`,
   `redirect_uri` and `client_id`, form-encoded, and **no client secret**. (D3)
4. `expires_in` is turned into an absolute expiry; `current()` returns null and the credential is
   deleted once that time has passed, with no request made. (FR-017, D5)
5. A `401` on any authenticated request clears the credential and surfaces `LoginExpiredError`.
   **No code path anywhere attempts a refresh** — asserted by a source-level check that no file
   mentions `refresh_token`. (FR-017, D5)
6. A `429` surfaces `RateLimitedError` and issues **exactly one** request — no retry loop. (FR-018)
7. Requests are serialised: two concurrent calls do not produce two in-flight requests. (D6)
8. `exportStudy` sends `comments=true`, `variations=true` and `clocks=false`, and the study id is
   validated as 8 characters before any request is made. (D7, D8)
9. `parseStudyId` accepts a study URL, a chapter URL and a bare id, and rejects a game URL, a
   profile URL, a URL on another host, and an id of the wrong length. (D8)
10. `logOut` deletes the local credential even when the revocation request fails. (FR-022)
11. The token never appears in any exception message, log line, or `toString()` — asserted by
    feeding a sentinel token through every error path and searching the output. (FR-021)
12. **No request is made outside an explicit import or login.** The full training flow — setup,
    session, commit, review, resume, history, collection management — runs against a
    `LichessApi` whose every method fails the test if called. (FR-015, FR-016, SC-009)
13. No file under `lib/ui/` or `lib/domain/` imports `lib/data/lichess/`, and no file outside
    `lib/data/lichess/` mentions `package:http/` or `HttpClient`. (D14, Principle II and IV)
