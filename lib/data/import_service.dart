/// Driving one import from choice to report.
///
/// The state machine is in `specs/003-position-import/data-model.md`. Every
/// state except the last can fail, and each failure has a required message —
/// which is why this is a service with a progress stream rather than a function
/// that returns a collection or throws.
library;

import 'dart:convert';

import 'package:chess_trainer/data/collection_repository.dart';
import 'package:chess_trainer/data/engine/evaluator.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/tree/move_path.dart';
import 'package:chess_trainer/domain/tree/variation_tree.dart';
import 'package:chess_trainer/data/import_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:crypto/crypto.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

/// Where an import is up to.
@immutable
sealed class ImportProgress {
  const ImportProgress();
}

/// Reading the file, or fetching the study. No count to report yet.
@immutable
final class ImportAcquiring extends ImportProgress {
  const ImportAcquiring();
}

/// Parsing, with a determinate count so the player sees movement (SC-007).
@immutable
final class ImportParsing extends ImportProgress {
  const ImportParsing(this.done, this.total);

  final int done;
  final int total;

  double get fraction => total == 0 ? 0 : done / total;
}

/// The content matches a collection already present (FR-010).
///
/// The import stops here and waits: the app does not silently merge,
/// deduplicate, or refuse — the player decides.
@immutable
final class ImportDuplicate extends ImportProgress {
  const ImportDuplicate(this.existing, this.outcome, this.contentHash);

  final Collection existing;
  final ImportOutcome outcome;

  /// Carried so confirming does not re-read and re-hash the source.
  final String contentHash;
}

/// Stored. What was added, and what was not.
@immutable
final class ImportReported extends ImportProgress {
  const ImportReported(this.collection, this.outcome);

  final Collection collection;
  final ImportOutcome outcome;
}

/// Nothing was imported, and this is why.
@immutable
final class ImportFailed extends ImportProgress {
  const ImportFailed(this.message, {this.outcome});

  /// Player-facing, and always says what happened. Never a stack trace.
  final String message;

  /// Present when the source parsed but yielded nothing usable, so the report
  /// can still say *why* each entry was refused.
  final ImportOutcome? outcome;
}

/// Turns a source into a stored collection.
abstract interface class ImportService {
  /// Imports a PGN file the player picked.
  Stream<ImportProgress> importFile(XFile file, {required String name});

  /// Imports text the player already has in hand — a paste, or a study fetched
  /// from Lichess (feature 003 US2 reuses this).
  Stream<ImportProgress> importText(
    String pgn, {
    required String name,
    required CollectionOrigin origin,
  });

  /// Opens the platform picker, or null if the player backed out.
  ///
  /// Accepts **any** file rather than filtering on a type: Android's document
  /// providers report `.pgn` inconsistently — often `application/octet-stream`
  /// or `text/plain` — so filtering strictly makes the player's own file
  /// invisible in the picker with no explanation (003 research D1). The content
  /// is validated instead, which is the check that has to exist anyway.
  Future<XFile?> pickFile();

  /// Completes an import the player confirmed after a duplicate warning.
  Future<ImportProgress> confirmDuplicate(
    ImportOutcome outcome, {
    required String name,
    required CollectionOrigin origin,
    required String contentHash,
  });
}

/// How the parsing is actually run.
///
/// Injectable so tests can parse in-process. The default runs it on another
/// isolate, which is the behaviour that matters on a phone and the behaviour
/// that makes a widget test slow and flaky.
/// Working out what the engine thinks of positions their author left unsolved
/// (005 FR-007).
///
/// A separate progress state from [ImportParsing] because it is a separate
/// wait, and one that can be much longer: parsing 330 positions takes under
/// three seconds, while a search costs about a quarter of a second *each*
/// (005 research D10). Reusing "Reading 12 of 12" would leave the screen
/// claiming to be doing something it finished seconds ago.
class ImportEvaluating implements ImportProgress {
  const ImportEvaluating(this.done, this.total);

  final int done;
  final int total;
}

typedef ImportParserRunner = Future<ImportOutcome> Function(String pgn);

class DefaultImportService implements ImportService {
  DefaultImportService(
    this._collections, {
    ImportParserRunner? parse,
    Evaluator? evaluator,
  })  : _parse = parse ?? _parseOffIsolate,
        // ignore: prefer_initializing_formals
        _evaluator = evaluator;

  final CollectionRepository _collections;
  final ImportParserRunner _parse;

  /// Supplies a solution where an author gave none (005 FR-007).
  ///
  /// Null on a platform with no engine, and in most tests. A null evaluator is
  /// not an error: the positions that needed one keep [SolutionSource.none] and
  /// stay trainable, which is FR-010 rather than a degraded mode.
  final Evaluator? _evaluator;

  @override
  Future<XFile?> pickFile() => openFile();

  @override
  Stream<ImportProgress> importFile(XFile file, {required String name}) async* {
    yield const ImportAcquiring();

    final String pgn;
    try {
      pgn = await file.readAsString();
    } on FormatException {
      // Almost always a binary file picked by mistake. Saying so is more use
      // than reporting a decoding error nobody can act on.
      yield const ImportFailed(
        'That file is not text, so it cannot be PGN. A study exported from '
        'Lichess, or any file of games or positions in PGN, is what this '
        'expects.',
      );
      return;
    } on Object catch (error) {
      // Deliberately catching `Object` rather than `FileSystemException`:
      // that type comes from the platform I/O library, and importing it here
      // would blunt the layering rule that keeps sockets out of every
      // directory except the one allowed to reach the network. A file that
      // will not open is a file that will not open, whatever type says so.
      yield ImportFailed('That file could not be read ($error).');
      return;
    }

    yield* importText(pgn, name: name, origin: FileOrigin(file.name));
  }

