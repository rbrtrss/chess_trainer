/// Getting a study id out of whatever the player pasted.
///
/// A Lichess study id is exactly 8 characters — the OpenAPI spec pins it at
/// `minLength: 8, maxLength: 8` — so this check is exact rather than a guess
/// (003 research D8).
library;

/// Matches a study id in a study URL, a chapter URL, or on its own.
///
/// A chapter URL (`/study/{studyId}/{chapterId}`) is a natural thing to paste,
/// and taking the study id from it and importing the whole study is more useful
/// than an error — the player sees what came in either way.
final RegExp _inUrl = RegExp(
  r'(?:^|[./])lichess\.org/study/([A-Za-z0-9]{8})(?:[/?#]|$)',
  caseSensitive: false,
);

final RegExp _bareId = RegExp(r'^[A-Za-z0-9]{8}$');

/// The study id in [input], or null if there is not one.
///
/// Null rather than a throw, so the caller can say what kind of address was
/// expected — a game link, a profile, or another site each land here and each
/// deserve that message rather than a parse failure.
String? parseStudyId(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  if (_bareId.hasMatch(trimmed)) return trimmed;

  final match = _inUrl.firstMatch(trimmed);
  return match?.group(1);
}
