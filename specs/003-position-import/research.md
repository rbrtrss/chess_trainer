# Phase 0 Research: Position Import

**Feature**: 003-position-import | **Date**: 2026-08-14 | **Spec**: [spec.md](./spec.md)

Decisions D1–D16, then the facts they rest on. Every fact in "Verified facts" was checked
against a primary source on 2026-08-14 rather than recalled, because three of them (token
lifetime, absence of refresh tokens, and what a study export actually contains) decide the shape
of the design and would be expensive to discover during implementation.

---

## D1: Files arrive through `file_selector`, not `file_picker`

**Decision**: Add `file_selector` ^1.1.0 (BSD-3-Clause, published by flutter.dev) and open PGN
through `openFile()`.

**Rationale**: It is the narrowest thing that does the job. On Android it goes through the
Storage Access Framework, which grants access to the one file the player picked, so the app
needs no storage permission at all — a real reduction in what the app can reach, which matters
for an app whose whole pitch is that it does not go looking at things. It is published by the
Flutter team under a licence already used throughout this project.

**Alternatives considered**: `file_picker` (MIT, ^12.0.0) is more popular and offers caching,
multi-select and directory picking — none of which this feature wants, all of which are surface
that has to keep working. Receiving files through Android's share sheet was rejected as an
addition rather than an alternative: it is a second entry path to build and test, and the player
who wants it can still pick the file.

**Trap**: PGN has no MIME type Android reliably recognises. `application/x-chess-pgn` is what
Lichess serves, but Android's document picker filters on what the *provider* claims, and Drive,
Downloads and most file managers report `application/octet-stream` or `text/plain` for a `.pgn`.
Filtering strictly makes the player's own file invisible in the picker with no explanation. So
the picker accepts any file, and the *content* is validated — which is the check that has to
exist anyway, since a file named `.pgn` proves nothing.

## D2: One HTTP client, `http`, confined to `lib/data/lichess/`

**Decision**: Add `http` ^1.6.0 (BSD-3-Clause, dart.dev). All of it lives behind
`LichessApi` in `lib/data/lichess/`, which is the only directory in `lib/` permitted to mention
it (D14).

**Rationale**: The feature makes at most four kinds of request — token exchange, token
revocation, list studies, export study. That is a job for the standard client, not for a
framework. `dio`'s interceptors, transformers and retry policies would be more code to reason
about than the requests themselves.

**Alternatives considered**: `dio` (MIT) — rejected as disproportionate. `dart:io`'s
`HttpClient` directly — rejected because it would make the layering rule in D14 harder to write:
"no `dart:io` outside `lib/data/lichess/`" is a weaker rule than one naming a package, since
`dart:io` has many innocent uses.

## D3: OAuth is Authorization Code + PKCE, through `flutter_web_auth_2`

**Decision**: Add `flutter_web_auth_2` ^5.1.0 (MIT) and `crypto` ^3.0.7 (BSD-3-Clause). The flow
is exactly the one Lichess documents:

1. Generate `code_verifier` (43–128 unreserved characters) and `state`, both from
   `Random.secure()`.
2. `code_challenge = base64url(sha256(code_verifier))`, unpadded. `code_challenge_method=S256`
   is the only method Lichess accepts.
3. Open `https://lichess.org/oauth` with `response_type=code`, `client_id`, `redirect_uri`,
   `code_challenge`, `code_challenge_method`, `scope=study:read`, `state`.
4. On return, check `state` matches, then `POST https://lichess.org/api/token`, form-encoded,
   with `grant_type=authorization_code`, `code`, `code_verifier`, `redirect_uri`, `client_id`.
5. Store the `access_token` and the absolute expiry computed from `expires_in`.

