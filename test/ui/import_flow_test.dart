import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:math';

import 'package:chess_trainer/data/import_parser.dart';
import 'package:chess_trainer/data/import_service.dart';
import 'package:chess_trainer/data/local/database.dart';
import 'package:chess_trainer/data/local/drift_collection_repository.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/library/import_outcome.dart';
import 'package:chess_trainer/ui/library/import_screen.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The import flow, from picking a file to reading what happened.
///
/// The picker itself is stubbed — it is a platform dialog, and what this test
/// is about is everything after it: parsing, the duplicate warning, the report,
/// and the failure messages.
void main() {
  late AppDatabase db;
  late DriftCollectionRepository collections;

  setUp(() {
    db = AppDatabase.memory();
    collections = DriftCollectionRepository(
      db,
      random: Random(20260814),
      loadSamples: () async => const IList.empty(),
    );
    addTearDown(db.close);
  });

  String fixture(String name) =>
      io.File('test/fixtures/$name').readAsStringSync();

  Future<void> pumpImport(
    WidgetTester tester, {
    required String pgn,
    String fileName = 'study.pgn',
    Duration parseDelay = Duration.zero,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _StubPickerImportService(
      DefaultImportService(
        collections,
        // Parsed in-process. The real service uses another isolate, which is
        // the behaviour that matters on a phone and the behaviour that makes a
        // widget test slow; what is under test here is the flow.
        parse: (source) async {
          if (parseDelay > Duration.zero) {
            await Future<void>.delayed(parseDelay);
          }
          return parseImport(source, newId: timestampIds());
        },
      ),
      XFile.fromData(Uint8List.fromList(utf8.encode(pgn)), name: fileName),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(collections),
          importServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: ImportScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> runImport(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('pick-file')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-import')));
    await tester.pumpAndSettle();
  }

  group('a study file becomes a collection (US1, FR-001 – FR-007)', () {
    testWidgets('the report says how many were added', (tester) async {
      await pumpImport(tester, pgn: fixture('study_multi_chapter.pgn'));
      await runImport(tester);

      expect(find.byKey(const Key('import-report')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('import-added-count'))).data,
        '33 positions added.',
      );
      expect(await collections.listCollections(), hasLength(1));
    });

    testWidgets('the positions are trainable afterwards', (tester) async {
      await pumpImport(tester, pgn: fixture('study_multi_chapter.pgn'));
      await runImport(tester);

      final stored = (await collections.listCollections()).single;
      expect(await collections.positionsIn(stored.id), hasLength(33));
    });

    testWidgets('rejections are reported, grouped, and named (SC-008)',
        (tester) async {
      await pumpImport(tester, pgn: fixture('study_mixed_chapters.pgn'));
      await runImport(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('import-added-count'))).data,
        '7 positions added.',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('import-rejected-count')))
            .data,
        contains('4 of the 11 entries could not be used'),
      );

      // Grouped by reason rather than printed one per line: a real study can
      // reject nine chapters for the same reason, and nine near-identical
      // lines reads as a broken app.
      expect(
        find.byKey(const Key(
            'rejection-group-${'noStartingPosition'}')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('rejection-group-noMoves')), findsOneWidget);

      // And the common case is explained, not just counted.
      expect(
        find.textContaining('does not say which moment is the exercise'),
        findsOneWidget,
      );
    });

    testWidgets('a chapter is named so the player can find it', (tester) async {
      await pumpImport(tester, pgn: fixture('study_mixed_chapters.pgn'));
      await runImport(tester);

      expect(find.textContaining('• Chapter 8'), findsOneWidget);
    });
  });

  group('a variant study is refused with its reason (FR-006)', () {
    testWidgets('nothing is imported and the reason is on screen',
        (tester) async {
      await pumpImport(tester, pgn: fixture('study_variant.pgn'));
      await runImport(tester);

      expect(find.byKey(const Key('import-failed')), findsOneWidget);
      expect(
        find.byKey(const Key('rejection-group-unsupportedVariant')),
        findsOneWidget,
      );
      expect(await collections.listCollections(), isEmpty);
    });
  });

  group('a source that is not PGN (US1 scenario 8)', () {
    testWidgets('says what was expected, and imports nothing', (tester) async {
      await pumpImport(tester, pgn: 'this is not a chess file at all');
      await runImport(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('import-failure-message')))
            .data,
        contains('PGN'),
      );
      expect(await collections.listCollections(), isEmpty);
    });
  });

  group('duplicate content (FR-010, invariant 11)', () {
    testWidgets('warns, and imports anyway when confirmed', (tester) async {
      await pumpImport(tester, pgn: fixture('study_mixed_chapters.pgn'));
      await runImport(tester);
      expect(await collections.listCollections(), hasLength(1));

      // The same file again.
      await pumpImport(tester, pgn: fixture('study_mixed_chapters.pgn'));
      await runImport(tester);

      expect(find.byKey(const Key('import-duplicate')), findsOneWidget);
      expect(find.textContaining('which you already have'), findsOneWidget);
      // Nothing was added while the player decides.
      expect(await collections.listCollections(), hasLength(1));

      await tester.tap(find.byKey(const Key('confirm-duplicate')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-report')), findsOneWidget);
      expect(await collections.listCollections(), hasLength(2),
          reason: 'the app does not merge, deduplicate or refuse — the player '
              'decides (FR-010)');
    });
  });

  group('progress is determinate while parsing (SC-007)', () {
    testWidgets('the screen shows progress rather than freezing',
        (tester) async {
      await pumpImport(
        tester,
        pgn: fixture('study_multi_chapter.pgn'),
        parseDelay: const Duration(milliseconds: 200),
      );

      await tester.tap(find.byKey(const Key('pick-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-import')));
      await tester.pump();

      // Mid-parse: the app is drawing, not blocked.
      expect(find.byKey(const Key('import-parsing')), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('import-report')), findsOneWidget);
    });

    test('the real service parses off the UI isolate (D15)', () {
      // The delay above is a stand-in for CPU work. What keeps the app
      // responsive in production is that `DefaultImportService` hands parsing
      // to `compute`; if that ever changes, a 300-chapter study freezes the
      // screen and no widget test would notice.
      final source = io.File('lib/data/import_service.dart').readAsStringSync();
      expect(source, contains('compute(parseImportInIsolate'));
    });
  });

  group('the outcome accounts for every entry (invariant 5)', () {
    testWidgets('added plus rejected equals the entries in the file',
        (tester) async {
      await pumpImport(tester, pgn: fixture('study_mixed_chapters.pgn'));
      await runImport(tester);

      final added = int.parse(RegExp(r'^(\d+)')
          .firstMatch(tester
              .widget<Text>(find.byKey(const Key('import-added-count')))
              .data!)!
          .group(1)!);
      final rejected = int.parse(RegExp(r'^(\d+)')
          .firstMatch(tester
              .widget<Text>(find.byKey(const Key('import-rejected-count')))
              .data!)!
          .group(1)!);

      expect(added + rejected, 11);
    });
  });
}

/// The real service, with the platform file picker replaced by a fixed file.
class _StubPickerImportService implements ImportService {
  _StubPickerImportService(this._delegate, this._file);

  final ImportService _delegate;
  final XFile _file;

  @override
  Future<XFile?> pickFile() async => _file;

  @override
  Stream<ImportProgress> importFile(XFile file, {required String name}) =>
      _delegate.importFile(file, name: name);

  @override
  Stream<ImportProgress> importText(
    String pgn, {
    required String name,
    required CollectionOrigin origin,
  }) =>
      _delegate.importText(pgn, name: name, origin: origin);

  @override
  Future<ImportProgress> confirmDuplicate(
    ImportOutcome outcome, {
    required String name,
    required CollectionOrigin origin,
    required String contentHash,
  }) =>
      _delegate.confirmDuplicate(outcome,
          name: name, origin: origin, contentHash: contentHash);
}
