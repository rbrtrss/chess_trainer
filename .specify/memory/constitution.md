# Chess Trainer Constitution

Chess Trainer is an Android app for calculation training. It shows a position, lets the
user lay out their entire analysis as a tree of variations for both colours, and reveals
nothing until the whole session is over. Positions come from Lichess studies and puzzles,
cached for offline use.

These principles govern every specification, plan, and implementation in this repository.

## Core Principles

### I. Delayed Feedback Is Inviolable (NON-NEGOTIABLE)

No part of the training experience may signal whether a move is good, bad, expected, or
unexpected before the session reaches its review phase. This is not a UX preference; it is
the entire product thesis. Every mainstream puzzle app already does the opposite, and the
instant green-check/red-cross loop is precisely the habit this app exists to break.

Concretely, during the training phase the app MUST NOT vary any of the following based on
the correctness of the user's input: colour, icon, sound, haptic, animation, arrow, board
highlight, move-list styling, progress indicator, latency, or wording.

Position metadata is *evidence* and is therefore withheld: puzzle themes, puzzle ratings,
study chapter titles, comments, NAGs, and evaluation glyphs MUST be stored but MUST NOT be
rendered on any training screen. "Chapter 3: Winning the Opposition" tells the user the
answer. So does a `!!` glyph. So does the word "mate" anywhere on screen.

The user is told exactly one thing about the position: **whose turn it is.** Not whether a
win exists, not whether the goal is to win or to hold, not how long the solution is.

Any proposed feature that risks leaking correctness MUST be rejected at specification time
rather than mitigated at implementation time. When in doubt, the answer is no.

### II. Offline-First

Every training and review path MUST function with no network connection. Content is
fetched and cached ahead of time; training reads only from local storage.

Network access is confined to explicit, user-initiated sync operations. Network code lives
behind repository interfaces in the data layer and MUST NOT be reachable from the domain
or UI layers. No screen may block on a network call to render. A failed sync degrades to
"no new positions", never to a broken session.

### III. Chess Correctness Is Delegated

`dartchess` is the single source of truth for move legality, position state, FEN, SAN, and
PGN parsing. Hand-rolled move generation, FEN parsing, or PGN parsing is prohibited —
these are solved problems with a long tail of edge cases (en passant, castling rights,
promotion, repetition, PGN variation nesting) that we will get wrong.

`chessground` is the single board rendering and interaction surface. It holds no chess
logic by design; game state is owned by our domain layer and handed to it.

### IV. Layered Architecture

Three layers, dependencies pointing strictly inward:

- `lib/domain/` — pure Dart. Zero Flutter imports, zero I/O, zero platform calls. The move
  tree, tree comparison, session state machine, and spaced-repetition scheduler live here
  and are testable with `dart test` on any machine with no device or emulator.
- `lib/data/` — repositories, local database, Lichess API client, OAuth, secure storage.
  Depends on domain. Exposes interfaces, not implementations.
- `lib/ui/` — widgets, screens, state management. Depends on both, and reaches data only
  through repository interfaces.

The domain layer is where the interesting logic lives, so the domain layer is where the
tests live. If a rule is hard to unit-test, it is in the wrong layer.

### V. Testing Floor

The following REQUIRE unit tests before their feature is considered complete:

- Move tree construction, navigation, and branching
- Tree-vs-tree comparison and the match indicator
- Session state machine transitions
- Spaced-repetition scheduling intervals
- Lichess puzzle ply-offset handling (see Technology Constraints)
- Study PGN → training position extraction, against real fixture files

The tree editor's branching behaviour REQUIRES widget tests: rewinding and playing an
alternative move must create a sibling branch while leaving the original line intact.

Principle I REQUIRES a guard test asserting that no correctness signal is reachable from
the training screen's widget tree. This is the one defect class that destroys the product's
value while every test still passes and the app still looks fine.

## Technology & Licensing Constraints

**Stack.** Flutter + Dart, Android-first. Riverpod for state, Drift for local persistence.
iOS is out of scope but MUST NOT be actively precluded by platform-specific choices.

**Licensing.** This project is GPL-3.0. `chessground` and `dartchess` are GPL-3.0, and
this is a deliberate, accepted consequence of using them — they are the Lichess team's own
packages and give us a variation-aware PGN parser and a production chessboard for free.
Every new dependency MUST be license-checked for GPL-3.0 compatibility before adoption.
Adding an incompatible dependency is a constitution violation, not a minor issue.

**Lichess API.** Two facts drive design and are easy to get wrong:

1. Lichess issues long-lived access tokens (~1 year) and **no refresh tokens**. Token
   expiry MUST be handled as "log in again", never as silent refresh. Do not build a
   refresh path; it cannot work.
2. A Lichess puzzle's FEN is the position *before* the opponent's setup move, and the
   first move of the solution is that opponent move. The trainable position is the one
   reached *after* applying solution move 1. Getting this wrong shifts every puzzle by one
   ply — silently, and for every puzzle in the database.

OAuth uses PKCE with S256, a public client id, and no client secret. Rate limiting (HTTP
429) MUST be respected with backoff.

**Secrets.** No credentials, tokens, or keystores in the repository. Tokens live in
`flutter_secure_storage`. The OAuth client id is public by design and may be committed.

## Development Workflow

Work proceeds through Spec Kit cycles, one numbered feature at a time under `specs/`:

`/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` →
`/speckit-implement`

Specifications describe *what* and *why*; plans describe *how*. A specification that
cannot state how it upholds Principle I is not ready for planning.

Features are sequenced so that the riskiest, least proven idea is validated first. The
delayed-feedback training loop is unproven as a product; it is built first, on bundled
sample positions, before any network or persistence code exists. There is no point
building OAuth for a training loop that turns out to feel bad to use.

## Governance

This constitution supersedes other practices and conventions in this repository. Where a
plan, task, or piece of code conflicts with it, the constitution wins and the conflicting
work is revised.

Principle I is non-negotiable and MUST NOT be amended to accommodate a feature. Any other
amendment requires: a written rationale recorded in this file's history, a version bump per
the scheme below, and a review of open specifications for consequences.

Versioning is semantic: MAJOR for removing or redefining a principle, MINOR for adding a
principle or section, PATCH for clarifications that change no requirement.

Complexity MUST be justified against the goal. This is a personal training tool first; a
Play Store release is a possible future, not a current requirement, and MUST NOT be used
to justify speculative architecture today. The bar for added complexity is a concrete
problem, not an anticipated one.

**Version**: 1.0.0 | **Ratified**: 2026-08-12 | **Last Amended**: 2026-08-12
