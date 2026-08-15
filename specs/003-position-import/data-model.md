# Data Model: Position Import

**Feature**: 003-position-import | **Date**: 2026-08-14

What this feature adds to the model feature 002 left behind: content becomes a first-class stored
thing rather than three files in the asset bundle, and the app gains a credential for the first
time. Decisions referenced as **D*n*** are in [research.md](./research.md).

---

## Domain types

Pure Dart under `lib/domain/`. No Flutter, no I/O (Principle IV).

### `PositionMetadata` — changed

The one existing type this feature modifies. It keeps its five typed fields and gains a sixth
that changes what the type means (D11).

| Field | Type | Notes |
|---|---|---|
| `title` | `String?` | From `[Title]` or `[Event]`, as today |
| `goal` | `String?` | From `[Goal]` |
| `themes` | `IList<String>` | From `[Themes]`, comma-separated |
| `rating` | `int?` | From `[Rating]` |
| `source` | `String?` | From `[Source]` or `[Site]` |
| **`headers`** | **`IMap<String, String>`** | **NEW.** Every PGN header of the entry, verbatim, including the five above and every one the app does not recognise |

The typed fields are now a *view* over the bag, kept because review lays them out deliberately.
`headers` is what makes FR-025 true: withholding stops being a list someone maintains and becomes
a property of where the data can be reached from. Nothing in this type is reachable from
`TrainingProjection`, and nothing is added to `TrainingProjection` — that remains the rule the
README states and the whole design leans on.

**Validation**: header keys are trimmed and non-empty; values are stored as written, including
`?`, which PGN uses for "unknown". The typed accessors keep skipping `?`; the bag does not,
because a review that shows `[Date "?"]` is honest about what the file said.

### `Collection` — new

A named group of positions from one import.

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Generated, stable |
| `name` | `String` | Player-supplied, not unique (FR-009), renamable (FR-035) |
| `origin` | `CollectionOrigin` | Where it came from — see below |
| `importedAt` | `DateTime` | UTC |
| `positionCount` | `int` | Denormalised for the list (FR-034) |

### `CollectionOrigin` — new

A sealed hierarchy, not a string, because the three cases carry different data and the UI shows
them differently:

- `BundledOrigin` — the samples seeded on first run (FR-033).
- `FileOrigin(fileName)` — the name of the picked file. **Withheld from training screens exactly
  like a title** (FR-026): `mate-in-3.pgn` is as much a hint as "Chapter 3: Winning the
  Opposition".
- `LichessOrigin(studyId, studyName, fetchedAt)` — enough to identify what was imported and to
  offer "import again" later.

### `ImportOutcome` and `RejectedEntry` — new

What one import produced (FR-007). This is a domain type, not a UI model, because the rejection
rules are domain rules and are unit-tested as such.

| `ImportOutcome` | Type | Notes |
|---|---|---|
| `positions` | `IList<TrainingPosition>` | The usable entries |
| `rejections` | `IList<RejectedEntry>` | Everything else |

| `RejectedEntry` | Type | Notes |
|---|---|---|
| `reference` | `String` | How the player finds it: the chapter's `[Event]`/`[Title]`, else its ordinal ("entry 7 of 12") |
| `reason` | `RejectionReason` | Enum: `noStartingPosition`, `noMoves`, `illegalMove`, `unsupportedVariant`, `unparseable` |
| `detail` | `String?` | The parser's message, for the ones where it helps |

