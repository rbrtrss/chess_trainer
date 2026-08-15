# Contract: Library API

**Feature**: [spec.md](../spec.md) | **Data model**: [data-model.md](../data-model.md) |
**Companion**: [lichess-api.md](./lichess-api.md)

The surface the UI codes against for collections and imports. Bodies are omitted deliberately —
this is a contract, not an implementation.

As in feature 002, the UI never sees Drift: it sees the interfaces below, which live in
`lib/data/` while their implementations live in `lib/data/local/` (Principle IV).

```dart
// --------------------------------------------------------------- collections

/// Everything the app stores about imported content.
///
/// Implementations must satisfy the invariants below. The in-memory
/// implementation used by widget tests is held to the same ones.
abstract interface class CollectionRepository {
  /// Every collection, newest import first (FR-034).
  Future<IList<Collection>> listCollections();

  /// The positions of one collection, in source order.
  ///
  /// Returns an empty list for an unknown collection rather than throwing: a
  /// collection deleted in another tab of the player's attention is an absence,
  /// not an error.
  Future<IList<TrainingPosition>> positionsIn(String collectionId);

  /// Stores a parsed import as a new collection, in ONE transaction (FR-019,
  /// FR-041): the collection row and every position commit together or not at
  /// all.
  ///
  /// Throws [StorageWriteError] if the write fails. Nothing partial is left
  /// behind — an interrupted import must not produce half a study.
  Future<Collection> store({
    required String name,
    required CollectionOrigin origin,
    required String contentHash,
    required IList<TrainingPosition> positions,
    DateTime? now,
  });

  /// The collection already holding this content, if any (FR-010, D13).
  ///
  /// Compared by content hash, not by name, study id, or file name — the case
  /// that actually happens is the same study exported twice under two names.
  Future<Collection?> findByContentHash(String contentHash);

  /// Renames a collection (FR-035). No uniqueness constraint (FR-009).
  Future<void> rename(String collectionId, String name);

  /// Deletes a collection and its positions (FR-036).
  ///
  /// Sessions are untouched: each carries its own frozen copy of what it showed
  /// (002, D4), so a past review remains readable afterwards (FR-037). The
  /// caller is expected to have warned first, including the extra warning when
  /// the unfinished session depends on this collection (FR-038).
  Future<void> delete(String collectionId);

  /// Seeds the bundled samples as an ordinary collection, once (FR-033).
  ///
  /// Does nothing if the `samples_seeded` flag is set, so deleting the samples
  /// is permanent and they do not reappear on the next launch.
  Future<void> seedSamplesIfNeeded();
}

// ------------------------------------------------------------------- parsing

/// Turns PGN text — from a file or from Lichess — into positions and
/// rejections. Pure; no I/O, no plugins, safe to run in an isolate (D15).
///
/// Never throws for a bad *entry*: entries are rejected individually and
/// reported (FR-007). Throws only when the whole source is unusable — not PGN
/// at all, or past the stated size limits (D16).
ImportOutcome parseImport(String pgn, {required IdGenerator newId});

/// One entry of a source. Rejects with [PositionParseError] when the entry has
/// no `[FEN]` header, no moves, an illegal move, or a non-standard `[Variant]`
/// (FR-006, D10).
///
/// CHANGED in this feature: previously fell back to the standard initial
/// position when `[FEN]` was absent. It now rejects, because against arbitrary
/// imports that fallback silently turns a game record into an untrainable
/// "position" starting at move 1.
TrainingPosition parseTrainingPosition(String pgn, {required String id});

// -------------------------------------------------------------- the importer

/// Drives one import from choice to report — the state machine in the data
/// model. Owned by the UI layer's controller, tested without a device.
abstract interface class ImportService {
  /// Reads a picked file, parses it off the UI isolate, and reports progress
  /// as `(done, total)` while it runs (SC-007).
  Stream<ImportProgress> importFile(XFile file, {required String name});

  /// The same, from a Lichess study. Needs a connection only for a private
  /// study (FR-011, FR-012).
  Stream<ImportProgress> importStudy(String studyIdOrUrl, {String? name});
}
```

## Error contract

| Error | Raised when |
|---|---|
| `PositionParseError` | One entry cannot be trained. Carries a `RejectionReason`; collected into the report rather than propagated (FR-007). |
| `SourceUnreadableError` | The whole source is not PGN, or is empty. Nothing is imported (FR-006, US1 scenario 8). |
| `SourceTooLargeError` | Past the stated cap. **Message must name the limit** (D16). |
| `StorageWriteError` | A write failed. Surfaces to the player, and nothing partial remains (FR-041). |

Network errors are the companion contract's, and are listed there.

## Invariants the tests must enforce

1. A collection written and read back is equal to what was written, including every position's
   solution tree with its branches, comments and NAGs, and its full header bag. (FR-002, D11)
2. `store` is atomic: simulating a failure part-way leaves **no** collection row and **no**
   positions — never a collection with some of its study. (FR-019, FR-041)
3. An entry with no `[FEN]` header is rejected with `noStartingPosition`, and the other entries
   of the same source still import. (FR-003, FR-006, FR-007, D10)
4. Entries with no moves, an illegal move, and a non-standard `[Variant]` are each rejected with
   their own reason, and the report identifies each by title or ordinal. (FR-006, SC-008)
5. Every rejected entry appears in the outcome. A source of *n* entries yields
   `positions.length + rejections.length == n`, always. (SC-008)
6. Every PGN header of an imported entry survives into `PositionMetadata.headers`, including
   headers the app has never heard of. (FR-024, FR-025, D11)
7. Every variation in the source is present in the stored solution, and which line is primary is
   preserved. (FR-004, SC-006)
8. Deleting a collection removes its positions and leaves every stored session — record,
   snapshots, attempts, grades — byte-identical. (FR-037, SC-012)
9. `seedSamplesIfNeeded` seeds once; after deleting the sample collection and calling it again,
   nothing is seeded. (FR-033)
10. A session started on a collection draws every position from that collection, and a collection
    with fewer positions than requested yields a shorter session rather than a repeated one.
    (FR-030, FR-031)
11. Importing content whose hash matches an existing collection reports the duplicate and, on
    confirmation, still imports. (FR-010)
12. Parsing a 300-entry study reports determinate progress and never blocks the UI isolate for
    more than one frame at a time. (SC-007, D15)
13. **No file under `lib/ui/training/` mentions a collection, its name, its origin, or any
    metadata header.** The rule from 002 is extended: the training layer may not read grade data
    *or* content provenance. (FR-026, FR-027, SC-003)
