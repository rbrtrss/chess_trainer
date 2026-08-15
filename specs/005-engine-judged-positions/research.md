# Phase 0 Research: Positions With No Author's Line

**Feature**: [spec.md](./spec.md) | **Date**: 2026-08-15

The specification left three questions to planning, and named them: what supplies the evaluation,
when it runs, and whether the constitution needs amending. The first two are settled below by
facts rather than preference — one API's documented behaviour rules out the obvious cheap option,
and one principle rules out the obvious convenient one. The third is a recommendation the owner
has to accept or refuse.

Decisions are numbered so tasks and code comments can cite them.

---

## D1: The evaluation must come from an engine on the device

**Decision.** Bundle a chess engine in the app. Do not use a remote evaluation service.

**Rationale.** The cheap option would be Lichess's cloud evaluation endpoint — no binary, no app
size, and this app already talks to Lichess. It cannot work, and the reason is in the endpoint's
own description: it returns *"the cached evaluation of a position, **if available**"*, and answers
`404` when the position is not in Lichess's analysis cache.

The cache holds positions many people have analysed. **The positions this feature exists to serve
are the opposite of that**: a position a player set up by hand, in their own study, this
afternoon, to think about. It is precisely the position nobody else has ever analysed. Using
cloud eval here would fail for the exact input the feature was requested for.

Add FR-008 — the evaluation must be readable at review with no network — and a device-side engine
is not a preference, it is the only thing left.

**Alternatives considered.**

- *Lichess cloud eval.* Rejected above, on the endpoint's documented coverage.
- *Lichess tablebase API.* Exact and free, but only for endgames of seven pieces or fewer, and it
  needs a network. Useful for a minority of positions and no help for the rest; two sources to
  maintain and reconcile.
- *Fetch an evaluation at import and keep it.* Satisfies "offline at review" — but there is
  nothing to fetch, per D1's first paragraph. This option only exists if a remote source could
  answer, and none can.
- *Ask the player to enter at least one move.* This is the feature refusing to exist.

---

## D2: The engine runs at import, and never while a session exists

**Decision.** Positions are evaluated during import, as part of the import job, and the result is
stored with the position. No engine process is started during training or review.

**Rationale.** FR-017 forbids a training screen varying by evaluation *including latency*, and
FR-019 forbids the player becoming aware of engine work. The tempting design — evaluate while the
player is thinking, so the answer is ready when they commit — puts a native chess engine at full
tilt on the same device, at the same moment, as a player who must be told nothing. It leaks
through latency, through battery, through the phone getting warm. Those are not hypothetical
channels; they are the channels a person actually notices.

The verified package facts make it worse: the engine runs as **two additional isolates**, and only
one engine instance may exist at a time. So "just run it quietly in the background" is a
concurrency design with a single shared resource, competing with the UI, on the one screen where
the app has promised to behave identically no matter what.

Evaluating at import removes the question rather than managing it. Import is already the app's
explicit, slow, progress-bearing operation — the player asked for it, waits for it, and watches it
work (003 D15, D16). **After import, the engine is not running, so it cannot leak.** That is a
structural guarantee of the same kind D1 in feature 004 bought for the account read, and it is
worth more than any amount of care in a background scheduler.

**Alternatives considered.**

- *Evaluate lazily at review.* No Principle I risk — training is over — but it puts a multi-second
  wait between the player finishing and seeing anything, and FR-009 forbids a session waiting on
  an evaluation to finish. It also makes review impossible to test without a device.
- *Evaluate in the background after import, positions trainable meanwhile.* Sound in principle,
  and FR-010 already defines the not-yet-evaluated case. Rejected as premature: it adds a
  scheduler, a partial state and a race, to solve an import-duration problem that has not been
  measured. If import turns out to be intolerably slow, this is the first thing to reach for, and
  it can be added without changing anything the player sees.
- *Evaluate during training.* Rejected on Principle I, above. It should not be reconsidered.

---

## D3: The engine's line becomes the solution, and review does not change

**Decision.** At import, the engine's principal variation is stored as the position's `solution`,
in the same `VariationTree` an author's line produces. Review, comparison and grading are
untouched.

**Rationale.** This is the decision that makes the feature small. `TrainingPosition` already
carries `solution` as a `VariationTree`, and everything downstream — the review screen's two
panes, `compareTrees`, the match indicator, the self-grade — consumes that and nothing else. If
the engine's line arrives in that shape, then:

- FR-012, showing the engine's preferred line, is already built.
- FR-013, saying where the player's line parts from it, is `compareTrees`, unchanged since 001.
- FR-015, authored positions being presented exactly as before, is true because nothing on that
  path is touched.
- FR-020, keeping the evaluation out of the training layer's reach, is inherited: training
  consumes `TrainingProjection`, which has never carried the solution and gains nothing here.