`RejectionReason` is an enum rather than free text so the report can group ("9 chapters start from
the standard position and cannot be trained") instead of printing nine near-identical lines. For
a real study this is the difference between a usable report and a wall (D10).

### `LichessConnection` — new

| Field | Type | Notes |
|---|---|---|
| `username` | `String` | Cached so listing studies needs one round trip (D9) |
| `expiresAt` | `DateTime` | Absolute, computed from `expires_in` at login (D5) |

**The token is deliberately not a field on this type.** It lives only inside
`lib/data/lichess/`, behind the credential store, so no domain or UI value can hold it, log it,
or put it in an error message. What the UI needs to know is "connected as *whom*, until *when*",
and that is all this type carries.

### Unchanged

`TrainingPosition`, `TrainingProjection`, `VariationTree`, `MoveNode`, `MovePath`, `Attempt`,
`Grade`, `SessionRecord`. `TrainingPosition.id` changes meaning slightly — it was the bundled
asset's basename, and is now a generated id unique across collections — but not shape.

---

## Stored schema (v2)

`schemaVersion` moves from 1 to 2. The four tables from 002 are untouched. Three are added.

### `collections`

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `name` | text | Not unique (FR-009) |
| `origin_kind` | text | `bundled` / `file` / `lichess` |
| `origin_ref` | text, null | File name, or study id |
| `origin_label` | text, null | Study name at fetch time |
| `imported_at` | integer | UTC epoch ms |
| `content_hash` | text | SHA-256 of the source text, for duplicate detection (D13) |

Indexed on `content_hash` — it is only ever looked up by equality, once per import.

### `positions`

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `collection_id` | text | FK → `collections.id`, `ON DELETE CASCADE` |
| `ordinal` | integer | Order within the collection, as the source had it |
| `initial_fen` | text | The entry's `[FEN]`. Never null — an entry without one is rejected (D10) |
| `solution_pgn` | text | The whole tree, comments and NAGs included, via the codec from 001 (D7) |
| `metadata_json` | text | The typed fields *and* the header bag (D11) |

Indexed on `collection_id`.

**The cascade is the point of the design.** Deleting a collection deletes its positions and
nothing else, because `session_positions.position_id` is plain text with no foreign key — 002
froze each session's own copy of what it showed. FR-037 therefore needs no code: a past review
reads its own snapshot and never asks whether the position still exists (D12).

### `app_settings`

| Column | Type | Notes |
|---|---|---|
| `key` | text, PK | |
| `value` | text | |

One key in this feature: `samples_seeded` = `"true"`. It exists so deleting the bundled
collection is permanent (FR-033). Seeding "when the collection table is empty" would resurrect
the samples for a player who had deliberately cleared everything — an app arguing with its user.

### Migration v1 → v2

`onUpgrade` creates the three tables and seeds the samples. Nothing in v1 is altered, so the
migration cannot damage stored sessions — the property the migration test asserts, using the
harness and `drift_schemas/` snapshots that 002 built for exactly this moment. A fresh install
runs `onCreate` and seeds the same way, so both paths end in the same state, and the test says so.

---

## Import: states and transitions

One import moves through these states. It matters because most of them can fail and each failure
has a required message (FR-007, FR-020, SC-011).

```text
                 ┌──────────────┐
                 │  Choosing    │  pick a file, paste a URL, or select a study
                 └──────┬───────┘
                        │
              ┌─────────▼─────────┐
              │    Acquiring      │  read the file, or fetch from Lichess
              └─────────┬─────────┘
                        │ ── offline / 401 / 429 / 404 / too large ──► Failed
              ┌─────────▼─────────┐
              │     Parsing       │  off the UI isolate (D15), determinate progress
              └─────────┬─────────┘
                        │ ── nothing usable ──► Failed
              ┌─────────▼─────────┐
              │    Confirming     │  duplicate warning, if the hash matches (D13)
              └─────────┬─────────┘
                        │ ── player declines ──► Cancelled
              ┌─────────▼─────────┐
              │     Storing       │  ONE transaction: collection + all positions
              └─────────┬─────────┘
                        │ ── storage failure ──► Failed
                 ┌──────▼───────┐
                 │   Reported   │  n added, m rejected and why
                 └──────────────┘
```

**Failed and Cancelled leave nothing behind.** Storing is a single transaction (FR-019, FR-041):
a collection row and its positions commit together or not at all, so an interrupted import cannot
produce a collection that is half a study. This is the same atomicity rule 002 applied to
committing an attempt, for the same reason — a partial write here would be invisible until the
player wondered why a study had lost its last four chapters.

**Parsing never fails as a whole because one entry is bad.** Rejections accumulate; the outcome
carries both lists (FR-007). The only "nothing usable" failure is an empty `positions` list,
which is reported as a failure with the reasons attached rather than as an empty collection.

## Login: states and transitions

```text
   Disconnected ──login──► Authorizing ──code──► Exchanging ──token──► Connected
        ▲                       │                    │                    │
        │                       │ cancelled          │ error              │ 401, or expiry passed
        └───────────────────────┴────────────────────┴────────────────────┘
```

There is no `Refreshing` state, and adding one later would be adding a state that cannot be
reached: Lichess issues no refresh tokens (D5). Every edge back to `Disconnected` deletes the
stored credential, so the app never holds a token it believes to be dead.

---

## Relationships

```text
Collection 1 ──< Position                    cascade delete
Collection 1 ──< (nothing else)              sessions do not reference collections

Session    1 ──< SessionPosition             frozen copy, from 002 — no FK to Position
Session    1 ──< Attempt
Session    1 ──< Grade

LichessConnection 0..1                       at most one account, in secure storage
```

The absence of an edge from `Session` to `Collection` is the load-bearing part. It is why
deleting a collection cannot corrupt history, why an app update that changes the bundled samples
cannot rewrite a played session, and why this feature adds no new way for stored content to
reach a training screen.

## Not modelled here

- **Position history across sessions.** Unchanged from 002 and unchanged in reason: the grades
  exist, nothing aggregates them, and nothing may display them during training.
- **Chapter identity within a study.** A chapter becomes a position with an ordinal; it does not
  keep a chapter id. Re-import creates a new collection (D13), so there is nothing to match
  against.
- **Sync state.** No "last checked", no "update available". A collection is a copy taken once.
- **Tags, folders, search.** Out of scope in the spec, and each would need a rule about whether
  its labels are evidence. They are.
