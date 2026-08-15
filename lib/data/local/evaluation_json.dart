/// How a [PositionEvaluation] is stored, in one place.
///
/// Separate from `metadata_json.dart` because it answers a different question:
/// metadata is what the *source* said about a position, and an evaluation is
/// what *we* worked out about it. They are stored in different columns, arrive
/// by different routes, and there is no reason a change to one should be able
/// to break the other.
///
/// The stored form names its kind rather than relying on a shape. A score is
/// either centipawns or a forced mate, and a reader a year from now should not
/// have to infer which from whether a number looks large.
library;

import 'dart:convert';

import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:dartchess/dartchess.dart';

String encodeEvaluation(PositionEvaluation evaluation) => jsonEncode({
      'kind': switch (evaluation.score) {
        Centipawns() => 'cp',
        MateIn() => 'mate',
      },
      'value': switch (evaluation.score) {
        Centipawns(:final value) => value,
        MateIn(:final plies) => plies,
      },
      'depth': evaluation.depth,
      'perspective': evaluation.perspective == Side.white ? 'white' : 'black',
    });

PositionEvaluation decodeEvaluation(String stored) {
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException catch (error) {
    throw TreeDecodeError('stored evaluation is not JSON: $error');
  }

  if (decoded is! Map) {
    throw TreeDecodeError('stored evaluation is not an object');
  }

  final kind = decoded['kind'];
  final value = decoded['value'];
  final depth = decoded['depth'];
  if (value is! int || depth is! int) {
    throw TreeDecodeError('stored evaluation has no numeric value or depth');
  }

  final score = switch (kind) {
    'cp' => Centipawns(value),
    'mate' => MateIn(value),
    _ => throw TreeDecodeError('unknown evaluation kind "$kind"'),
  };

  return PositionEvaluation(
    score: score,
    depth: depth,
    // Defaulting rather than throwing: a missing perspective is recoverable and
    // an unreadable one is not worth losing a position over.
    perspective: decoded['perspective'] == 'black' ? Side.black : Side.white,
  );
}

/// The stored name for a [SolutionSource], and back.
///
/// Written out rather than using `.name` and `values.byName` so that renaming
/// an enum constant cannot silently change what is already in the database.
String encodeSolutionSource(SolutionSource source) => switch (source) {
      SolutionSource.author => 'author',
      SolutionSource.engine => 'engine',
      SolutionSource.none => 'none',
    };

SolutionSource decodeSolutionSource(String stored) => switch (stored) {
      'engine' => SolutionSource.engine,
      'none' => SolutionSource.none,
      // Anything unrecognised reads as authored, which is what every row
      // written before schema v3 is.
      _ => SolutionSource.author,
    };
