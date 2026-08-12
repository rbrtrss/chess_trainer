import 'package:chess_trainer/data/pgn_position_parser.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';

/// The positions this feature trains on: a fixed set shipped inside the app
/// (FR-029), read from the asset bundle and never from a network (FR-030).
///
/// Content sourcing is deliberately out of scope here. When feature 004 adds
/// Lichess studies it will produce [TrainingPosition]s through the same parser,
/// and this class becomes one implementation of a repository interface rather
/// than the only source.
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
