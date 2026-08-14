import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/position/training_position.dart';
import 'package:chess_trainer/domain/session/grade.dart';
import 'package:chess_trainer/domain/session/session_record.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/tree_helpers.dart';
import 'repository_harness.dart';

/// The storage invariants from
/// `specs/002-session-persistence/contracts/storage-api.md`.
///
/// Everything here runs against an in-memory database, so persistence is
/// testable with no device attached.
void main() {
  group('invariant 1 — a session survives being written and read back', () {
    test('the record comes back as it went in', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions();
      final startedAt = DateTime.utc(2026, 8, 12, 9, 15);

      final started =
          await harness.repository.start(positions, now: startedAt);
      final loaded = await harness.repository.loadInProgress();

      expect(loaded, isNotNull);
      expect(loaded!.record.id, started.record.id);
      expect(loaded.record.startedAt, startedAt);
      expect(loaded.record.endedAt, isNull);
      expect(loaded.record.status, SessionStatus.inProgress);
      expect(loaded.record.positionIds,
          positions.map((position) => position.id).toIList());
    });

    test('the snapshots come back with their trees intact, branches and all',
        () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions();

      final started = await harness.repository.start(positions);
      final loaded = await harness.repository.loadInProgress();

      expect(loaded!.positions, started.positions);

      for (var i = 0; i < positions.length; i++) {
        final snapshot = loaded.positions[i];
        final position = positions[i];

        expect(snapshot.positionId, position.id);
        expect(snapshot.ordinal, i);
        expect(snapshot.initialPosition.fen, position.initialPosition.fen);
        // The whole tree, not just its main line: which sibling is primary at
        // every branch point is what review measures divergence against.
        expect(snapshot.solution, position.solution);
        expect(snapshot.metadata, position.metadata);
      }
    });

    test('metadata survives in full, including themes and rating', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 1);

      await harness.repository.start(positions);
      final loaded = await harness.repository.loadInProgress();

      final metadata = loaded!.positions.first.metadata;
      expect(metadata, isNotNull);
      expect(metadata!.title, "Philidor's Legacy");
      expect(metadata.goal, 'White to play and force mate');
      expect(metadata.themes, contains('smothered mate'));
      expect(metadata.rating, 1500);
      expect(metadata.source, 'Classic study');
    });

    // The attempts and grades half of invariant 1 needs `commitAttempt` and
    // `recordGrade`, and is asserted in the "resuming" and "grading" groups
    // below, which arrive with them.
  });

  group('invariant 4 — at most one session in progress', () {
    test('start throws while a session is unfinished', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());

      expect(
        () => harness.repository.start(samplePositions()),
        throwsA(isA<SessionAlreadyInProgressError>()),
      );
    });

    test('the first session is untouched by the refused second one', () async {
      final harness = RepositoryHarness.create();
      final first = await harness.repository.start(samplePositions());

      await expectLater(
        harness.repository.start(samplePositions()),
        throwsA(isA<SessionAlreadyInProgressError>()),
      );

      final loaded = await harness.repository.loadInProgress();
      expect(loaded!.record.id, first.record.id);
      expect(await harness.rawSessions(), hasLength(1));
    });

    test('the database refuses a second in_progress row even when application '
        'logic is bypassed', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());

      // Straight past the repository, the way a future bug would.
      await expectLater(
        harness.insertRawSession(id: 'smuggled', status: 'in_progress'),
        throwsA(anything),
      );

      expect(await harness.rawSessions(), hasLength(1));
    });

    test('a finished session does not block a new one', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());
      await harness.corrupt(
        "UPDATE sessions SET status = 'complete', ended_at = 1",
      );

      // No throw: the partial index only constrains in_progress rows.
      final second = await harness.repository.start(samplePositions());
      expect(second.record.status, SessionStatus.inProgress);
      expect(await harness.rawSessions(), hasLength(2));
    });
  });

  group('invariant 2 — a commit is atomic', () {
    test('a failure part way through leaves neither the attempt nor the '
        'advanced index', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions();
      final started = await harness.repository.start(positions);

      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[0]));

      final afterFirst = await harness.repository.loadInProgress();
      expect(afterFirst!.record.currentIndex, 1);

      // Committing the same position twice fails on the attempt insert, which
      // happens *after* the index has already been moved inside the
      // transaction. If the transaction did not roll back, the session would be
      // left at an index past a position with no attempt — the one state that
      // is unrecoverable, because `allPositionsAttempted` could never become
      // true and review could never begin.
      await expectLater(
        harness.repository
            .commitAttempt(started.id, sampleAttempt(positions[0])),
        throwsA(isA<StorageWriteError>()),
      );

      final afterFailure = await harness.repository.loadInProgress();
      expect(afterFailure!.record.currentIndex, 1,
          reason: 'the index moved without an attempt being stored');
      expect(afterFailure.attempts.length, 1);
      expect(await harness.rawAttempts(), hasLength(1));
    });

    test('a commit against an unknown session writes nothing at all', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions();
      final started = await harness.repository.start(positions);

      await expectLater(
        harness.repository.commitAttempt('no-such-session',
            sampleAttempt(positions[0])),
        throwsA(isA<StorageWriteError>()),
      );

      final loaded = await harness.repository.loadInProgress();
      expect(loaded!.record.id, started.id);
      expect(loaded.record.currentIndex, 0);
      expect(await harness.rawAttempts(), isEmpty);
    });

    test('committing the last position completes the session in one step',
        () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 2);
      final started = await harness.repository.start(positions);

      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[0]));
      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[1]));

      // No session is in progress any more, and the row says complete.
      expect(await harness.repository.loadInProgress(), isNull);
      final rows = await harness.rawSessions();
      expect(rows.single.status, 'complete');
      expect(rows.single.endedAt, isNotNull);
    });
  });

  group('invariant 3 — a resumed session carries what was committed', () {
    test('every attempt committed before the interruption comes back, and '
        'nothing for the position in progress', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 5);
      final started = await harness.repository.start(positions);

      final first = sampleAttempt(positions[0]);
      final second = sampleAttempt(positions[1],
          duration: const Duration(minutes: 4));
      await harness.repository.commitAttempt(started.id, first);
      await harness.repository.commitAttempt(started.id, second);

      // The player is now part way through position 3 with moves on the board.
      // Nothing is written for it, so nothing can come back for it.
      final resumed = await harness.repository.loadInProgress();

      expect(resumed!.record.currentIndex, 2);
      expect(resumed.record.positionIds.length, 5);
      expect(resumed.attempts.keys.toSet(),
          {positions[0].id, positions[1].id});
      expect(resumed.attempts[positions[2].id], isNull);

      // Invariant 1's other half: attempts round trip whole, tree and all.
      expect(resumed.attempts[positions[0].id], first);
      expect(resumed.attempts[positions[1].id], second);
      expect(resumed.attempts[positions[0].id]!.tree, first.tree);
    });

    test('an abandoned session is not offered for resumption', () async {
      final harness = RepositoryHarness.create();
      final started = await harness.repository.start(samplePositions());

      await harness.repository.abandon(started.id);

      expect(await harness.repository.loadInProgress(), isNull);
    });

    test('a completed session is not offered for resumption', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 1);
      final started = await harness.repository.start(positions);

      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[0]));

      expect(await harness.repository.loadInProgress(), isNull);
    });
  });

  group('invariant 5 — one grade per position per session', () {
    test('re-grading overwrites and keeps the later value', () async {
      final harness = RepositoryHarness.create();
      // Two positions with one committed, so the session is still readable
      // through `loadInProgress` — reopening a *finished* session is US2's job.
      final positions = samplePositions(count: 2);
      final started = await harness.repository.start(positions);
      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[0]));

      await harness.repository.recordGrade(
        started.id,
        Grade(positionId: positions[0].id, value: GradeValue.failed),
      );
      await harness.repository.recordGrade(
        started.id,
        Grade(positionId: positions[0].id, value: GradeValue.good),
      );

      expect(await harness.rawGrades(), hasLength(1));
      final loaded = await harness.repository.loadInProgress();
      expect(loaded!.grades[positions[0].id]!.value, GradeValue.good);
    });

    test('grades for different positions coexist', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 2);
      final started = await harness.repository.start(positions);

      await harness.repository.recordGrade(started.id,
          Grade(positionId: positions[0].id, value: GradeValue.hard));
      await harness.repository.recordGrade(started.id,
          Grade(positionId: positions[1].id, value: GradeValue.easy));

      expect(await harness.rawGrades(), hasLength(2));
    });
  });

  group('invariant 6 — abandoning forfeits the answers permanently', () {
    test('the record stays and the attempts and grades go', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 3);
      final started = await harness.repository.start(positions);
      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[0]));
      await harness.repository.recordGrade(started.id,
          Grade(positionId: positions[0].id, value: GradeValue.good));

      await harness.repository.abandon(started.id);

      final rows = await harness.rawSessions();
      expect(rows.single.status, 'abandoned');
      expect(rows.single.endedAt, isNotNull);
      expect(await harness.rawAttempts(), isEmpty);
      expect(await harness.rawGrades(), isEmpty);
    });

    test('discarding an unfinished session frees the way for a new one',
        () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());

      await harness.repository.discardInProgress();

      expect(await harness.repository.loadInProgress(), isNull);
      // Which is the whole point: the player said start a new one.
      final second = await harness.repository.start(samplePositions());
      expect(second.record.status, SessionStatus.inProgress);
    });

    test('discarding when there is nothing in progress does nothing', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.discardInProgress();
      expect(await harness.rawSessions(), isEmpty);
    });
  });

  group('the history of past sessions (FR-013)', () {
    test('finished sessions are listed newest first', () async {
      final harness = RepositoryHarness.create();

      final ids = <String>[];
      for (var day = 1; day <= 3; day++) {
        final positions = samplePositions(count: 1);
        final started = await harness.repository
            .start(positions, now: DateTime.utc(2026, 8, day));
        ids.add(started.id);
        await harness.repository
            .commitAttempt(started.id, sampleAttempt(positions[0]));
      }

      final listed = await harness.repository.listSessions();

      expect(listed.map((record) => record.id).toList(),
          [ids[2], ids[1], ids[0]]);
      expect(listed.first.startedAt, DateTime.utc(2026, 8, 3));
      expect(listed.first.status, SessionStatus.complete);
      expect(listed.first.positionIds, hasLength(1));
    });

    test('abandoned sessions are listed too, as abandoned', () async {
      final harness = RepositoryHarness.create();
      final started = await harness.repository.start(samplePositions());
      await harness.repository.abandon(started.id);

      final listed = await harness.repository.listSessions();

      expect(listed, hasLength(1));
      expect(listed.single.status, SessionStatus.abandoned);
      expect(listed.single.endedAt, isNotNull);
    });

    test('a session still in progress is not in the history', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());

      expect(await harness.repository.listSessions(), isEmpty);
    });

    test('limit and offset page through it', () async {
      final harness = RepositoryHarness.create();
      for (var day = 1; day <= 5; day++) {
        final started = await harness.repository
            .start(samplePositions(count: 1), now: DateTime.utc(2026, 8, day));
        await harness.repository.abandon(started.id);
      }

      final first = await harness.repository.listSessions(limit: 2);
      final second =
          await harness.repository.listSessions(limit: 2, offset: 2);

      expect(first, hasLength(2));
      expect(second, hasLength(2));
      expect(first.first.startedAt, DateTime.utc(2026, 8, 5));
      expect(second.first.startedAt, DateTime.utc(2026, 8, 3));
    });
  });

  group('invariant 7 — a finished session is a record of what was shown', () {
    test('reopening it after the bundled positions changed still yields the '
        'solution it was run against', () async {
      final harness = RepositoryHarness.create();
      final asPlayed = samplePositions(count: 1);
      final started = await harness.repository.start(asPlayed);
      await harness.repository
          .commitAttempt(started.id, sampleAttempt(asPlayed[0]));
      await harness.repository.recordGrade(started.id,
          Grade(positionId: asPlayed[0].id, value: GradeValue.hard));

      // The app updates: the same position id now ships with a different
      // solution, different notes and a different title.
      final corrected = TrainingPosition(
        id: asPlayed[0].id,
        initialPosition: asPlayed[0].initialPosition,
        solution: treeFromLine(const ['Qb8+'], from: asPlayed[0].initialPosition),
        metadata: const PositionMetadata(title: 'Renamed chapter'),
      );
      expect(corrected.solution, isNot(asPlayed[0].solution));

      final reopened = await harness.repository.loadSession(started.id);

      expect(reopened!.positions.single.solution, asPlayed[0].solution);
      expect(reopened.positions.single.metadata, asPlayed[0].metadata);
      expect(reopened.grades[asPlayed[0].id]!.value, GradeValue.hard);
    });

    test('the review content is the same as when the session ended', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 2);
      final started = await harness.repository.start(positions);
      final attempts = [
        sampleAttempt(positions[0]),
        sampleAttempt(positions[1]),
      ];
      for (final attempt in attempts) {
        await harness.repository.commitAttempt(started.id, attempt);
      }

      final reopened = await harness.repository.loadSession(started.id);

      expect(reopened!.record.status, SessionStatus.complete);
      expect(reopened.attempts[positions[0].id], attempts[0]);
      expect(reopened.attempts[positions[1].id], attempts[1]);
      expect(reopened.positions.map((p) => p.solution).toList(),
          positions.map((p) => p.solution).toList());
    });

    test('an unknown id is null, not an error', () async {
      final harness = RepositoryHarness.create();
      expect(await harness.repository.loadSession('nothing'), isNull);
    });
  });

  group('invariant 6 (read) — an abandoned session hands back no answers', () {
    test('its snapshots come back with no solution and no metadata', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 3);
      final started = await harness.repository.start(positions);
      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[0]));

      await harness.repository.abandon(started.id);
      final reopened = await harness.repository.loadSession(started.id);

      expect(reopened!.record.status, SessionStatus.abandoned);
      expect(reopened.answersForfeited, isTrue);
      for (final snapshot in reopened.positions) {
        expect(snapshot.solution, isNull,
            reason: 'the answers are gone, not hidden by the UI (FR-016)');
        expect(snapshot.metadata, isNull);
      }
      // Including the position that was committed before abandoning.
      expect(reopened.attempts, isEmpty);
      expect(reopened.grades, isEmpty);
    });

    test('the rows are still there — it is the reading that forfeits them',
        () async {
      final harness = RepositoryHarness.create();
      final started = await harness.repository.start(samplePositions());
      await harness.repository.abandon(started.id);

      // The snapshot survives as a record of what the session contained; what
      // never happens is handing it back out.
      expect(await harness.rawPositions(), isNotEmpty);
    });
  });

  group('deleting everything (FR-018)', () {
    test('removes every session, snapshot, attempt and grade', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 2);
      final started = await harness.repository.start(positions);
      await harness.repository
          .commitAttempt(started.id, sampleAttempt(positions[0]));
      await harness.repository.recordGrade(started.id,
          Grade(positionId: positions[0].id, value: GradeValue.good));

      await harness.repository.deleteEverything();

      expect(await harness.rawSessions(), isEmpty);
      expect(await harness.rawPositions(), isEmpty);
      expect(await harness.rawAttempts(), isEmpty);
      expect(await harness.rawGrades(), isEmpty);
      expect(await harness.repository.listSessions(), isEmpty);
      expect(await harness.repository.loadInProgress(), isNull);
    });

    test('leaves a database a new session can start against', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());
      await harness.repository.deleteEverything();

      final fresh = await harness.repository.start(samplePositions());
      expect(fresh.record.status, SessionStatus.inProgress);
    });
  });

  group('a long history stays usable (SC-009)', () {
    test('the first page of 200 stored sessions comes back quickly', () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 3);

      // Seeded synthetically rather than waiting a year for real history
      // (research, "Open items"). Each session is a full one: three snapshots,
      // three committed trees, three grades.
      for (var i = 0; i < 200; i++) {
        final started = await harness.repository.start(
          positions,
          now: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
        );
        for (final position in positions) {
          await harness.repository
              .commitAttempt(started.id, sampleAttempt(position));
          await harness.repository.recordGrade(started.id,
              Grade(positionId: position.id, value: GradeValue.good));
        }
      }

      final stopwatch = Stopwatch()..start();
      final firstPage = await harness.repository.listSessions(limit: 50);
      stopwatch.stop();

      expect(firstPage, hasLength(50));
      // The budget is the app opening in two seconds; a page of the list is a
      // fraction of that, and the margin is what makes this a useful alarm
      // rather than a flaky one.
      expect(stopwatch.elapsedMilliseconds, lessThan(500),
          reason: 'listing the first page of a 200-session history took '
              '${stopwatch.elapsedMilliseconds}ms');
    });

    test('one session out of 200 is loaded without reading the rest',
        () async {
      final harness = RepositoryHarness.create();
      final positions = samplePositions(count: 1);
      String? middle;

      for (var i = 0; i < 200; i++) {
        final started = await harness.repository.start(
          positions,
          now: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
        );
        await harness.repository
            .commitAttempt(started.id, sampleAttempt(positions[0]));
        if (i == 100) middle = started.id;
      }

      final stopwatch = Stopwatch()..start();
      final reopened = await harness.repository.loadSession(middle!);
      stopwatch.stop();

      expect(reopened, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });
  });

  group('invariant 8 — unreadable stored data is absent, not fatal', () {
    test('a truncated solution PGN', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());
      await harness.corrupt(
        "UPDATE session_positions SET solution_pgn = '[FEN \"8/8/8' ",
      );

      expect(await harness.repository.loadInProgress(), isNull);
    });

    test('an unparseable initial FEN', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());
      await harness.corrupt(
        "UPDATE session_positions SET initial_fen = 'not a position'",
      );

      expect(await harness.repository.loadInProgress(), isNull);
    });

    test('metadata that is not JSON', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());
      await harness.corrupt(
        "UPDATE session_positions SET metadata_json = '{oops'",
      );

      expect(await harness.repository.loadInProgress(), isNull);
    });

    test('a status this app never wrote', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());
      await harness.corrupt("UPDATE sessions SET status = 'in_progress '");

      expect(await harness.repository.loadInProgress(), isNull);
    });

    test('a session row whose snapshots are gone', () async {
      final harness = RepositoryHarness.create();
      await harness.repository.start(samplePositions());
      await harness.corrupt('DELETE FROM session_positions');

      // Nothing to resume into, and nothing thrown at the player either.
      final loaded = await harness.repository.loadInProgress();
      expect(loaded?.positions ?? const [], isEmpty);
    });

    test('an empty database is simply empty', () async {
      final harness = RepositoryHarness.create();
      expect(await harness.repository.loadInProgress(), isNull);
    });
  });
}