The alternative is a second review path for engine-judged positions, with its own comparison, its
own screen states and its own Principle I surface. That is a great deal of new code, and every
line of it would be new opportunity to leak.

**What this does change.** The word "solution" stops meaning "what the author intended" and starts
meaning "the standard this attempt is measured against". Feature 001's comparison documents itself
as advisory *because* "no engine evaluates anything here". After this feature one kind of position
has an engine behind its solution and one does not, and the review has to be honest about which —
see D5.

---

## D4: A fixed-depth, single-threaded search — and storage is what makes it reproducible

**Decision.** Search to a fixed depth with `Threads` set to 1. Store the result. Never re-run the
engine for a position that has one.

**Rationale.** SC-008 requires that reviewing the same position twice says the same thing.

It is tempting to get that from the engine — but a time-limited search returns different lines on
a busy phone than on an idle one, and a multi-threaded search is not deterministic even at fixed
depth, because threads race to fill the shared table. A fixed depth on one thread is reproducible
for a given binary and network file.

**But that is not what satisfies SC-008.** What satisfies it is that the result is *stored at
import and read thereafter*. Even a perfectly deterministic engine would break SC-008 across an
app update that changed the engine version or its network file, because the same position would
then evaluate differently. Storing decouples the player's history from the engine's version
entirely: a position reviewed today and in a year says the same thing, because it is the same
recorded answer, not the same computation.

Determinism is still worth having, for a smaller reason: it makes the device tests repeatable.

---

## D5: What is stored, and how review admits where it came from

**Decision.** For an engine-judged position, store:

- the principal variation as the `solution` tree, capped at a fixed number of plies;
- the evaluation at the starting position, in a form that can express both a centipawn score and
  a forced mate;
- the fact that the solution came from an engine, and the search budget it came from.

The last of these is shown at review and never at training.

**Rationale.** FR-012 and FR-013 need the line and the assessment. The provenance is needed
because of what D3 changes: two positions can look identical at review while one is measured
against a human's intention and the other against a machine's preference, and the player is
entitled to know which. It is also the honest thing to do with a line that is *correct* rather
than *instructive* — an engine's first choice is often not what a human would call the point of
the position.

Recording the budget matters for the same reason a scientist records their instrument: a
depth-20 line and a depth-8 line are different claims, and a position imported by an old build
should not silently be compared with one imported by a new one.

**The cap on the line's length** is a judgement. Authored solutions in this app run to about nine
moves. A principal variation forty plies deep is mostly the engine talking to itself, and showing
it as "the solution" would misrepresent how much of it is meaningful. Capping keeps the review
readable and the stored tree small; the exact number is set in the contract and is not
interesting.

---

## D6: The no-evaluation case already has somewhere to land

**Decision.** A position whose evaluation could not be produced is imported with an empty
solution. Review shows its existing empty state.

**Rationale.** FR-010 requires that such a position stay trainable and that review say so plainly.
`tree_comparison_view.dart` already renders an empty solution pane with **"No solution was
recorded."** — written for a case that could not previously occur, and exactly right for one that
now can.

That wording gets revisited during implementation, because "not recorded" is now one of two
different situations: the engine was not asked, and the engine was asked and could not answer. The
player should be told which, in the same style every other message in this app is written: what
happened, and what they can do about it.

---

## D7: The engine lives in one directory, and nothing outside it knows

**Decision.** All engine code lives under `lib/data/engine/`. `lib/domain/` and `lib/ui/` never
import it. A layering rule enforces this, in the same shape as the rule that confines networking
to `lib/data/lichess/`.

**Rationale.** The engine is platform code — a native binary reached over FFI, with process state
and a UCI text protocol. It is exactly what the constitution's layering principle exists to keep
out of the domain, and it is a second thing after networking that the training layer must be
provably unable to touch.

The training-directory rule in `layering_test.dart` grows to forbid the engine's identifiers as
well, for the reason feature 004 gave when it added the account: the rule is written before the
temptation, not after.

---

## D8: The engine sits behind an interface because tests cannot load it

**Decision.** Define the evaluator as an interface in the data layer. Everything except one
implementation class depends on the interface. Tests use a fake that returns canned lines.

**Rationale.** This is not architectural taste; it is forced. The package supports **Android and
iOS only**, and `flutter test` runs on the host VM, so a test that touched the real engine could
not run at all — not in CI, not on the development machine.

The same arrangement the Lichess client already has: every test drives a fake, one device task
exercises the real thing, and the seam is where the fake goes. It also means the import pipeline
can be tested for the shape of what it produces without an engine anywhere in sight.

---

## D9: Terminal positions are rejected, and dartchess decides that

**Decision.** A position with no legal move — checkmate, stalemate, or any other terminal state —
is rejected at import with a stated reason. `dartchess` answers the question; the engine is not
consulted.