**Rationale**: `flutter_web_auth_2` contributes exactly the two things that are annoying to
build: a Chrome Custom Tab (so the player sees the real Lichess address bar and can use their
password manager — an embedded WebView would be both worse security and against Google's
policy), and an Android activity registered for the callback scheme that hands the redirect URL
back to Dart as a `Future`. Everything else — the verifier, the challenge, the state check, the
token exchange — is fifty lines we write ourselves against `http` and `crypto`, and writing them
keeps the security-relevant part legible rather than delegated.

**Alternatives considered**: `url_launcher` + `app_links` — the same result from two packages
plus a callback stream and its lifecycle, with more ways to lose the redirect. The `oauth2`
package (BSD-3-Clause, dart.dev) — a full client-credential-aware library whose main service is
the token refresh this API does not have.

**Client id**: an arbitrary public string; Lichess registers nothing in advance. Use a stable
URL identifying the project. It is public by design and the constitution explicitly permits
committing it. The redirect URI is a custom scheme, `org.chesstrainer://oauth/callback`,
declared in the Android manifest.

## D4: The token lives in `flutter_secure_storage`, and backups are turned off

**Decision**: Add `flutter_secure_storage` ^10.3.1 (BSD-3-Clause; see the correction under
"Verified package facts" — 11.0.0 cannot build on this toolchain), storing the access token, its
expiry and the account's username under one key each. Set `android:allowBackup="false"` and
`android:dataExtractionRules` on `<application>`.

**Rationale**: The constitution requires tokens in `flutter_secure_storage`; that part is not a
choice. The backup setting is: FR-021 says the credential must not be carried into device
backups, and on Android the plugin's data is ordinary app storage as far as Auto Backup is
concerned. Without `allowBackup="false"`, a token can leave the device inside a Google backup,
which is precisely the movement FR-021 forbids.

**Consequence, recorded deliberately**: this also stops the training database being backed up. No
requirement is lost — FR-040 asks that data survive the app being *closed and updated*, which is
unaffected — but a player who factory-resets their phone loses their session history. That is
the honest trade, and it is the reason this is in research rather than buried in a manifest.

## D5: Expiry is a re-login, and there is no code path that pretends otherwise

**Decision**: Store the absolute expiry alongside the token. Before any authenticated request,
if the expiry has passed, delete the credential and ask the player to log in. On a `401` from
any request, do the same. There is **no** refresh-token code, no silent retry, and no
`refreshToken()` method anywhere in the interface.

**Rationale**: Lichess issues tokens lasting about a year and does not support refresh tokens —
verified below, and stated as a hard fact in the constitution's Technology Constraints. A
refresh path cannot be made to work, so the only question is whether the failure is honest or
mysterious. Checking expiry locally as well as reacting to `401` means the common case (a token
that quietly aged out) becomes an invitation rather than a request that fails for reasons the
player cannot see.

## D6: Rate limiting is respected by not retrying

**Decision**: One request at a time, serialised inside `LichessApi`. On `429`, no automatic
retry: report "Lichess is rate-limiting this app — try again in a minute" and stop. Retrying is
the player's explicit action.

**Rationale**: Lichess's own guidance is "only make one request at a time" and "waiting one
minute before retrying will be sufficient, but some limits may require longer". An automatic
backoff loop turns a one-minute wait into an app that appears to hang, and a client that retries
on its own is how an app gets its rate limit tightened. Since every request in this feature is
already the direct result of a player tapping something (FR-015), handing the retry back to them
costs nothing and keeps the request count honest.

## D7: A study is fetched as one PGN and split by the existing parser

**Decision**: `GET /api/study/{studyId}.pgn?clocks=false&comments=true&variations=true`, then
`PgnGame.parseMultiGamePgn` (dartchess) to split chapters, then the *existing*
`parseTrainingPosition` on each.

**Rationale**: This is the reuse feature 001 was designed around — its research says so
explicitly, and `pgn_position_parser.dart` says it in a comment. The fetched bytes and a picked
file become the same `String` and take the same path from there, so there is one parser, one set
of rejection rules, and one place where Principle I's withholding is enforced. It also means the
Lichess path inherits every parser test already written.

