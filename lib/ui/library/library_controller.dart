/// Providers for the library: collections, imports, and which collection a
/// session draws from.
///
/// Providers live in `lib/ui/` by this project's convention, which is what
/// keeps `lib/data/` free of Flutter and Riverpod imports (Constitution IV).
library;

import 'package:chess_trainer/data/collection_repository.dart';
import 'package:chess_trainer/data/engine/evaluator.dart';
import 'package:chess_trainer/data/engine/stockfish_evaluator.dart';
import 'package:chess_trainer/data/import_service.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the app stores imported content.
///
/// Tests override this with a repository over `AppDatabase.memory()`, which is
/// how the whole library path is exercised with no device attached.
final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return DriftCollectionRepository(ref.watch(appDatabaseProvider));
});

/// Seeds the bundled samples on first run, once (FR-033).
///
/// Everything that reads the library waits on this, so the app never opens on
/// an empty library that a moment later grows three positions.
final librarySeededProvider = FutureProvider<void>((ref) async {
  await ref.watch(collectionRepositoryProvider).seedSamplesIfNeeded();
});

/// Every collection, newest import first (FR-034).
final collectionsProvider = FutureProvider<IList<Collection>>((ref) async {
  await ref.watch<Future<void>>(librarySeededProvider.future);
  return ref.watch(collectionRepositoryProvider).listCollections();
});

/// Which collection the next session draws from (FR-029).
///
/// Null means "whichever was imported most recently", which is what a player
/// with one collection never has to think about.
final selectedCollectionProvider =
    NotifierProvider<SelectedCollection, String?>(SelectedCollection.new);

class SelectedCollection extends Notifier<String?> {
  @override
  String? build() => null;

  void choose(String? collectionId) => state = collectionId;
}

/// The positions a session can be built from.
///
/// This replaced `bundledPositionsProvider` in feature 003: the app's content
/// is the library now, and the samples are one collection in it.
final availablePositionsProvider =
    FutureProvider<IList<TrainingPosition>>((ref) async {
  final collections = await ref.watch(collectionsProvider.future);
  if (collections.isEmpty) return const IList.empty();

  final selected = ref.watch(selectedCollectionProvider);
  final chosen = collections.firstWhere(
    (collection) => collection.id == selected,
    // A collection deleted while it was selected falls back to the newest
    // rather than leaving the setup screen pointing at nothing.
    orElse: () => collections.first,
  );

  return ref.watch(collectionRepositoryProvider).positionsIn(chosen.id);
});

/// The collection a session would draw from right now, for the setup screen's
/// label. Null when the library is empty.
final chosenCollectionProvider = FutureProvider<Collection?>((ref) async {
  final collections = await ref.watch(collectionsProvider.future);
  if (collections.isEmpty) return null;

  final selected = ref.watch(selectedCollectionProvider);
  return collections.firstWhere(
    (collection) => collection.id == selected,
    orElse: () => collections.first,
  );
});

/// Runs imports.
/// The engine, built once and quit with the provider.
///
/// **This is the only file under `lib/ui/` that names the engine
/// implementation**, in the same way `connection_controller.dart` is the only
/// one that names the Lichess client, and for the same reason: providers live
/// in `lib/ui/` by this project's convention, so something here has to
/// construct it. What matters is that it is exactly one file, and that no
/// screen imports `lib/data/engine/`. `test/domain/layering_test.dart` enforces
/// both.
///
/// Nothing watches this except the import service. No screen builds it, no
/// session touches it, and `ref.onDispose` quits it — an engine left running
/// after an import is an engine running while the next session starts, which
/// the constitution forbids outright (Principle III).
final evaluatorProvider = Provider<Evaluator>((ref) {
  final evaluator = StockfishEvaluator();
  ref.onDispose(evaluator.dispose);
  return evaluator;
});

final importServiceProvider = Provider<ImportService>((ref) {
  return DefaultImportService(
    ref.watch(collectionRepositoryProvider),
    evaluator: ref.watch(evaluatorProvider),
  );
});
