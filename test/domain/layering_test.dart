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

  test('nothing in the app opens a network connection (FR-030, Principle II)',
      () {
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

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