**Parameters, chosen not defaulted**: `variations=true` and `comments=true` because the
variations *are* the solution and the comments *are* the author's notes — a study exported
without them is worthless here. `clocks=false` because clock annotations would land in the same
comment text as the author's prose and be shown at review as if they were notes.

## D8: A study is identified by an 8-character id parsed out of whatever the player pastes

**Decision**: Accept a full study URL, a chapter URL, or a bare id. Extract with a regex anchored
on `lichess.org/study/`, validate the id as exactly 8 characters of `[A-Za-z0-9]`, and reject
anything else — a game URL, a profile, a different site — with a message naming what was
expected.

**Rationale**: The OpenAPI spec pins the study id at `minLength: 8, maxLength: 8`, so the check
is exact rather than a guess. A chapter URL (`/study/{studyId}/{chapterId}`) is a natural thing
to paste; taking the study id from it and importing the whole study is more useful than an
error, and the player sees what came in either way.

## D9: The player's own studies are listed via `/api/account` then `/api/study/by/{username}`

**Decision**: After login, `GET /api/account` (any valid token, no scope needed) for the
username, then `GET /api/study/by/{username}` — NDJSON, one `{id, name, createdAt, updatedAt}`
per line — for the list to choose from. Store the username with the credential so listing does
not need two round trips every time.

**Rationale**: There is no "my studies" endpoint that infers the user; the listing endpoint is
by username. Both endpoints include private studies when authenticated, which is the whole point
of FR-012 and FR-013.

**NDJSON note**: the response is a stream of lines, not a JSON array. It is parsed line by line
and a malformed line is skipped rather than failing the listing, because one bad row must not
cost the player their whole study list.

## D10: An entry with no `[FEN]` is now rejected, which changes the parser

**Decision**: `parseTrainingPosition` stops falling back to the standard initial position when
`[FEN]` is absent and throws `PositionParseError` instead. Non-standard `[Variant]` values are
rejected the same way.

**Rationale**: FR-003 and the clarification. The fallback made sense when every position was one
we authored and had reviewed; against arbitrary imports it silently turns "a game record" into
"a position starting from move 1", which is not a calculation exercise and cannot be graded. All
three bundled PGNs carry an explicit `[FEN]`, so nothing already in the app changes behaviour.

**Consequence for real studies, stated plainly**: Lichess omits `[FEN]` for a chapter that starts
from the standard position, so any "let's analyse this game" chapter will be rejected. That is
correct under the clarification, and it makes FR-007's "which entries were rejected and why"
load-bearing rather than a nicety: for some studies the report will be most of the chapters, and
the player has to be able to see why at a glance.

## D11: Metadata becomes a bag of everything, not a list of fields

**Decision**: `PositionMetadata` keeps its five typed fields and gains
`headers: IMap<String, String>` holding **every** PGN header of the entry, verbatim. The typed
fields become conveniences for review's layout; the bag is what guarantees the withholding.

**Rationale**: FR-025 requires unrecognised content to be withheld *by default*, and the current
design cannot do that — it names five fields and drops everything else on the floor. Dropping is
safe for Principle I but wrong for review (the author's `[Annotator]` or `[Opening]` is worth
reading), and the moment someone adds a sixth field to satisfy a review request, the default
flips back to allow-by-omission. A bag inverts it: everything the file carried is captured,
everything captured is withheld during training because `TrainingProjection` has no path to it,
and review renders the bag.

**What does not change**: `TrainingProjection` gains nothing. The README's rule — "do not add a
field to that type" — is exactly the rule that makes this safe, because the bag can only be
reached from something that holds a `TrainingPosition`, and the training layer never has one.

## D12: Schema v2 adds collections and positions; the samples are seeded once

