/// A named group of imported positions, and where it came from.
///
/// See `specs/003-position-import/data-model.md`. Pure domain: this file knows
/// nothing about files, HTTP, or SQLite — it describes what a collection *is*,
/// and the data layer decides how one is obtained and stored.
library;

import 'package:meta/meta.dart';

/// Where a collection's positions came from.
///
/// A sealed hierarchy rather than a string, because the three cases carry
/// different data and are shown differently — and because a `switch` over them
/// stops compiling when a fourth arrives, which is the behaviour we want the
/// day someone adds one.
@immutable
sealed class CollectionOrigin {
  const CollectionOrigin();
}

/// The sample positions shipped inside the app, seeded on first run.
///
/// Not privileged in any way after seeding: it is renamable and deletable like
/// any other collection (FR-033). The distinction exists so the list can say
/// where the positions came from, not so the app can treat them specially.
@immutable
final class BundledOrigin extends CollectionOrigin {
  const BundledOrigin();

  @override
  bool operator ==(Object other) => other is BundledOrigin;

  @override
  int get hashCode => (BundledOrigin).hashCode;

  @override
  String toString() => 'BundledOrigin()';
}

/// A PGN file the player picked from the device.
@immutable
final class FileOrigin extends CollectionOrigin {
  const FileOrigin(this.fileName);

  /// The picked file's name.
  ///
  /// **Withheld from training screens exactly like a chapter title** (FR-026):
  /// `mate-in-3.pgn` tells the player the answer as surely as
  /// "Chapter 3: Winning the Opposition" does.
  final String fileName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileOrigin && fileName == other.fileName;

  @override
  int get hashCode => Object.hash(FileOrigin, fileName);

  @override
  String toString() => 'FileOrigin($fileName)';
}

/// A study fetched from Lichess.
///
/// Carries enough to identify what was imported and to offer "import it again"
/// later. It is **not** a live link: the local collection is a copy taken once,
/// and a study edited on Lichess afterwards does not change it (003 D13).
@immutable
final class LichessOrigin extends CollectionOrigin {
  const LichessOrigin({
    required this.studyId,
    required this.studyName,
    required this.fetchedAt,
  });

  /// Exactly 8 characters, as Lichess defines a study id.
  final String studyId;

  /// The study's name at the time it was fetched. Withheld during training for
  /// the same reason [FileOrigin.fileName] is.
  final String studyName;

  final DateTime fetchedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LichessOrigin &&
          studyId == other.studyId &&
          studyName == other.studyName &&
          fetchedAt == other.fetchedAt;

  @override
  int get hashCode => Object.hash(studyId, studyName, fetchedAt);

  @override
  String toString() => 'LichessOrigin($studyId)';
}

/// A named group of positions produced by one import.
@immutable
class Collection {
  const Collection({
    required this.id,
    required this.name,
    required this.origin,
    required this.importedAt,
    required this.positionCount,
  });

  final String id;

  /// Player-supplied, and deliberately **not** unique (FR-009): two imports of
  /// the same study under the same name is the player's business, and refusing
  /// it would be the app arguing about bookkeeping.
  final String name;

  final CollectionOrigin origin;

  final DateTime importedAt;

  /// Denormalised so the list can show it without loading every position.
  final int positionCount;

  Collection copyWith({String? name, int? positionCount}) => Collection(
        id: id,
        name: name ?? this.name,
        origin: origin,
        importedAt: importedAt,
        positionCount: positionCount ?? this.positionCount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Collection &&
          id == other.id &&
          name == other.name &&
          origin == other.origin &&
          importedAt == other.importedAt &&
          positionCount == other.positionCount;

  @override
  int get hashCode => Object.hash(id, name, origin, importedAt, positionCount);

  @override
  String toString() => 'Collection($id, "$name", $positionCount positions)';
}
