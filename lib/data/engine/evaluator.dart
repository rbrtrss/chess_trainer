/// The seam between this app and a chess engine.
///
/// **Everything except one class depends on this interface**, and that is not
/// architectural taste — it is forced. `multistockfish` supports Android and
/// iOS only, and `flutter test` runs on the host VM, so a test that touched the
/// real engine could not run at all: not in CI, not on the development machine
/// (005 research D8). The fake goes here, and exactly one implementation
/// behind it does the real thing.
///
/// The same arrangement the Lichess client has: every test drives a fake, one
/// device task exercises the real one.
library;

import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// A principal variation, and what the engine made of the position it starts
/// from.
@immutable
class EngineLine {
  const EngineLine({required this.moves, required this.evaluation});

  /// The principal variation, capped at [maxPrincipalVariationPlies].
  ///
  /// Legal from the position asked about, in order. A caller replays these into
  /// a `VariationTree`; a replay that fails is a defect in the implementation,
  /// not a case for the caller to handle.
  final IList<Move> moves;

  final PositionEvaluation evaluation;
}

/// How much of the engine's line is worth keeping (005 contract §4).
///
/// Authored solutions in this app run to about nine moves. Beyond a dozen plies
/// an engine line is mostly its own hypothesis, and presenting all of it as
/// "the solution" would overstate how much of it means anything.
const int maxPrincipalVariationPlies = 12;

/// The search depth every evaluation is produced at (005 contract §4).
///
/// Measured on the target device rather than chosen: 257 ms on the worst of
/// five representative positions, against 1.25 s at depth 16 and 2.6 s at depth
/// 20 (005 research D10). Chosen on the worst case, because an import is only
/// as fast as its slowest entry.
const int searchDepth = 12;

abstract interface class Evaluator {
  /// The engine's opinion of [position], or null if it has none to give.
  ///
  /// **Returning null is a normal outcome and this must never throw** (005
  /// FR-010). The engine may be unavailable, the platform may have none, it may
  /// fail to start, it may time out, the process may die. Every one of those
  /// reaches the caller as null, which stores `SolutionSource.none` and carries
  /// on — one position upsetting the engine must not cost an import its other
  /// three hundred entries.
  ///
  /// It must also never return a pending future that does not resolve. A hung
  /// start was seen on a real phone on 2026-08-15; an import that hangs is
  /// worse than one reporting a position it could not evaluate, because the
  /// second is FR-010 working as designed.
  Future<EngineLine?> bestLine(Position position);

  /// What produced these answers — name, version and search budget.
  ///
  /// Stored beside the evaluation so a position imported by one build is not
  /// silently compared with one imported by another (005 research D5).
  String get engineId;

  /// Releases the engine.
  ///
  /// **Callers must do this when an import finishes.** The package permits one
  /// instance at a time, and an engine left running after an import is an
  /// engine running while the next session starts — which the constitution
  /// forbids outright (Principle III).
  Future<void> dispose();
}
