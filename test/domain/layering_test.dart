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

  test('the training layer reads no content provenance (003 FR-026, FR-027)',
      () {
    // Feature 002's rule covered grades. Feature 003 introduced a second class
    // of evidence with exactly the same shape: where a position came from.
    // A collection called "Back-rank mates", a file called `mate-in-3.pgn`, a
    // study titled "Winning the Opposition" — each tells the player the answer,
    // and each is a string the app now holds while a player is calculating.
    //
    // The training screen is handed a `TrainingProjection` and cannot reach any
    // of it. This rule exists so that stays true.
    final trainingFiles = Directory('lib/ui/training')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    expect(trainingFiles, isNotEmpty);

    for (final file in trainingFiles) {
      final source = file.readAsStringSync();
      for (final forbidden in const [
        'Collection',
        'CollectionOrigin',
        'CollectionRepository',
        'BundledOrigin',
        'FileOrigin',
        'LichessOrigin',
        'PositionMetadata',
        'ImportOutcome',
        'RejectedEntry',
        'positionsIn',
        'listCollections',
        '.headers',
        'metadata',
        // Feature 004 put the account on the screen a session starts from,
        // which makes account state watchable from any widget for the first
        // time. A username is not evidence about a position, so this is not a
        // Principle I emergency — it is the standing rule that training screens
        // gain no affordances, written down before "logged in as roberto"
        // occurs to anyone as helpful context (004 FR-020, research D11).
        'LichessAccount',
        'LichessConnection',
        'lichessAccountProvider',
        'connectionController',
        'username',
      ]) {
        expect(source, isNot(contains(forbidden)),
            reason: '${file.path} reads $forbidden — the training screen must '
                'show nothing about where the position came from, because a '
                'collection name is evidence exactly as a chapter title is '
                '(FR-026)');
      }

      expect(source, isNot(contains('data/collection_repository.dart')),
          reason: '${file.path} imports the library surface');
      expect(source, isNot(contains('domain/library/')),
          reason: '${file.path} imports the library types');
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

  test('the network lives in one directory and nowhere else (003 D14)', () {
    // **This rule was narrowed by feature 003, and the narrowing is a real
    // loss.** Until then the release build declared no INTERNET permission and
    // was therefore *incapable* of reaching the network — a guarantee the
    // operating system enforced. Importing from Lichess needs that permission,
    // so the guarantee is gone and cannot be recovered.
    //
    // What replaces it is this rule plus `no_network_during_training_test.dart`:
    // networking may exist in exactly one directory, and the training flow is
    // proven not to touch it. That is weaker, deliberately, and it must not be
    // weakened further to make something else pass.
    //
    // Generated database code is included on purpose. `lib/` contains
    // `*.g.dart` files nobody wrote by hand, and a rule that quietly skipped
    // them would stop covering the layer most likely to reach for a socket.
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

    const networkDirectory = 'lib/data/lichess/';

    for (final file in libFiles) {
      if (file.path.startsWith(networkDirectory)) continue;

      final source = file.readAsStringSync();
      for (final networking in const [
        'package:http/',
        'dart:io',
        'HttpClient',
        'WebSocket',
        'Socket(',
      ]) {
        expect(source, isNot(contains(networking)),
            reason: '${file.path} contains $networking. Networking belongs in '
                '$networkDirectory and nowhere else — everything outside it '
                'must work with the device offline (FR-016)');
      }
    }
  });

  test('only the connection provider reaches the network directory', () {
    // The other half of the confinement. `lib/data/lichess/` may use an HTTP
    // client; the question is who may reach *it*.
    //
    // The domain layer: never. It is pure Dart and has no business knowing
    // Lichess exists.
    //
    // The UI: exactly one file, `connection_controller.dart`, which builds the
    // providers — the same arrangement `session_controller.dart` has with the
    // Drift repository, and for the same reason: this project keeps providers
    // in `lib/ui/`, so something there has to name an implementation. Every
    // screen goes through those providers, so no screen learns that Lichess is
    // reached over a network at all.
    const provider = 'lib/ui/library/connection_controller.dart';

    for (final file in Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      expect(file.readAsStringSync(), isNot(contains('data/lichess/')),
          reason: '${file.path} reaches the network from the domain layer');
    }

    final offenders = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path != provider)
        .where((file) => file.readAsStringSync().contains('data/lichess/'))
        .map((file) => file.path)
        .toList();

    expect(offenders, isEmpty,
        reason: 'these screens import the Lichess client directly instead of '
            'going through $provider (Principle II)');
  });

  test('the engine lives in one directory and nowhere else (005 D7)', () {
    // The second thing after networking that must be provably unreachable from
    // the rest of the app, and the constitution now requires it in as many
    // words: "Engine code MUST live in one directory and be unreachable from
    // the domain and UI layers, on the same terms as networking" (III).
    //
    // Written before the implementation exists, which is the ordering feature
    // 003 used for its Principle I guards — the rule is in place before the
    // temptation is.
    const engineDirectory = 'lib/data/engine/';

    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in libFiles) {
      if (file.path.startsWith(engineDirectory)) continue;

      expect(file.readAsStringSync(), isNot(contains('package:multistockfish')),
          reason: '${file.path} imports the engine package. It belongs in '
              '$engineDirectory and nowhere else');
    }

    // Import directives only, not the whole source. A doc comment that explains
    // this rule by naming the directory is documentation, not a dependency, and
    // the first version of this test failed on exactly that — the comment in
    // `evaluation.dart` saying the engine lives behind `lib/data/engine/`.
    bool importsEngine(File file) => file
        .readAsLinesSync()
        .where((line) =>
            line.trimLeft().startsWith('import ') ||
            line.trimLeft().startsWith('export '))
        .any((line) => line.contains('data/engine/'));

    // The domain layer: never. It is pure Dart and has no business knowing an
    // engine exists.
    final domainReachers = Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(importsEngine)
        .map((file) => file.path)
        .toList();

    expect(domainReachers, isEmpty,
        reason: 'the domain layer must not know an engine exists');

    // The UI: exactly one file, which builds the provider — the same
    // arrangement `connection_controller.dart` has with the Lichess client, and
    // for the same reason. Providers live in `lib/ui/` by this project's
    // convention, so something there has to name an implementation. Every other
    // file goes through `Evaluator`, so no screen learns an engine exists.
    const provider = 'lib/ui/library/library_controller.dart';

    final uiReachers = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path != provider)
        .where(importsEngine)
        .map((file) => file.path)
        .toList();

    expect(uiReachers, isEmpty,
        reason: 'these screens reach the engine directly instead of going '
            'through $provider');
    expect(File(provider).existsSync() && importsEngine(File(provider)), isTrue,
        reason: 'the one permitted file no longer builds the engine, so this '
            'rule is passing by covering nothing');
  });

  test('exactly one screen connects or disconnects the account (004 FR-012)',
      () {
    // Before feature 004 the login was in the study picker and the disconnect
    // was in the collection library, so the account had two homes and neither
    // was obvious. Both moved to the bar on the home screen.
    //
    // Checked as a source rule rather than by walking screens in a widget test,
    // because walking screens proves nothing about the screen nobody thought to
    // walk.
    const control = 'lib/ui/account/account_bar.dart';
    // Where the controller is defined, which is not a screen.
    const definition = 'lib/ui/library/connection_controller.dart';

    final offenders = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path != control && file.path != definition)
        .where((file) {
          final source = file.readAsStringSync();
          return source.contains('connectionControllerProvider');
        })
        .map((file) => file.path)
        .toList();

    expect(File(control).existsSync(), isTrue,
        reason: 'the one control is missing, so this rule is vacuous');
    expect(offenders, isEmpty,
        reason: 'these screens can connect or disconnect the Lichess account. '
            'There is one place for that, and it is $control — two controls '
            'for one account invite disagreement about which is authoritative '
            '(FR-012)');
  });
}