**Decision**: `schemaVersion` goes to 2. Two new tables, `collections` and `positions`, plus a
one-row-per-key `app_settings` table. Migration `onUpgrade` creates them; the bundled samples are
inserted as an ordinary collection on first run, guarded by a `samples_seeded` key in
`app_settings`.

**Rationale**: FR-033 needs seeding to happen once and *stay* undone after a delete. A "seed if
the collection table is empty" rule would resurrect the samples the moment a player deleted
everything — a bug that looks like the app second-guessing them. A flag is one row and says what
it means.

**Why sessions need no migration**: `session_positions.position_id` is plain text with no foreign
key, deliberately, because 002 froze each session's own copy of what it showed. Deleting a
collection therefore cannot touch history, and FR-037 is satisfied by a decision already made
rather than by new work. This is worth stating because it looks like an oversight in the 002
schema and is not.

## D13: Duplicate detection is a content hash on the collection

**Decision**: Store `content_hash` = SHA-256 of the source text on each collection. On import,
hash first, warn if a collection with that hash exists, and let the player proceed (FR-010).

**Rationale**: It is exact, cheap, and needs no new dependency — `crypto` is already in for PKCE
(D3). It answers the question actually being asked ("have I already imported *this*?") rather
than a proxy like the file name or the study id, and it catches the case that actually happens:
the same study exported twice under different names.

## D14: The network guard changes from "impossible" to "confined", and the difference is tested

**Decision**: Three changes, together:

1. The release manifest declares `android.permission.INTERNET`. It has to; the app now uses the
   network.
2. `layering_test.dart`'s rule "nothing in the app opens a network connection" is **narrowed** to
   "nothing outside `lib/data/lichess/` mentions `package:http/`, `dart:io` sockets, or
   `HttpClient`" — and gains a companion rule that `lib/ui/` and `lib/domain/` never import
   `lib/data/lichess/` directly.
3. A new widget test drives the whole training flow — setup, session, commit, review, resume,
   history — against a `LichessApi` fake whose every method fails the test if called. This is
   what FR-015 and SC-009 actually assert: not that the app *cannot* reach the network, but that
   it *does not*, except when the player asked.

**Rationale**: 002 could guarantee offline behaviour by making the shipped app incapable of
networking, and its plan said so proudly. That guarantee is genuinely gone and cannot be
recovered; pretending otherwise by leaving a stale test in place would be worse than losing it.
Point 3 is the honest replacement: a behavioural assertion instead of a structural one. It is
strictly more work and strictly weaker, and it is the correct consequence of the clarification
that put Lichess in scope.

## D15: Parsing runs off the UI isolate

**Decision**: Parse imports inside `Isolate.run` (via `compute`), returning parsed positions and
rejection reports to the main isolate.

**Rationale**: SC-007 allows ten seconds for a hundred positions but requires the app to stay
responsive throughout, and parsing a large study is CPU-bound pure Dart — every move of every
variation is replayed for legality (Principle III, via dartchess). On the main isolate that is
dropped frames for the duration. The parser is already pure and has no Flutter or plugin
dependency, so it is isolate-safe as written; the boundary types (PGN in, positions and
rejections out) are plain data.

**Trap**: `Position` and `VariationTree` cross the isolate boundary. Under Dart's send rules
these are copied, not shared, which is fine but is a real cost for a large study. If it measures
badly, the fix is to send PGN strings back and parse once on arrival — recorded here so the
option is not rediscovered under time pressure.

## D16: Imports are capped, and the cap is stated

**Decision**: Refuse a source larger than 5 MB or containing more than 500 entries, naming the
limit in the message. Show determinate progress ("47 of 300") while parsing.

**Rationale**: The spec's edge case requires either completion without apparent hang or a refusal
with a stated limit. A cap is the only one of the two that is testable in a bounded time. The
numbers are chosen against reality rather than intuition: a large Lichess study exports at a few
hundred kilobytes, so 5 MB refuses only PGN databases, which are not what this feature is for.

---

