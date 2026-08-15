import 'package:chess_trainer/data/lichess/study_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lichess-api invariant 9.
///
/// A study id is exactly 8 characters — the OpenAPI spec pins it at
/// `minLength: 8, maxLength: 8` — so these checks are exact rather than
/// approximate (003 research D8).
void main() {
  group('what counts as a study address', () {
    test('a study URL', () {
      expect(parseStudyId('https://lichess.org/study/9LjyYZ9N'), '9LjyYZ9N');
    });

    test('a chapter URL yields the study, not the chapter', () {
      // Pasting a chapter link is natural, and importing the whole study is
      // more useful than an error — the player sees what came in either way.
      expect(
        parseStudyId('https://lichess.org/study/9LjyYZ9N/FXMbkAeX'),
        '9LjyYZ9N',
      );
    });

    test('a bare id', () {
      expect(parseStudyId('9LjyYZ9N'), '9LjyYZ9N');
    });

    test('surrounding whitespace, as a paste usually carries', () {
      expect(parseStudyId('  https://lichess.org/study/9LjyYZ9N \n'),
          '9LjyYZ9N');
    });

    test('without a scheme', () {
      expect(parseStudyId('lichess.org/study/9LjyYZ9N'), '9LjyYZ9N');
    });

    test('with a query string or fragment', () {
      expect(parseStudyId('https://lichess.org/study/9LjyYZ9N?page=2'),
          '9LjyYZ9N');
    });
  });

  group('what does not', () {
    test('a game URL', () {
      expect(parseStudyId('https://lichess.org/abcdefgh'), isNull);
    });

    test('a profile URL', () {
      expect(parseStudyId('https://lichess.org/@/thibault'), isNull);
    });

    test('another site that happens to have /study/ in the path', () {
      expect(parseStudyId('https://example.com/study/9LjyYZ9N'), isNull);
    });

    test('an id of the wrong length', () {
      expect(parseStudyId('9LjyYZ9'), isNull);
      expect(parseStudyId('9LjyYZ9NX'), isNull);
      expect(parseStudyId('https://lichess.org/study/9LjyYZ9'), isNull);
    });

    test('empty input', () {
      expect(parseStudyId(''), isNull);
      expect(parseStudyId('   '), isNull);
    });

    test('an id with characters a study id cannot contain', () {
      expect(parseStudyId('9Ljy-Z9N'), isNull);
    });
  });
}
