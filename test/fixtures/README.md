# Test fixtures

Real Lichess study exports, fetched 2026-08-14 and committed on purpose. The constitution's
testing floor requires study PGN → training position extraction to be tested "against real
fixture files", because the failures that matter are the ones a hand-written fixture would never
contain: headers nobody anticipated, `[Variant "From Position"]`, chapters with no starting
position, and annotation styles we did not invent.

All three are public studies, fetched with the same query string the app uses:

```bash
curl -s 'https://lichess.org/api/study/{id}.pgn?clocks=false&comments=true&variations=true'
```

| File | Study | Why it is here |
|---|---|---|
| `study_multi_chapter.pgn` | [`9LjyYZ9N`](https://lichess.org/study/9LjyYZ9N) — "FIDE World Rapid & Blitz 2025 - Puzzle Pack" by Lichess | 33 chapters, **every one** with a `[FEN]`, with real annotator comments and variations. The happy path, at a realistic size |
| `study_mixed_chapters.pgn` | [`55NSdxBQ`](https://lichess.org/study/55NSdxBQ) — "Puzzles" by thibault | 11 chapters, 8 with a `[FEN]` and 3 without. The rejection report's main case, on real content |
| `study_variant.pgn` | [`1wzY0YmD`](https://lichess.org/study/1wzY0YmD) — "Sunsetter" by thibault | Crazyhouse. Must be rejected as an unsupported variant, not trained as standard chess |
| `hostile_metadata.pgn` | Authored here | Every text-carrying field filled with a sentinel, for the Principle I guard |

## What the real exports taught us

Two things in these files contradicted what the plan assumed, and both are now in the code:

1. **`[Variant "From Position"]` is what Lichess writes for a chapter set up from a FEN** — that
   is, for exactly the chapters this app wants. Treating anything but `"Standard"` as an
   unsupported variant would have rejected every usable chapter in `study_multi_chapter.pgn`.
2. **`[StudyName]` and `[ChapterName]` are real headers**, and `[ChapterName]` is literally the
   "Chapter 3: Winning the Opposition" case the constitution names. Neither was in the five
   fields feature 001 knew about, which is the clearest argument for the header bag (research
   D11): the allowlist was already incomplete on the first real file we tried.

## Refreshing them

Don't, unless a test needs something they lack. These are inputs to assertions with exact counts
(33 chapters, 8 of 11 usable); re-fetching a study whose author has since edited it will fail
tests for reasons that have nothing to do with the code.
