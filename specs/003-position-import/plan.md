# Implementation Plan: Position Import

**Branch**: `003-position-import` | **Date**: 2026-08-14 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-position-import/spec.md`

## Summary

Content stops being three files in the asset bundle. The player imports PGN — from a file on the
device, or from a Lichess study fetched after logging in — into named collections, and picks
which collection a session draws from.

The approach rests on five decisions from [research.md](./research.md):

- **One parser, two sources.** A fetched study and a picked file become the same `String` and take
  the same path from there, through the parser feature 001 built and unit-tested (D7). The Lichess
  work is a fetch and a chapter split, exactly as 001's research predicted.
- **Withholding inverts from allowlist to bag.** `PositionMetadata` gains a header bag holding
  *every* header of the entry (D11). Unknown text is captured and withheld by default instead of
  dropped, because against arbitrary files a five-field allowlist is a rule that fails open the
  first time someone wants a sixth field at review.
- **An entry without `[FEN]` is rejected** (D10). The parser's old fallback to the standard
  starting position was safe for content we authored and is wrong for content we did not.
- **Network lives in one directory and is proven unused elsewhere** (D14). The release manifest
  now declares `INTERNET`, so 002's structural guarantee is gone; the replacement is a narrowed
  layering rule plus a test that drives the whole training flow against an API fake that fails
  the test if touched.
- **No refresh path is built, anywhere** (D5). Lichess issues no refresh tokens, so expiry is
  presented as logging in again — asserted by a source-level check that nothing mentions
  `refresh_token`.

## Technical Context

**Language/Version**: Dart 3.13.0 (bundled with Flutter 3.47.0)

**Primary Dependencies**: existing — `chessground` ^10.1.1, `dartchess` ^0.13.1,
`flutter_riverpod` ^3.0.3, `fast_immutable_collections` ^11.0.4, `drift` ^2.34.3,
`drift_flutter` ^0.3.1. New — `file_selector` ^1.1.0, `http` ^1.6.0, `flutter_web_auth_2` ^5.1.0,
`crypto` ^3.0.7, `flutter_secure_storage` ^11.0.0. Licences verified before adoption
(research, "Verified package facts"): BSD-3-Clause and MIT throughout, all GPL-3.0 compatible.

**Storage**: SQLite via Drift at `<app documents>/chess_trainer.sqlite`, schema v2 — three new
tables (`collections`, `positions`, `app_settings`) alongside the four from 002. The access token
lives in `flutter_secure_storage`, never in the database.

**Testing**: `flutter test`. Persistence against `NativeDatabase.memory()`; every Lichess request
against a fake `http.Client`; PGN extraction against real study fixtures committed under
`test/fixtures/`, as the constitution's testing floor requires. No test makes a real network
request.

**Target Platform**: Android (phone). Verified on a physical device over `adb`.

**Project Type**: Mobile app, single Flutter module.

**Performance Goals**: 100 positions imported in under 10 s with the UI responsive throughout
(SC-007); parsing runs off the UI isolate (D15). Training and review performance is untouched —
this feature adds nothing to those paths.

**Constraints**: Every path except import and login works offline (FR-016, SC-009). Network code
confined to `lib/data/lichess/` and unreachable from `lib/domain/` and `lib/ui/` (Principle II).
Domain layer keeps zero Flutter imports. The token never appears in a log, an exception message,
or a device backup (FR-021).

**Scale/Scope**: one user, one Lichess account, collections of up to 500 positions each (D16).
Roughly 4 new screens: collection list, import/report, study picker, and the session-setup change
that chooses a collection.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | How this design satisfies it |
|---|---|---|
| **I. Delayed feedback (non-negotiable)** | PASS | The barrier is unchanged — training still consumes only `TrainingProjection`, which gains no field (README's standing rule). What changes is the *volume* of evidence arriving: arbitrary titles, comments, NAGs, results and headers written by someone else. D11 makes withholding default-closed by capturing every header into a bag reachable only from `TrainingPosition`, which the training layer never holds. Three new guards: the hostile fixture in `no_feedback_guard_test.dart` (SC-003), the extended `lib/ui/training/` rule forbidding collections and provenance as well as grades, and an imported-vs-bundled screen comparison (SC-004). |
| **II. Offline-first** | PASS, with a guarantee downgraded | Requirements are met: network only on explicit request (FR-015), no screen blocks on it (FR-016), a failure degrades to "no new positions" (FR-020), training reads local storage alone (SC-009, SC-010), and the client sits behind repository interfaces in `lib/data/lichess/`, unreachable from domain and UI. What is lost is 002's stronger claim — a release build with no `INTERNET` permission. That is unavoidable once fetching is in scope, and the replacement is behavioural: see Complexity Tracking. |
| **III. Delegated chess correctness** | PASS | No new chess code. `parseTrainingPosition` and `PgnGame.parseMultiGamePgn` (dartchess) do the work; every move of every variation is replayed for legality, which is *why* import is a CPU-bound job worth an isolate (D15). Variant detection reads `[Variant]` rather than inferring anything. |
| **IV. Layering** | PASS | `lib/domain/` gains pure types (`Collection`, `CollectionOrigin`, `ImportOutcome`, `RejectedEntry`, `LichessConnection`) and stays Flutter-free and I/O-free. HTTP, OAuth and secure storage live in `lib/data/lichess/`; Drift stays in `lib/data/local/`. The UI sees `CollectionRepository`, `ImportService` and `ConnectionController` and never learns that either SQLite or `http` exists. |
| **V. Testing floor** | PASS, and it closes an open item | "Study PGN → training position extraction, against real fixture files" has been on the floor since ratification with nothing to cover it; this feature covers it. Everything already covered stays covered. New: the parsing and rejection suite, the full Lichess request suite against a fake client, the PKCE assertions, the no-request-during-training test, and the v2 migration. All device-free. The floor's puzzle ply-offset item stays uncovered because puzzles remain unbuilt. |
| **Licensing** | PASS | `file_selector`, `http`, `crypto`, `flutter_secure_storage` BSD-3-Clause; `flutter_web_auth_2` MIT. All GPL-3.0 compatible, checked on pub.dev before adoption as the constitution requires. |
| **No secrets** | PASS | The Lichess `client_id` is public by design and committed, which the constitution explicitly permits. There is no client secret — Lichess does not support one. The access token lives in `flutter_secure_storage`, is excluded from backups (D4), and is asserted absent from every error path and log line (contract invariant 11). |
| **Complexity justified** | PASS with two recorded judgements | The feature is large because the clarification put OAuth in scope. Both judgement calls — the manifest downgrade, and adding a login before a scheduler — are in Complexity Tracking. |

**Post-design re-check (after Phase 1)**: still PASS. The design added no dependency beyond the
five listed and no reachable path from domain or UI to the network. Two things sharpened during
design and are recorded rather than waved through: the metadata bag (D11), which changes an
existing domain type in order to make Principle I default-closed, and the loss of the manifest
guarantee (D14), which is a genuine reduction in assurance traded for a tested behavioural claim.

## Project Structure

### Documentation (this feature)

```text
specs/003-position-import/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — decisions D1–D16, verified API and package facts
├── data-model.md        # Phase 1 — entities, schema v2, import and login state machines
├── quickstart.md        # Phase 1 — how to build, run and validate
├── contracts/
│   ├── library-api.md   # Phase 1 — collections, parsing, import
│   └── lichess-api.md   # Phase 1 — the entire network surface
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 — created by /speckit-tasks, not here
```

### Source Code (repository root)

Additions and changes to the structure features 001 and 002 established.

```text
lib/
├── domain/                                  # pure Dart — no Flutter, no I/O
│   ├── position/
│   │   └── training_position.dart           # CHANGED — PositionMetadata gains `headers` (D11)
│   ├── library/
│   │   ├── collection.dart                  # NEW — Collection, CollectionOrigin
│   │   └── import_outcome.dart              # NEW — ImportOutcome, RejectedEntry, RejectionReason
│   └── lichess/
│       └── lichess_connection.dart          # NEW — username + expiry. NOT the token
├── data/
│   ├── pgn_position_parser.dart             # CHANGED — [FEN] required, variants rejected,
│   │                                        #   every header captured (D10, D11)
│   ├── import_parser.dart                   # NEW — multi-entry split, rejection collection
│   ├── collection_repository.dart           # NEW — the interface the UI codes against
│   ├── import_service.dart                  # NEW — the import state machine
│   ├── bundled_position_source.dart         # CHANGED — a seeder now, not the only source
│   ├── local/
│   │   ├── tables.dart                      # CHANGED — collections, positions, app_settings
│   │   ├── database.dart                    # CHANGED — schemaVersion 2, onUpgrade
│   │   └── drift_collection_repository.dart # NEW
│   └── lichess/                             # THE ONLY DIRECTORY THAT MAY TOUCH THE NETWORK
│       ├── lichess_api.dart                 # NEW — four requests, serialised (D2, D6)
│       ├── lichess_auth.dart                # NEW — PKCE. No refresh path exists (D3, D5)
│       ├── credential_store.dart            # NEW — flutter_secure_storage (D4)
│       └── study_link.dart                  # NEW — URL/id parsing (D8)
└── ui/
    ├── session/
    │   └── session_setup_screen.dart        # CHANGED — choose a collection (FR-029)
    ├── training/                            # UNCHANGED — and must stay content-blind
    └── library/
        ├── collection_list_screen.dart      # NEW — FR-034 to FR-039
        ├── import_screen.dart               # NEW — pick, progress, report
        ├── import_report_view.dart          # NEW — grouped rejections (D10)
        ├── study_picker_screen.dart         # NEW — the account's studies (FR-013)
        └── connection_controller.dart       # NEW — log in, log out, expiry

