/// The library surface the rest of the app codes against.
///
/// See `specs/003-position-import/contracts/library-api.md`. As with
/// `SessionRepository`, the UI never sees Drift: this interface lives in
/// `lib/data/` while its implementation lives in `lib/data/local/`, as the
/// constitution's layering section requires.
library;

import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// Everything the app stores about imported content.
///
/// Implementations must satisfy the invariants in the contract; the in-memory
/// implementation used by widget tests is held to the same ones.
abstract interface class CollectionRepository {
  /// Every collection, newest import first (FR-034).
  Future<IList<Collection>> listCollections();

  /// One collection, or null if it is not there.
  Future<Collection?> collection(String collectionId);

  /// The positions of one collection, in source order.
  ///
  /// Returns an empty list for an unknown collection rather than throwing: a
  /// collection deleted while the player was looking at a stale list is an
  /// absence, not an error.
  Future<IList<TrainingPosition>> positionsIn(String collectionId);

  /// Stores a parsed import as a new collection, in **one transaction**
  /// (FR-019, FR-041): the collection row and every position commit together
  /// or not at all.
  ///
  /// Throws [StorageWriteError] if the write fails. Nothing partial is left
  /// behind — an interrupted import must not produce half a study, because a
  /// study missing its last four chapters looks like a study that only had
  /// eleven.
  Future<Collection> store({
    required String name,
    required CollectionOrigin origin,
    required String contentHash,
    required IList<TrainingPosition> positions,
    DateTime? now,
  });

  /// The collection already holding this content, if any (FR-010, 003 D13).
  ///
  /// Compared by content hash, not by name, study id, or file name — the case
  /// that actually happens is the same study exported twice under two names.
  Future<Collection?> findByContentHash(String contentHash);

  /// Renames a collection (FR-035). No uniqueness constraint (FR-009).
  Future<void> rename(String collectionId, String name);

  /// Deletes a collection and its positions (FR-036).
  ///
  /// Sessions are untouched: each carries its own frozen copy of what it
  /// showed (002 D4), so a past review remains readable afterwards (FR-037).
  /// The caller is expected to have warned first, including the extra warning
  /// when the unfinished session depends on this collection (FR-038).
  Future<void> delete(String collectionId);

  /// Seeds the bundled samples as an ordinary collection, once (FR-033).
  ///
  /// Does nothing if the seeding has already happened, so deleting the samples
  /// is permanent and they do not reappear on the next launch.
  Future<void> seedSamplesIfNeeded();
}
