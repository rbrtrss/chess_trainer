import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';

/// The sample positions shipped inside the app, read from the asset bundle.
///
/// **No longer the app's content — its seed.** Feature 003 made the library the
/// source of positions; this class is read once, on first run, to plant the
/// samples as an ordinary collection (FR-033). After that they are renamable,
/// deletable, and in every respect like something the player imported, and
/// deleting them is permanent.
///
/// The three samples exist to prove the training loop, not to train on. A
/// calculation trainer whose content cannot change is a demo, which is what
/// feature 003 was for.
class BundledPositionSource {
  const BundledPositionSource({this.bundle});

  /// Overridable so tests can supply their own assets.
  final AssetBundle? bundle;

  AssetBundle get _assets => bundle ?? rootBundle;

  static const String _directory = 'assets/positions/';

  /// Every bundled position, ordered by asset name so a session is reproducible.
  ///
  /// Throws [PositionParseError] if any bundled PGN is malformed. Failing the
  /// whole load is the intended behaviour: a broken sample position must never
  /// reach a session, where it would be indistinguishable from a bug in the
  /// training loop.
  Future<IList<TrainingPosition>> loadAll() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_assets);
    final paths = manifest
        .listAssets()
        .where((path) => path.startsWith(_directory) && path.endsWith('.pgn'))
        .toList()
      ..sort();

    if (paths.isEmpty) {
      throw PositionParseError('no positions found under $_directory');
    }

    final positions = <TrainingPosition>[];
    for (final path in paths) {
      final pgn = await _assets.loadString(path);
      positions.add(parseTrainingPosition(pgn, id: _idOf(path)));
    }
    return positions.lock;
  }

  /// The asset's basename without extension, e.g. `001-tactic`.
  static String _idOf(String path) =>
      path.substring(_directory.length).replaceAll('.pgn', '');
}
