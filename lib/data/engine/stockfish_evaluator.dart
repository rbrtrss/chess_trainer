/// The only file in this project that knows a chess engine exists.
///
/// Everything else depends on [Evaluator]. That is not architectural taste:
/// `multistockfish` supports Android and iOS only, so **this class cannot be
/// exercised by any test** — `flutter test` runs on the host VM (005 research
/// D8). Every line here is verified on a device or not at all, which is why it
/// is small, why it holds no logic worth testing, and why every decision it
/// makes is one the contract already wrote down.
///
/// It is also the only place an engine is ever started. It is started during an
/// import and quit when that import ends; while a session exists, no engine
/// runs. That is a constitutional requirement since v1.1.0, not a performance
/// choice — a search beside a player who is calculating leaks through latency,
/// battery and heat, and no widget test can see any of those.
library;

import 'dart:async';

import 'package:chess_trainer/data/engine/evaluator.dart';
import 'package:chess_trainer/domain/position/evaluation.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:multistockfish/multistockfish.dart';

/// How long to wait for the engine to become ready before giving up.
///
/// A hung start was seen on a real phone on 2026-08-15. The package's own start
/// timeout is five seconds; this is the outer bound, after which [bestLine]
/// answers null and the import carries on reporting positions it could not
/// evaluate — which is FR-010 working, rather than an import that never ends.
const Duration _startTimeout = Duration(seconds: 15);

/// How long one search may take before it is abandoned.
///
/// Depth 12 measured 257 ms on the worst of five representative positions
/// (005 research D10), so this is roughly forty times the expected cost. It
/// exists to bound a pathological position or a wedged process, not to
/// influence the search — a timeout that fired routinely would make results
/// depend on how busy the phone was, which is exactly what fixed-depth
/// searching avoids.
const Duration _searchTimeout = Duration(seconds: 10);

class StockfishEvaluator implements Evaluator {
  StockfishEvaluator({Stockfish? engine}) : _engine = engine ?? Stockfish.instance;

  final Stockfish _engine;

  Stream<String>? _output;
  bool _started = false;

  /// Serialises searches.
  ///
  /// The package permits one engine instance at a time, and UCI is a
  /// conversation rather than a request/response protocol: two overlapping
  /// searches would read each other's `bestmove`. The contract promises callers
  /// they need not coordinate, so the coordination is here.
  Future<void> _inFlight = Future<void>.value();

  @override
  String get engineId => 'multistockfish/sf16 depth $searchDepth threads 1';

  @override
  Future<EngineLine?> bestLine(Position position) {
    final result = _inFlight.then((_) => _search(position));
    // Chained whether or not this search succeeds, so one failure does not
    // wedge every later call behind a rejected future.
    _inFlight = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<EngineLine?> _search(Position position) async {
    try {
      if (!await _ensureStarted()) return null;

      final output = _output!;
      final done = output
          .firstWhere((line) => line.startsWith('bestmove'))
          .timeout(_searchTimeout);

      // Collected while the search runs: the last `info` line carrying a score
      // and a principal variation is the engine's final answer.
      String? lastInfo;
      final listening = output.listen((line) {
        if (line.startsWith('info ') && line.contains(' pv ')) lastInfo = line;
      });

      _engine.stdin = 'position fen ${position.fen}';
      _engine.stdin = 'go depth $searchDepth';

      try {
        await done;
      } finally {
        await listening.cancel();
      }

      final info = lastInfo;
      if (info == null) return null;
      return _lineFrom(info, position);
    } on Object {
      // Every failure is a null: a start that never completed, a search that
      // timed out, a process that died, output that made no sense. One position
      // upsetting the engine must not cost an import its other entries
      // (FR-010), and it must never surface as a pending future.
      return null;
    }
  }

  /// Starts the engine if it is not already running, and configures it.
  ///
  /// Returns false rather than throwing when it will not start.
  Future<bool> _ensureStarted() async {
    if (_started && _engine.state.value == StockfishState.ready) return true;

    if (_engine.state.value != StockfishState.ready) {
      await _engine.start(flavor: StockfishFlavor.sf16);
      await _whenReady().timeout(_startTimeout);
    }
    if (_engine.state.value != StockfishState.ready) return false;

    _output = _engine.stdout.asBroadcastStream();

    // Threads 1 because a multi-threaded search is not reproducible even at
    // fixed depth — threads race to fill the shared table — and the device
    // tests need to repeat (005 research D4). A small hash because this is a
    // phone doing one position at a time.
    _engine.stdin = 'setoption name Threads value 1';
    _engine.stdin = 'setoption name Hash value 16';
    _engine.stdin = 'isready';
    await _output!
        .firstWhere((line) => line.startsWith('readyok'))
        .timeout(_startTimeout);

    _started = true;
    return true;
  }

  Future<void> _whenReady() {
    if (_engine.state.value == StockfishState.ready) return Future.value();

    final ready = Completer<void>();
    void listener() {
      switch (_engine.state.value) {
        case StockfishState.ready:
          if (!ready.isCompleted) ready.complete();
        case StockfishState.error:
          if (!ready.isCompleted) {
            ready.completeError(StateError('the engine could not start'));
          }
        case StockfishState.initial:
        case StockfishState.starting:
          break;
      }
    }

    _engine.state.addListener(listener);
    listener();
    return ready.future.whenComplete(() => _engine.state.removeListener(listener));
  }

  /// Turns one UCI `info` line into a line and an assessment.
  ///
  /// Returns null rather than guessing when the line is not what was expected.
  /// A malformed answer is the same as no answer.
  EngineLine? _lineFrom(String info, Position position) {
    final words = info.split(' ');

    final scoreAt = words.indexOf('score');
    final pvAt = words.indexOf('pv');
    if (scoreAt < 0 || pvAt < 0 || scoreAt + 2 >= words.length) return null;

    final Score score;
    final value = int.tryParse(words[scoreAt + 2]);
    if (value == null) return null;
    switch (words[scoreAt + 1]) {
      case 'cp':
        score = Centipawns(value);
      case 'mate':
        // UCI counts mate in *moves*; this app counts plies, because a ply is
        // what the tree is made of.
        score = MateIn(value * 2);
      default:
        return null;
    }

    // Replayed rather than trusted: every move is checked for legality against
    // the position it is played from, and the line is cut at the first one that
    // is not. The contract promises callers a legal line.
    final moves = <Move>[];
    var current = position;
    for (final uci in words.skip(pvAt + 1).take(maxPrincipalVariationPlies)) {
      final move = Move.parse(uci);
      if (move == null || !current.isLegal(move)) break;
      moves.add(move);
      current = current.play(move);
    }
    if (moves.isEmpty) return null;

    return EngineLine(
      moves: IList(moves),
      evaluation: PositionEvaluation(
        score: score,
        depth: searchDepth,
        perspective: position.turn,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (!_started) return;
    _started = false;
    _output = null;
    try {
      await _engine.quit();
    } on Object {
      // Best effort. An engine that will not quit must not stop an import from
      // reporting what it managed to do.
    }
  }
}