  @override
  Stream<ImportProgress> importText(
    String pgn, {
    required String name,
    required CollectionOrigin origin,
  }) async* {
    yield const ImportParsing(0, 0);

    ImportOutcome outcome;
    try {
      // Off the UI isolate: parsing replays every move of every variation for
      // legality (Principle III), which on a large study is seconds of CPU and
      // would otherwise be seconds of dropped frames (003 research D15).
      outcome = await _parse(pgn);
    } on SourceUnreadableError catch (error) {
      yield ImportFailed(error.message);
      return;
    } on SourceTooLargeError catch (error) {
      yield ImportFailed(error.message);
      return;
    } on Object catch (error) {
      yield ImportFailed('That file could not be read as PGN ($error).');
      return;
    }

    yield ImportParsing(outcome.entryCount, outcome.entryCount);

    // Where an author gave no line, an engine supplies one (005 FR-007).
    //
    // **This is the only place in the app that runs an engine**, and it runs
    // here rather than during a session because a search beside a player who is
    // calculating leaks through latency, battery and heat — channels no widget
    // test can see. After import, no engine runs at all, which is what makes
    // Principle I structural here rather than careful (005 research D2, and
    // Constitution III since v1.1.0).
    final needing =
        outcome.positions.where((p) => p.solutionSource == SolutionSource.none);
    if (needing.isNotEmpty && _evaluator != null) {
      var done = 0;
      yield ImportEvaluating(done, needing.length);

      final evaluated = <TrainingPosition>[];
      for (final position in outcome.positions) {
        if (position.solutionSource != SolutionSource.none) {
          evaluated.add(position);
          continue;
        }
        evaluated.add(await _judged(position));
        done++;
        yield ImportEvaluating(done, needing.length);
      }
      outcome = ImportOutcome(
        positions: IList(evaluated),
        rejections: outcome.rejections,
      );
    }

    if (outcome.positions.isEmpty) {
      yield ImportFailed(
        'Nothing in this could be trained, so nothing was imported.',
        outcome: outcome,
      );
      return;
    }

    final contentHash = hashOf(pgn);
    final existing = await _collections.findByContentHash(contentHash);
    if (existing != null) {
      yield ImportDuplicate(existing, outcome, contentHash);
      return;
    }

    yield await _store(outcome,
        name: name, origin: origin, contentHash: contentHash);
  }

  @override
  Future<ImportProgress> confirmDuplicate(
    ImportOutcome outcome, {
    required String name,
    required CollectionOrigin origin,
    required String contentHash,
  }) =>
      _store(outcome, name: name, origin: origin, contentHash: contentHash);

  /// One position, asked of the engine.
  ///
  /// Returns the position unchanged as [SolutionSource.none] when the engine
  /// has nothing to say — which is a normal outcome, not a failure (FR-010).
  /// One position upsetting the engine must not cost an import its other
  /// entries, so anything thrown is caught here rather than escaping.
  Future<TrainingPosition> _judged(TrainingPosition position) async {
    final EngineLine? line;
    try {
      line = await _evaluator!.bestLine(position.initialPosition);
    } on Object {
      return position;
    }
    if (line == null || line.moves.isEmpty) return position;

    var tree = VariationTree.empty(position.initialPosition);
    var path = MovePath.root;
    for (final move in line.moves.take(maxPrincipalVariationPlies)) {
      final edit = tree.play(path, move);
      tree = edit.tree;
      path = edit.path;
    }

    return TrainingPosition(
      id: position.id,
      initialPosition: position.initialPosition,
      solution: tree,
      metadata: position.metadata,
      solutionSource: SolutionSource.engine,
      evaluation: line.evaluation,
    );
  }

  Future<ImportProgress> _store(
    ImportOutcome outcome, {
    required String name,
    required CollectionOrigin origin,
    required String contentHash,
  }) async {
    try {
      final collection = await _collections.store(
        name: name,
        origin: origin,
        contentHash: contentHash,
        positions: outcome.positions,
        engineId: outcome.positions
                .any((p) => p.solutionSource == SolutionSource.engine)
            ? _evaluator?.engineId
            : null,
      );
      return ImportReported(collection, outcome);
    } on StorageWriteError catch (error) {
      // The store is one transaction, so there is nothing half-imported to
      // clean up — which is what lets this message be this plain.
      return ImportFailed(
        'This device could not save the import, so nothing was added. '
        '(${error.operation})',
      );
    }
  }

  static Future<ImportOutcome> _parseOffIsolate(String pgn) =>
      compute(parseImportInIsolate, pgn);
}

/// The isolate entry point.
///
/// Top-level and static-free because that is what `compute` requires, and
/// because everything it touches — the parser, the domain types — is pure.
///
/// Ids are minted here, per position and never reused, so the same study
/// imported twice yields two collections of distinct positions rather than a
/// primary-key clash.
ImportOutcome parseImportInIsolate(String pgn) =>
    parseImport(pgn, newId: timestampIds());

/// Ids unique to one import run.
IdGenerator timestampIds() {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  var next = 0;
  return () => 'p$stamp-${next++}';
}

/// SHA-256 of the source text, for duplicate detection (003 research D13).
String hashOf(String pgn) => sha256.convert(utf8.encode(pgn)).toString();