**Rationale.** FR-004. There is nothing to calculate, so there is nothing to train, and importing
it would produce a position that opens to a board the player cannot move on. Principle III makes
this dartchess's judgement rather than ours.

This is a *new rejection* inside a feature whose purpose is to reject less, which is why the
specification's checklist flagged it as the judgement most worth pushing back on. It stays because
the alternative is worse: a position that imports and then cannot be trained is a trap, and the
import report exists to say what could not be used and why.

---

## D10: The size cost, measured — and it changes the decision

**Measured on 2026-08-15**, before anything was built, which is what this decision was gated on.
`multistockfish` (lichess.org, v0.5.0, GPL-3.0) was added to `pubspec.yaml`, release APKs were
built, and the package was then removed again.

| Build | Baseline | With `multistockfish` | Delta |
|---|---|---|---|
| Universal APK | 75.1 MB | **208.4 MB** | +133 MB |
| arm64 split APK — what a phone downloads | **34.9 MB** | **79.7 MB** | **+44.8 MB, ×2.3** |

The universal figure is misleading and the split figure is the honest one: a real install takes one
ABI. Inside the arm64 APK:

| Library | Size | What it is |
|---|---|---|
| `libmultistockfish_sf16.so` | **39.5 MB** | Stockfish 16 **with the NNUE network embedded** |
| `libmultistockfish_variant.so` | 1.7 MB | Fairy-Stockfish — for chess variants this app rejects |
| `libmultistockfish_chess.so` | **1.5 MB** | Stockfish for chess and chess960, **without an embedded network** |

**The 1.5 MB line is the finding.** Almost the entire cost is one embedded neural network, and the
flavour that matches this app's scope exactly — standard chess, which is all it will ever
train — is a rounding error by comparison. `multistockfish` pulls all three flavours whether or
not they are used, which is why the naive measurement is so bad.

**So the choice is not "engine or no engine". It is which network, and where it lives:**

| Option | Install cost | Consequence |
|---|---|---|
| **Embedded network** (sf16) | +44.8 MB, app goes 34.9 → 79.7 MB | Works offline from the moment it is installed, forever. No new network path — the feature keeps the property that made D1 clean |
| **Network file fetched once** (chess flavour) | ≈ +1.5 MB | The evaluation needs a one-time download before the first import that uses it. A player who installs the app on a plane and imports a file has no evaluation until they are next online |

**Decided by the owner on 2026-08-15: embed the network.** The app goes from 34.9 MB to 79.7 MB
per install, and in exchange this feature adds **no network path whatsoever** — evaluation works
from the moment the app is installed, including on a phone that has never been online. That keeps
the property which made D1's argument clean in the first place, and it keeps faith with the
file-import path feature 003 deliberately built to need no network at all.

`multistockfish` is adopted, defaulting to the `sf16` flavour, which is the one with the network
embedded. The dependency is in `pubspec.yaml` with the measurement recorded beside it.

### Seconds per position — measured 2026-08-15 on the TECNO KJ6

Five positions spanning what this feature will actually be handed, from a bare king-and-pawn
ending to a dense middlegame, at four depths, `Threads` at 1. Milliseconds from `go` to
`bestmove`:

| Depth | K+P ending | rook ending | smothered mate | open middlegame | closed middlegame | **worst** |
|---|---|---|---|---|---|---|
| 8 | 7 | 9 | 12 | 43 | 11 | **43** |
| 12 | 29 | 90 | 18 | 257 | 39 | **257** |
| 16 | 73 | 1012 | 1 | 1249 | 265 | **1249** |
| 20 | 90 | 1732 | 1 | 2590 | 2544 | **2590** |

**Depth 12 is the choice**, and the worst case is what chose it: 257 ms. Depth 16 costs 1.25 s on
the position that hurts most and depth 20 costs 2.6 s, which is past the line T003 drew — a study
of a hundred hand-made positions would take two minutes at depth 16 and four at depth 20. At depth
12 the same import spends about 26 seconds in the engine, worst case, on top of the parse.

**The mean is not the number to design against.** At depth 12 it is 87 ms, which would suggest
depth 16 is affordable; the worst case says otherwise, and an import is only as fast as its
slowest entry.

**A property worth keeping.** The smothered-mate position costs 1 ms at depths 16 and 20 because
the search stops the moment it proves a forced mate. Hand-made tactical positions — the most
likely thing a player sets up to practise — are the cheapest ones the engine will be given.

**Still unknown**: the cost of transferring 330 evaluated positions out of the isolate, which
feature 003's D15 flagged for parsing and which applies here too. It will be visible the first
time a large import runs on the device (T042).

**A second question this raises**, for planning rather than now: whether the two unused flavours
can be excluded. `multistockfish_chess` publishes "only the C++ dynamic library interface, and not
the dart bindings", so using it alone means writing the bindings this project would otherwise get
for free. Worth an hour of investigation before accepting either number above.

