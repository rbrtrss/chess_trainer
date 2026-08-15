/// How [PositionMetadata] is stored, in one place.
///
/// Two tables hold metadata for two different reasons — `session_positions`
/// freezes what a session showed (002 D4), `positions` holds what an import
/// produced — and they must agree byte for byte, because a session snapshots
/// its positions *from* the library. One codec rather than two is what keeps
/// them agreeing.
library;

import 'dart:convert';

import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

String encodeMetadata(PositionMetadata metadata) => jsonEncode({
      'title': metadata.title,
      'goal': metadata.goal,
      'themes': metadata.themes.unlock,
      'rating': metadata.rating,
      'source': metadata.source,
      // Every header the entry carried (003 D11). Stored alongside the typed
      // fields rather than instead of them: review lays the five out
      // deliberately, and the bag is what makes withholding default-closed for
      // everything else.
      'headers': metadata.headers.unlock,
    });

PositionMetadata decodeMetadata(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on Object catch (error) {
    throw TreeDecodeError('stored metadata is not JSON: $error');
  }
  if (decoded is! Map<String, Object?>) {
    throw TreeDecodeError('stored metadata is not an object');
  }

  final themes = decoded['themes'];
  final headers = decoded['headers'];

  return PositionMetadata(
    title: decoded['title'] as String?,
    goal: decoded['goal'] as String?,
    themes: themes is List
        ? themes.whereType<String>().toIList()
        : const IList<String>.empty(),
    rating: decoded['rating'] as int?,
    source: decoded['source'] as String?,
    // Absent for rows written before feature 003. Those are the bundled
    // samples, whose headers were the five typed fields anyway, so an empty bag
    // loses nothing — and a missing key must not fail the read of a session the
    // player already played.
    headers: headers is Map
        ? headers.map((key, value) => MapEntry('$key', '$value')).lock
        : const IMap<String, String>.empty(),
  );
}
