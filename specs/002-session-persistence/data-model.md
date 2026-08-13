# Data Model: Session Persistence

**Date**: 2026-08-12 | **Feature**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

Two layers are described here and should not be confused. The **domain types** are pure Dart
values in `lib/domain/`, unchanged in spirit from feature 001. The **stored schema** is the
Drift table layout in `lib/data/local/`, which nothing outside that directory knows about.

---

## Domain types

### SessionRecord

A session that has been persisted. This is what the history list is made of.

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Stable identifier for the session. |
| `startedAt` | `DateTime` | When the session began. |
| `endedAt` | `DateTime?` | Null while in progress. |
| `status` | `SessionStatus` | `inProgress`, `complete`, `abandoned`. |
| `positionIds` | `IList<String>` | In session order. |

`SessionStatus` deliberately omits `setup`, `training` and `review`: those are phases of a
*live* `TrainingSession`, and are not worth persisting. What survives a restart is "this
session is unfinished", not which screen was open.

### Grade

Unchanged from feature 001 in shape: `positionId` and a `GradeValue` of `failed`, `hard`,
`good` or `easy`. What this feature adds is that a grade is stored against the session that
gave it, and that a session holds **exactly one grade per position** — re-grading from a past
review overwrites it (FR-017).

Nothing aggregates grades across sessions. A cross-session view of a position was removed from
this feature by clarification; the scheduling feature will add both the aggregation and its
display, and the grades stored here are what it will read.

### Unchanged from feature 001

`VariationTree`, `MoveNode`, `MovePath`, `TrainingPosition`, `PositionMetadata`,
`TrainingProjection`, `Attempt`, `ComparisonResult`, `TrainingSession`. This feature
adds storage around them and changes none of them.

**`TrainingProjection` in particular gains nothing.** It is why resumption needs no new leak
barrier (research D5), and it must stay that way.

---

## Stored schema

Drift tables. Times are stored as UTC; display converts to local (spec assumption).

### `sessions`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT, PK | |
| `started_at` | INTEGER | UTC epoch. |
| `ended_at` | INTEGER? | Null while in progress. |
| `status` | TEXT | `in_progress` / `complete` / `abandoned`. |
| `current_index` | INTEGER | Which position the player is on. Meaningless once finished. |

**Constraint**: a *partial unique index* over `status` where `status = 'in_progress'`, so the
database refuses a second live session rather than letting the resume prompt become ambiguous
(FR-010, research D7).

### `session_positions`

The snapshot (research D4). One row per position per session, capturing what the player was
actually shown.

| Column | Type | Notes |
|---|---|---|
| `session_id` | TEXT, FK → `sessions.id` | |
| `ordinal` | INTEGER | Position order within the session. |
| `position_id` | TEXT | The bundled position's identifier. |
| `initial_fen` | TEXT | |
| `solution_pgn` | TEXT | Snapshotted solution, with comments and NAGs. |
| `metadata_json` | TEXT | Snapshotted title, goal, themes, rating, source. |

Primary key `(session_id, ordinal)`.

**Nothing in the training layer queries this table.** It exists for review and for history.

### `attempts`

| Column | Type | Notes |
|---|---|---|
| `session_id` | TEXT, FK | |
| `position_id` | TEXT | |
| `tree_pgn` | TEXT | The committed analysis, PGN with a `[FEN]` header (research D2). |
| `duration_ms` | INTEGER | |
| `committed_at` | INTEGER | UTC epoch. |

Primary key `(session_id, position_id)`. Rows here are immutable once written — FR-015 of
feature 001 (a committed analysis cannot be edited) becomes a storage property too.

### `grades`

| Column | Type | Notes |
|---|---|---|
| `session_id` | TEXT, FK | |
| `position_id` | TEXT | |
| `value` | TEXT | `failed` / `hard` / `good` / `easy`. |
| `graded_at` | INTEGER | UTC epoch, rewritten when the grade is changed. |

Primary key `(session_id, position_id)` — one grade per position per session, overwritten in
place when the player revises it (FR-017).

---

## State machine

The stored status is coarser than the live one, and that is the point.

```
              start                    commit (last position)         all graded
   (none) ───────────► in_progress ─────────────────────────────────► complete
                            │                                              ▲
                            │ abandon, or discarded to start a new one     │
                            ▼                                              │
                        abandoned                          re-grade from history
```

**Transition rules**

- `in_progress → complete` only when every position has an attempt *and* every position has a
  grade — the same conditions feature 001 uses, now durable.
- `in_progress → abandoned` deletes the attempts and grades and keeps the row.
  The session stays in history as abandoned and **its snapshot is never shown** (FR-015). Feature
  001 could only forfeit answers until the process died; this makes it permanent.
- Only an `in_progress` session is offered for resumption (FR-009).
- Re-grading a `complete` session overwrites that position's grade and leaves the status
  alone (FR-017).

## Relationships

```
sessions
├── session_positions   ──► snapshot: initial FEN, solution PGN, metadata   [review only]
├── attempts            ──► committed tree as PGN                           [immutable]
└── grades              ──► one per position, overwritten on re-grade

TrainingProjection ◄── still built from the live session; touches none of the above
```

## Not modelled here

No user, no device, no sync state, no scheduling, and **no uncommitted analysis** — an
interruption costs the player the position they were part way through, by decision rather than
by omission (FR-003). Nor is there any cross-session view of a position. The scheduling feature
will read `grades` and add its own state beside them; this one stops at recording what happened
in each session.