## D11: The constitution was amended — v1.1.0, 2026-08-15

**Decision.** A MINOR amendment adding the engine to Principle III and to Technology Constraints.
**Made on 2026-08-15, by the owner**, following the document's own procedure: a written rationale,
a version bump, and a review of open specifications for consequences.

**Rationale.** The constitution's Technology & Licensing Constraints name Flutter, Dart, Riverpod,
Drift, `chessground` and `dartchess`, and require that **every new dependency be licence-checked
for GPL-3.0 compatibility before adoption**. The licence check passes: the package is GPL-3.0, the
same licence as this project and as the two Lichess packages it already depends on, adopted for
the same reason.

What was not covered was the engine's *standing*. Principle III said `dartchess` is the single
source of truth for move legality and that hand-rolled chess logic is prohibited; an engine is a
second piece of delegated chess authority, of a different kind — not what is legal, but what is
good. That is a genuine addition to the technology the project is built on, and it arrived through
the document rather than through a `pubspec.yaml` diff.

**What the amendment added beyond naming the dependency**, and what implementation is now bound by:

- `dartchess` says what is legal; the engine says what is good. The engine **MUST NOT** be asked
  about legality or terminal positions — one question, one source of truth. This makes D9 a
  constitutional requirement rather than a design preference.
- The engine **MUST NOT** run while a training or review session exists. D2 is now constitutional.
- Evaluations **MUST** be computed once and stored. D4's conclusion is now constitutional.
- Engine code **MUST** live in one directory, unreachable from domain and UI. D7, likewise.

**The review of open specifications turned up four consequences**, recorded in the amendment
history. The one worth repeating here: feature 001 justified the self-grade's authority with
"because no engine evaluates the user's moves, the app cannot judge lines the solution does not
contain". That premise dies with this feature. The self-grade stays authoritative — 005 FR-014
requires it — but it now rests on **a choice rather than on incapacity**, which is a stronger
position and a harder one to keep. Two source comments saying the same thing become false when
this feature lands and are listed for correction.

**One thing the constitution already anticipated.** Principle I's list of withheld evidence names
"puzzle themes, puzzle ratings, study chapter titles, comments, NAGs, and **evaluation glyphs**".
The document already treats an evaluation as evidence to be stored and not rendered. This feature
does not introduce that idea; it introduces the first evaluation the app produces itself.

---

## Verified facts

Checked on 2026-08-15 rather than recalled.

| Fact | Source | Consequence |
|---|---|---|
| Lichess cloud eval returns "the cached evaluation of a position, if available", `404` otherwise | [Lichess API docs](https://lichess.org/api#operation/apiCloudEval), [forum](https://lichess.org/forum/lichess-feedback/database-of-all-lichess-cloud-evaluations) | D1 — cannot serve player-authored positions |
| `stockfish` on pub.dev: publisher `arjanaswal.com` (verified), v1.8.1, GPL-3.0, **Android and iOS only**, deps `ffi` and `logging`, not discontinued | [pub.dev/packages/stockfish](https://pub.dev/packages/stockfish) | Licence check passes; D8 — host tests cannot load it |
| Lichess maintain their own fork, `lichess-org/dart-stockfish` | [github.com/lichess-org/dart-stockfish](https://github.com/lichess-org/dart-stockfish) | A second candidate, from the same team as `dartchess` and `chessground`; pick during setup |
| The engine runs as two additional isolates, and only one instance may exist at a time | [dart-stockfish README](https://github.com/lichess-org/dart-stockfish) | D2 — a background engine is a shared-resource design competing with the UI |
| Lichess publish a `multistockfish` family on pub.dev — `multistockfish` (bindings, v0.5.0), and `_chess`, `_sf16`, `_variant` libraries. GPL-3.0, Android and iOS | [pub.dev/packages/multistockfish](https://pub.dev/packages/multistockfish) | The strongest candidate: same publisher as `dartchess` and `chessground`, and the one Lichess's own mobile app uses |
| Adding `multistockfish` takes the arm64 split APK from **34.9 MB to 79.7 MB**; `libmultistockfish_sf16.so` is **39.5 MB** and `libmultistockfish_chess.so` is **1.5 MB** | Measured here, 2026-08-15 | D10 — the cost is one embedded network, not the engine |

## What this feature does not research

- **Scheduling.** Still deferred, still out of scope.
- **How `dartchess` parses or validates anything.** Unchanged, and Principle III keeps it that way.
- **The import pipeline's shape.** Feature 003's parser, caps and isolate arrangement are reused as
  they stand; this feature adds a step to it, not a replacement for it.
- **Which engine version or network file.** A setup decision, made against the measurement D10
  requires, not a design one.
