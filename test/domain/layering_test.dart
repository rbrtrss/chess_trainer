import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Principle IV: `lib/domain/` is pure Dart — zero Flutter imports, zero I/O,
/// zero platform calls.
///
/// The constitution's reasoning is that the interesting logic belongs where it
/// can be tested without a device, and that a rule which is hard to unit-test
/// is in the wrong layer. A stray `package:flutter` import is how that slowly
/// stops being true, so it is checked rather than trusted.
void main() {
  final domainFiles = Directory('lib/domain')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  test('the domain layer exists and is where the model lives', () {
    expect(domainFiles, isNotEmpty);
  });

  test('no file in lib/domain imports Flutter', () {
    for (final file in domainFiles) {
      final offending = file
          .readAsLinesSync()
          .where((line) => line.trimLeft().startsWith('import '))
          .where((line) =>
              line.contains('package:flutter/') ||
              line.contains('package:flutter_riverpod/') ||
              line.contains('package:flutter_test/') ||
              line.contains('package:chessground/'))
          .toList();

      expect(offending, isEmpty,
          reason: '${file.path} reaches out of the domain layer: $offending');
    }
  });

  test('no file in lib/domain performs I/O', () {
    for (final file in domainFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains("import 'dart:io'")),
          reason: '${file.path} does I/O');
      expect(source, isNot(contains('rootBundle')),
          reason: '${file.path} reads assets');
    }
  });

  test('the domain layer does not import the data or ui layers', () {
    for (final file in domainFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:chess_trainer/data/')),
          reason: '${file.path} depends outward on the data layer');
      expect(source, isNot(contains('package:chess_trainer/ui/')),
          reason: '${file.path} depends outward on the ui layer');
    }
  });

  test('the data layer does not import the ui layer', () {
    final dataFiles = Directory('lib/data')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dataFiles) {
      expect(file.readAsStringSync(),
          isNot(contains('package:chess_trainer/ui/')),
          reason: '${file.path} depends outward on the ui layer');
    }
  });

  test('the training layer reads no grade or history data (FR-019)', () {
    // Persistence stored grades for the first time, so the ingredients for
    // "last seen 3 days ago, graded Hard" now exist even though nothing
    // displays them. That display is evidence about the position in front of a
    // player who is still calculating, and it is the most tempting thing to add
    // to a training screen because it looks like helpful context.
    //
    // Nothing produces it today. This rule exists so that nothing can start to,
    // and the scheduling feature will need it on its first day.
    final trainingFiles = Directory('lib/ui/training')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    expect(trainingFiles, isNotEmpty);

    for (final file in trainingFiles) {
      final source = file.readAsStringSync();
      for (final forbidden in const [
        'Grade',
        'GradeValue',
        'SessionRecord',
        'SessionStatus',
        'StoredSession',
        'PositionSnapshot',
        'SessionRepository',
        'sessionRepositoryProvider',
        'resumeCandidateProvider',
        'listSessions',
        'loadSession',
        'loadInProgress',
      ]) {
        expect(source, isNot(contains(forbidden)),
            reason: '${file.path} reads $forbidden — the training screen must '
                "show nothing derived from the player's history with the "
                'position on screen (FR-019)');
      }

      expect(source, isNot(contains('data/session_repository.dart')),
          reason: '${file.path} imports the storage surface');
      expect(source, isNot(contains('data/local/')),
          reason: '${file.path} imports the database');
    }
  });

  test('nothing in the app opens a network connection (FR-030, Principle II)',
      () {
    // Generated database code is included on purpose. `lib/` now contains
    // `*.g.dart` files nobody wrote by hand, and a rule that quietly skipped
    // them would stop covering the layer most likely to reach for a socket.
    // Drift's output imports neither `dart:io` nor an HTTP client, so nothing
    // needs narrowing — checked here rather than assumed.
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    expect(
      libFiles.where((file) => file.path.endsWith('.g.dart')),
      isNotEmpty,
      reason: 'run `dart run build_runner build` — the generated database code '
          'is missing, so this rule is not covering it',
    );

    for (final file in libFiles) {
      final source = file.readAsStringSync();
      for (final networking in const [
        'package:http/',
        'dart:io',
        'HttpClient',
        'WebSocket',
        'Socket(',
      ]) {
        expect(source, isNot(contains(networking)),
            reason: '${file.path} contains $networking — this feature is '
                'entirely offline and has no sync path');
      }
    }
  });
}
