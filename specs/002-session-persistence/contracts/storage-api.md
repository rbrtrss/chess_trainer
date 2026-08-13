# Contract: Storage API

**Feature**: [spec.md](../spec.md) | **Data model**: [data-model.md](../data-model.md)

The surface the UI codes against and the required tests exercise. Bodies are omitted
deliberately — this is a contract, not an implementation.

The UI never sees Drift. It sees the repository interface below, which lives in `lib/data/`
while its implementation lives in `lib/data/local/`, as the constitution's layering section
requires.

```dart
// ------------------------------------------------------------------ sessions

/// Everything the app stores about sessions.
///
/// Implementations must satisfy the invariants below. The in-memory
/// implementation used by widget tests is held to the same ones.
abstract interface class SessionRepository {
  /// The unfinished session, if there is one (FR-006).
  ///
  /// Returns null when there is none, and **also** when stored data is
  /// unreadable — a corrupt row is treated as absent rather than as an error to
  /// propagate (FR-023, research D10).
  Future<StoredSession?> loadInProgress();

  /// Begins a session, snapshotting the solution and metadata of every position
  /// it contains (research D4).
  ///
  /// Throws [SessionAlreadyInProgressError] if one is already unfinished; the
  /// caller is expected to have warned and discarded first (FR-010).
  Future<StoredSession> start(IList<TrainingPosition> positions, {DateTime? now});

  /// Commits an attempt and advances, in **one transaction** (FR-005, D6):
  /// writes the attempt, moves the index, and marks the session complete when
  /// it was the last position.
  Future<void> commitAttempt(String sessionId, Attempt attempt);

  /// Records the player's grade for a position within a session (FR-017).
  ///
  /// Overwrites any grade already recorded for that position in that session;
  /// no earlier grade is kept (FR-017).
  Future<void> recordGrade(String sessionId, Grade grade, {DateTime? now});

  /// Ends a session without revealing anything (FR-015).
  ///
  /// Deletes attempts and grades, keeps the session row as
  /// [SessionStatus.abandoned]. The snapshot is retained but must never be
  /// shown for an abandoned session.
  Future<void> abandon(String sessionId);

  /// Discards an unfinished session so a new one can start (FR-011). Same
  /// effect as [abandon]; separate so the caller's intent is legible.
  Future<void> discardInProgress();

  /// Finished sessions, newest first (FR-013).
  Future<IList<SessionRecord>> listSessions({int limit, int offset});

  /// Everything needed to re-render a past review from the snapshot (FR-014).
  ///
  /// Returns null for an unknown id. For an abandoned session, returns a record
  /// whose solutions and metadata are **absent** rather than merely hidden by
  /// the UI (FR-015).
  Future<StoredSession?> loadSession(String id);

  /// Removes every stored session, attempt and grade (FR-018).
  Future<void> deleteEverything();
}

/// A session as stored: the record, its position snapshots, its attempts and
/// its grades. There is no stored analysis-in-progress — an interruption costs
/// the player the position they were part way through (FR-003).
@immutable
class StoredSession {
  final SessionRecord record;
  final IList<PositionSnapshot> positions;
  final IMap<String, Attempt> attempts;
  final IMap<String, Grade> grades;

  /// True when [positions] carry no solution — an abandoned session.
  bool get answersForfeited;
}

/// What the player was actually shown, frozen at the time (research D4).
@immutable
class PositionSnapshot {
  final String positionId;
  final int ordinal;
  final Position initialPosition;

  /// Null for an abandoned session: the answers are gone, not hidden.
  final VariationTree? solution;
  final PositionMetadata? metadata;
}

// There is deliberately no history repository. A cross-session view of how a
// position has gone before is out of scope: "you failed this one twice" is
// evidence about the position on screen, and the safest way to keep it off the
// training screen is for nothing to be able to ask for it. The grades stored
// against each session are what a later scheduling feature will read.

// ------------------------------------------------------------------- codec

/// A tree as PGN text, with a `[FEN]` header so the row is self-describing
/// (research D2). Built on the `toPgnNode` / `fromPgnNode` codec from
/// feature 001.
String encodeTree(VariationTree tree);

/// Inverse of [encodeTree].
///
/// Throws [TreeDecodeError] if the text is not a tree this app wrote.
VariationTree decodeTree(String pgn);
```

## Error contract

| Error | Raised when |
|---|---|
| `SessionAlreadyInProgressError` | `start` is called while an unfinished session exists. A caller bug: the UI warns and discards first. |
| `StorageWriteError` | A write failed. **Must surface to the player** (FR-024) — the one thing that must never happen is the player believing their work was saved when it was not. |
| `TreeDecodeError` | Stored PGN cannot be replayed. Treated as absent for a *read* (FR-023), never swallowed for a write. |

## Invariants the tests must enforce

1. A session written and read back is equal to what was written — record, snapshots, attempts
   and grades, including branches and which line is primary in every stored tree.
2. `commitAttempt` is atomic: simulating a failure part-way leaves the session with neither the
   attempt nor the advanced index, never one without the other. (FR-005)
3. A resumed session carries every attempt committed before the interruption, and no analysis
   for the position in progress — nothing is stored for it, so nothing comes back. (FR-003,
   FR-007)
4. `start` throws while a session is in progress, and the database rejects a second
   `in_progress` row even if application logic is bypassed. (FR-010, D7)
5. `recordGrade` called twice for the same position in the same session leaves exactly one
   grade, holding the later value. (FR-017)
6. An abandoned session keeps its record and loses its attempts and grades, and `loadSession`
   returns snapshots whose `solution` and `metadata` are null. (FR-015)
7. A completed session reopened after the supplied positions have changed still yields the
   solution it was run against. (SC-005, D4)
8. `loadInProgress` returns null — and does not throw — for corrupt or truncated stored data.
   (FR-023, D10)
9. A tree with at least 40 moves across 8 branches survives `encodeTree`/`decodeTree`
   unchanged, including comments and NAGs on a snapshotted solution. (D2)
10. No file under `lib/ui/training/` reads grade data or any type derived from it. There is no
    history repository to import; this rule exists so that one cannot quietly appear.
    (FR-019, D5 — enforced in `layering_test.dart`)
11. A resumed training screen renders identically to a fresh one at the same point. (FR-008,
    SC-003 — reusing `renderSnapshot` from feature 001's guard test)