## Verified Lichess API facts

Checked 2026-08-14 against `lichess-org/api` `doc/specs` on `master` (the source the published
reference is generated from).

| Fact | Value | Why it matters here |
|---|---|---|
| Authorization endpoint | `GET https://lichess.org/oauth` | D3 |
| Token endpoint | `POST https://lichess.org/api/token`, form-encoded | D3 |
| Revocation | `DELETE https://lichess.org/api/token`, token as Bearer | FR-022 |
| Client authentication | None. Public clients, no secret, `client_id` is an arbitrary identifier | D3 |
| Code challenge method | `S256` only | D3 |
| Token lifetime | `expires_in: 31536000` — about a year | D5 |
| Refresh tokens | **Not supported.** Stated outright in the spec's overview | D5 |
| Token format | `^[A-Za-z0-9_]+$`, handle at least 512 characters | Column width, D4 |
| Scope for private studies | `study:read` | D3 |
| Export all chapters | `GET /api/study/{studyId}.pgn`, params `clocks`, `comments`, `variations`, `orientation` (all default true except `orientation`) | D7 |
| Private study access | "If authenticated, then all public, unlisted, and private study chapters are read" | FR-011, FR-012 |
| Study id shape | Exactly 8 characters | D8 |
| List a user's studies | `GET /api/study/by/{username}`, NDJSON of `{id, name, createdAt, updatedAt}` | D9 |
| Own profile | `GET /api/account`, valid token, no particular scope | D9 |
| Rate limiting | "Only make one request at a time"; `429` means back off, usually one minute, sometimes longer | D6 |

## Verified package facts

Latest versions and licences read from pub.dev on 2026-08-14. Every one is GPL-3.0 compatible,
checked before adoption as the constitution requires.

| Package | Version | Licence | Role |
|---|---|---|---|
| `file_selector` | 1.1.0 | BSD-3-Clause | Pick a PGN through the Storage Access Framework (D1) |
| `http` | 1.6.0 | BSD-3-Clause | The only HTTP client, confined to `lib/data/lichess/` (D2) |
| `flutter_web_auth_2` | 5.1.0 | MIT | Custom Tab and callback activity for the OAuth redirect (D3) |
| `crypto` | 3.0.7 | BSD-3-Clause | SHA-256 for the PKCE challenge (D3) and the duplicate hash (D13) |
| `flutter_secure_storage` | 10.3.1 | BSD-3-Clause | The access token (D4) |

Rejected after checking: `file_picker` 12.0.0 (MIT) — larger surface than needed (D1); `dio`
(MIT) — disproportionate (D2); `app_links` 7.2.1 — only needed if `flutter_web_auth_2` is not
used (D3); `oauth2` (BSD-3-Clause) — built around refresh, which this API does not have (D3).

**Corrected during implementation.** `flutter_secure_storage` 11.0.0 was the latest when this
table was written, and it does not build on this toolchain: it sets `compileSdk = 37`, and the
Android SDK manager publishes no plain `platforms;android-37` — only minor-versioned
`android-37.0`, `37.1`, and so on — so Gradle cannot resolve the platform hash and
`flutter build apk` fails on the plugin. 10.3.1 uses `compileSdk 36`, which is installed, has
the same API surface, and builds. Pinned there, with the reason recorded in `pubspec.yaml` so
the next person to see "11.0.0 available" knows why it was not taken.

## What this feature does *not* research

- **Puzzle import.** The constitution's warning about the puzzle ply offset (a puzzle's FEN is
  the position *before* the opponent's setup move) is real and expensive to get wrong, and it is
  irrelevant here: studies carry no such offset. Puzzles are out of scope, so the trap is left
  documented and unbuilt.
- **Keeping a collection in step with a study that changes upstream.** Out of scope by
  assumption; D13's content hash gives a later feature the hook it would need.
- **Scheduling.** Unchanged, and still the feature that has to argue for showing grade history.
