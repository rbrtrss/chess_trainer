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

**Stockfish, through `multistockfish`, is the single source of position evaluation.**
Hand-rolled evaluation, heuristics that score a move, and "good enough" approximations of
what a strong player would choose are prohibited for the same reason hand-rolled move
generation is: we would get them wrong, and the wrongness would be invisible.

These two authorities divide cleanly and MUST stay divided. **`dartchess` says what is legal;
the engine says what is good.** The engine MUST NOT be consulted about legality, terminal
positions, or anything `dartchess` can answer — one question, one source of truth. The
engine MUST NOT be consulted at all where a study author supplied a line; an author's
intention outranks a machine's preference, and the engine exists to supply a standard only
where none was given.

Three constraints follow, and they are constitutional rather than incidental:

- **The engine MUST NOT run while a training or review session exists.** Evaluation happens
  at import. This is not a performance rule; it is how Principle I is kept structurally. A
  search running beside a player who is calculating leaks through latency, battery and heat,
  and none of those channels can be caught by a widget test.
- **Evaluations MUST be computed once, stored, and read thereafter.** Never recomputed for
  display. A player's history must not change because the engine was upgraded.
- **Engine code MUST live in one directory** and be unreachable from the domain and UI
  layers, on the same terms as networking.

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

**Stack.** Flutter + Dart, Android-first. Riverpod for state, Drift for local persistence,
`multistockfish` for position evaluation. iOS is out of scope but MUST NOT be actively
precluded by platform-specific choices.

**Licensing.** This project is GPL-3.0. `chessground`, `dartchess` and `multistockfish` are
GPL-3.0, and this is a deliberate, accepted consequence of using them — they are the Lichess
team's own packages and give us a variation-aware PGN parser, a production chessboard and a
world-class engine for free.
Every new dependency MUST be license-checked for GPL-3.0 compatibility before adoption.
Adding an incompatible dependency is a constitution violation, not a minor issue.

**The engine, and what it costs.** `multistockfish` is the most expensive dependency in this
project and the price was measured before it was paid: the arm64 install goes from 34.9 MB to
79.7 MB. Almost all of that is one embedded neural network — 39.5 MB of it — against 1.5 MB
for the same engine with no network inside.

Embedding was chosen over downloading that network on first use, which would have cost about
1.5 MB. The reason is Principle II and nothing else: **an embedded network means this app
evaluates positions on a phone that has never been online**, and the alternative would have
put a network dependency into the one content path deliberately built to need none. Any future
proposal to shrink the app by fetching the network is a proposal to weaken Principle II, and
MUST be argued as one.

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

## Amendment History

### 1.1.0 — 2026-08-15 — the engine

**Added**: Stockfish, via `multistockfish`, as a second delegated chess authority (Principle
III); the engine's constraints and its measured cost (Technology & Licensing Constraints).

**Rationale.** Feature 005 needs a standard of correctness for positions a study author set up
without one — the app refused such a chapter on a real device on 2026-08-15, which is what
prompted the feature. No remote source can supply it: Lichess's cloud evaluation returns a
cached evaluation "if available" and 404 otherwise, and a position invented this afternoon by
one person is precisely the position nobody has cached. An engine on the device was therefore
not a preference but the only remaining option, and a major dependency arriving in this project
should arrive through this document rather than through a `pubspec.yaml` diff.

**Review of open specifications, as this section's own procedure requires.** Four consequences,
none of which invalidate completed work:

- **001's premise changes, and its conclusion survives.** The specification says "because no
  engine evaluates the user's moves, the app cannot judge lines the solution does not contain.
  This is why the user's self-grade is authoritative." The first sentence stops being true. The
  self-grade remains authoritative — 005 FR-014 requires it — but it now rests on **a choice
  rather than on incapacity**, which is a stronger position to hold and a harder one to keep.
- **001's Out of Scope excluded "any engine evaluation, best-move suggestion, or accuracy
  scoring."** That was true of feature 001 and stays true of it. Feature 005 narrows the
  exclusion to positions with no author's line; everything else — suggestions, accuracy scores,
  an evaluation bar — remains out of scope and is not licensed by this amendment.
- **003's FR-006 is superseded in one clause.** It requires rejecting an entry "with no moves at
  all". Accepting exactly those entries is what 005 exists to do. The other rejections in that
  requirement stand unchanged.
- **Two source comments become false when 005 lands**, and must be corrected rather than left:
  `lib/domain/attempt/comparison.dart` ("no engine evaluates anything here") and
  `lib/ui/review/grade_buttons.dart` ("without an engine there is nothing here that could make
  that suggestion honestly"). Both explain *why* a rule exists, and after 005 the reason changes
  even though the rule does not.

**Not amended**: Principle I, which is non-negotiable and which this amendment strengthens
rather than touches — its list of withheld evidence already named "evaluation glyphs", so the
document anticipated an engine's output as evidence before there was an engine to produce it.

---

**Version**: 1.1.0 | **Ratified**: 2026-08-12 | **Last Amended**: 2026-08-15