android/app/src/main/AndroidManifest.xml     # CHANGED — INTERNET, allowBackup=false,
                                             #   OAuth callback activity (D4, D14)

test/
├── data/
│   ├── import_test.dart                     # NEW — parsing, rejection reasons, the report
│   ├── collection_repository_test.dart      # NEW — round trip, atomic store, cascade
│   ├── lichess_api_test.dart                # NEW — every request, fake http.Client
│   ├── lichess_auth_test.dart               # NEW — PKCE, state, expiry, no refresh
│   ├── study_link_test.dart                 # NEW
│   └── migration_test.dart                  # CHANGED — v1 → v2
├── domain/
│   └── layering_test.dart                   # CHANGED — network rule narrowed, not deleted (D14)
├── fixtures/                                # NEW — real study exports, committed
└── ui/
    ├── no_feedback_guard_test.dart          # CHANGED — hostile imported fixture (SC-003)
    ├── no_network_during_training_test.dart # NEW — the behavioural offline guarantee (SC-009)
    ├── import_flow_test.dart                # NEW
    └── collection_list_test.dart            # NEW
```

**Structure Decision**: Unchanged from 001 and 002 — one Flutter module, the constitution's three
layers as top-level directories. The one structural novelty is `lib/data/lichess/`, which is
special not by convention but by test: it is the only directory permitted to mention an HTTP
client, and `layering_test.dart` enforces that in both directions.

## Implementation sequence

Ordered so the riskiest work is proven first and each step leaves the app runnable.

1. **Parser changes and the metadata bag** — `[FEN]` required, variants rejected, every header
   captured, multi-entry split with rejection collection. Tested against the committed study
   fixtures. *No UI, no network, no schema. Everything else rests on this, and it is where a real
   study first meets the app.*
2. **Schema v2 and the collection repository** — tables, migration, atomic store, cascade delete,
   sample seeding with its flag. Round-trip tests against an in-memory database, and the v1 → v2
   migration test using 002's harness.
3. **Principle I guards** — the hostile fixture, the extended `lib/ui/training/` rule, the
   imported-vs-bundled screen comparison. **Done before any import UI exists**, so the rule is in
   place before the temptation is. This is the same ordering 002 used and for the same reason.
4. **File import end to end** — picker, isolate parsing with progress, duplicate check, the
   report, the collection list, and choosing a collection at session setup. **First device
   checkpoint:** import a real study file and train on it. At this point User Stories 1, 3 and 4
   are delivered and the feature is independently useful with no network code written.
5. **The network guard, before the network** — narrow the layering rule and add
   `no_network_during_training_test.dart` against an API fake. Written now so that every line of
   step 6 lands against a rule that already exists.
6. **Lichess: fetch first, login second** — `study_link.dart`, `LichessApi`, and public-study
   import, all against a fake client. Then PKCE, the credential store, the manifest changes, the
   study picker, and expiry handling. **Second device checkpoint:** log in, import a private
   study, enable airplane mode, train it.
7. **Failure pass** — every row of the error contract, provoked deliberately: offline, 401, 429,
   404, cancelled login, revoked token, killed mid-fetch, storage full. Each must name what
   happened and leave nothing behind.
8. **End-to-end on device** — the quickstart scenarios, including the update from a 002 build and
   a full offline run.

Steps 1, 2, 3 and 5 need no device. Steps 1–4 need no network and no Lichess account, so the file
half of the feature can be finished and shipped even if the OAuth work stalls.

## Complexity Tracking

No constitution violations require justification. Two judgement calls are recorded for visibility.

| Decision | Why needed | Simpler alternative rejected because |
|---|---|---|
| The release build declares `INTERNET`, losing 002's structural offline guarantee | The clarification put Lichess fetching in scope; an app that fetches needs the permission | There is no alternative that keeps the guarantee and the feature. The mitigation is that the guarantee becomes tested rather than assumed (D14): a narrowed layering rule plus a test driving the whole training flow against an API fake that fails on contact. This is weaker, and saying so is the point of recording it |
| A login and OAuth arrive before any scheduling exists | The clarification chose private studies, which cannot be reached without an account | Public-only import needs no login and would have been half the work — offered explicitly at clarification and declined. Recorded so the cost is attributed to the decision that caused it rather than discovered later as scope creep |

## Known risks

- **Real studies will be rejected in bulk, and it will look like a bug.** Lichess omits `[FEN]`
  for a chapter starting from the standard position, so every "analyse this game" chapter fails
  the FR-003 rule. For some studies that is most of the file. The report has to group rejections
  by reason and explain the common one in the player's words, or the first import a real user
  tries will look broken (D10). This is the single most likely source of "the app doesn't work"
  after release.
- **Principle I's attack surface grows by an order of magnitude.** Until now every string that
  could reach a screen was written by us and reviewed. Now it is arbitrary text from a stranger's
  study, including headers nobody anticipated. The bag (D11) makes the default safe, but the
  guard test is only as good as its fixture: a field the hostile fixture does not fill is a field
  the test does not protect. Adding to that fixture must be routine, not an afterthought.
- **The offline guarantee is now a promise instead of a property.** A future change can reach for
  `http` from a widget and only a test will object. That test must never be weakened to make
  something else pass.
- **The token is the first secret this app has ever held.** Every previous feature could not leak
  a credential because there was none. The invariants — never in a log, never in an exception,
  never in a backup — are cheap to satisfy now and expensive to retrofit after the first `print`.
- **`allowBackup="false"` silently changes what a factory reset costs.** Sessions survive an app
  update, as required, but not a new phone. Nobody asked for that, and nobody will notice until it
  matters (D4).
- **Isolate transfer cost is unmeasured.** Sending parsed trees back from the parsing isolate
  copies them (D15). It should be fine at 500 positions and has not been measured; the fallback —
  send PGN strings and parse on arrival — is recorded so it is not rediscovered under pressure.
- **The old numbering in the repository is now wrong.** `lib/data/pgn_position_parser.dart` and
  the 001/002 research notes promise that "feature 004" imports Lichess studies. That is this
  feature. The comments need correcting during step 1, or they will mislead the next reader.
