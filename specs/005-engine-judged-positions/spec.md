# Feature Specification: Positions With No Author's Line

**Feature Branch**: `005-engine-judged-positions`

**Created**: 2026-08-15

**Status**: Draft

**Input**: User description: "we need to review the kind of studies that can be imported, a study with a position and no moves (apart from the starting position) should me imported (look at the Probando probando private study) here since all the line is not specified beforehand we need to rely on engine evaluation"

## Overview

Feature 003 decided what a trainable position is, and it drew the line in a way that has turned
out to be too tight in one specific place. A study chapter that sets up a position and stops —
no moves entered, nothing played — is rejected today with "this entry has no moves, so there is
no solution". That rejection was correct given what the app could do: the review screen compares
the player's line against the author's line, so an entry with no author's line could never be
graded.

But setting up a position and stopping is exactly how a player creates an exercise for
themselves. It is what happened on the device on 2026-08-15: a study made by hand for this
purpose imported as *"1 of the 1 entries could not be used: 1 entry has no moves, so there is no
solution."* The app refused the most natural way to author a training position, and the refusal
was honest about the reason — there was nothing to be right about.

This feature supplies the missing thing. Where an author has given no line, an engine's
evaluation stands in for it, so the position becomes trainable and the review has something to
compare against.

**That is a larger change than it looks, and the specification exists to bound it.** Feature
001's comparison carries this sentence in its source:

> Advisory only. The self-grade outranks this, and the reason is structural rather than polite:
> **no engine evaluates anything here**, so this type can say where two lines parted company and
> nothing whatever about which was better.

After this feature that is no longer true. The app gains, for the first time, the ability to say
which move was better — and that ability is precisely what Principle I exists to keep away from
a player who is still calculating. An engine is not a new kind of evidence; it is the strongest
kind the app has ever held.

Two constraints follow, and everything below is shaped by them.

**Principle I.** The evaluation is a solution. It belongs at review and nowhere else. Nothing
about a position having an engine verdict may be visible, audible or *inferable* during
training — including by timing. A position whose analysis is still being computed must not look
or behave differently from one that is finished, because "this one is taking a while" is a
statement about the position.

**Principle II.** Every review path must work with no network. A verdict the player cannot see
on a plane is a verdict the app cannot promise. Whatever supplies the evaluation must therefore
either live on the device or be obtained before it is needed and kept.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Train a position I set up myself (Priority: P1)

The player sets up a position in a Lichess study chapter — a middlegame they want to think
about, an endgame they keep misplaying — and enters no moves. They import the study and the
position is trainable, like any other.

**Why this priority**: This is the feature. It is the reason the request was made, and it is the
most natural way a player authors an exercise for themselves.

**Independent Test**: Import a study containing one chapter with a position and no moves, and
confirm a session can be started on it and completed.

**Acceptance Scenarios**:

1. **Given** a study chapter with a starting position and no moves, **When** the player imports
   it, **Then** it becomes a trainable position rather than a rejected entry.
2. **Given** such a position in a session, **When** the player trains it, **Then** the screen is
   indistinguishable from one showing a position that has an author's line — same controls, same
   wording, same absence of anything about how it will be judged.
3. **Given** a study mixing chapters with lines and chapters without, **When** the player imports
   it, **Then** both kinds are imported, and the report does not describe either as a problem.
4. **Given** a chapter with neither a position nor moves, **When** the player imports it, **Then**
   it is still rejected, and the reason still says a position is what is missing.

---

### User Story 2 - See what the engine made of it, at review (Priority: P2)

At review, having committed their analysis, the player is shown what the engine thinks: what it
considers best from the position, and how their own line fared against that.

**Why this priority**: Without it, US1 produces positions that can be trained and then reviewed
against nothing, which is worse than not importing them. It is separated only because the two
can be built and tested in that order.

**Independent Test**: Review a completed session containing one engine-judged position and
confirm the engine's line and the standing of the player's own line are both shown, and that the
player can still grade themselves.

**Acceptance Scenarios**:

1. **Given** a completed session on a position with no author's line, **When** the player reaches
   review, **Then** they are shown the engine's preferred line from the starting position.
2. **Given** the same review, **When** the player looks at their own line, **Then** they are told
   how it stands against the engine's, in terms they can act on.
3. **Given** the same review, **When** the player grades the position, **Then** their own grade is
   recorded and is still the record that counts.
4. **Given** a position that does have an author's line, **When** the player reviews it, **Then**
   it is presented as it was before this feature, and the change is not visible there.

---

### User Story 3 - Nothing waits, and nothing leaks (Priority: P1)

The player trains and reviews without ever waiting for an engine, and without the app's
behaviour telling them anything about the position they are working on.

**Why this priority**: P1 alongside US1, not below it. This is the constitution's non-negotiable
principle applied to the most dangerous thing the app has ever contained, and a version of US1
that leaks is not a lesser version — it is one that must not ship.

**Independent Test**: Train a session mixing engine-judged and author-lined positions with the
device offline, and confirm every screen, every wording and every timing is indistinguishable
between the two kinds.

**Acceptance Scenarios**:

1. **Given** a session mixing both kinds of position, **When** the player trains them, **Then**
   nothing on any training screen distinguishes them.
2. **Given** an engine-judged position, **When** the player commits an analysis, **Then** the app
   responds as promptly as it does for any other position.
3. **Given** the device with no network at all, **When** the player trains and reviews an
   engine-judged position, **Then** everything works and the engine's verdict is present.
4. **Given** any point during training, **When** the player looks for a sign of the engine —
   a spinner, a delay, a wording change, a battery or thermal effect — **Then** there is none.

---

### Edge Cases

#### What can be imported

- What happens to a chapter with a position and no moves that is *also* in an unsupported
  variant? Still rejected as a variant, unchanged. Adding an engine does not change what game
  the app plays.
- What happens to a chapter with no `[FEN]` and no moves? Still rejected for having no starting
  position. The reason "a game record does not say which of its eighty positions was the
  exercise" is untouched by this feature.
- What about a position that is already checkmate or stalemate, or has no legal moves? There is
  nothing to calculate, and it should be rejected as such rather than imported and found empty
  later.
- What about a position that is legal but absurd — a lone king each, a dead draw? It is
  trainable, and the engine will say it is equal. That is a true answer to a bad exercise, and
  not the app's business to prevent.

#### What the engine says, and cannot

- What if the engine's verdict is that the position is completely lost or completely won before
  the player does anything? The review says so. That is information about the exercise the
  player chose, and review is where information belongs.
- What if the player's line is *better* than the engine's? Then the review must not claim they
  were wrong. What is shown is a comparison, not a verdict on the player.
- What if the evaluation could not be produced at all? The position must not become a trap: the
  player is told at review that no evaluation is available, in plain words, and their own grade
  still stands.
- What if two runs of the engine disagree? Whatever the review shows must be stable for a given
  position, so that a session reviewed twice does not say two different things.

#### Sessions and time

- What happens to an unfinished session that was started before this feature was installed?
  Nothing. Existing sessions and existing positions behave exactly as they did.
- What about a study imported before this feature, whose chapters were rejected for having no
  moves? They were never stored, so they are not retroactively available; the player re-imports
  if they want them.

## Requirements *(mandatory)*

### Functional Requirements

#### What may be imported

- **FR-001**: System MUST accept an entry that declares a starting position and contains no
  moves, and make it a trainable position.
- **FR-002**: System MUST continue to reject an entry with no starting position, with the reason
  unchanged. This feature widens one rule and no others.
- **FR-003**: System MUST continue to reject entries whose moves are illegal or unparseable, and
  entries in a variant other than standard chess.
- **FR-004**: System MUST reject a position in which the player has no legal move to make —
  checkmate, stalemate, or otherwise terminal — stating that there is nothing to calculate.
- **FR-005**: System MUST report an accepted no-moves entry as accepted, and MUST NOT describe it
  as a problem, a limitation, or a lesser kind of position anywhere in the import report.
- **FR-006**: System MUST import a source containing both kinds of entry without treating either
  as exceptional.

#### Where the standard of correctness comes from

- **FR-007**: System MUST obtain an evaluation for every position that has no author's line, and
  MUST record what that evaluation says so that the same position always reviews the same way.
- **FR-008**: System MUST make the evaluation available at review with no network connection.
- **FR-009**: System MUST NOT require the player to wait for an evaluation in order to start, run
  or finish a session.
- **FR-010**: System MUST behave predictably when no evaluation can be obtained: the position
  remains trainable, the review says plainly that there is no evaluation, and nothing is
  presented as though it were one.
- **FR-011**: System MUST NOT apply engine evaluation to positions that have an author's line.
  Where an author said what they intended, that remains the standard.

#### What review shows

- **FR-012**: System MUST show, at review of an engine-judged position, what the engine considers
  the best continuation from the starting position.
- **FR-013**: System MUST tell the player how their own committed line stands against the
  engine's: where the two part company, and what the engine's assessment says about that point.
  A bare number on its own does not satisfy this.
- **FR-014**: System MUST NOT present the engine's verdict as a judgement on the player. The
  player's self-grade remains the record that counts, exactly as it does for authored positions.
- **FR-015**: System MUST present an authored position at review exactly as it did before this
  feature.

#### Principle I — the part that must not be got wrong

- **FR-016**: System MUST NOT reveal, on any training screen, that a position is judged by an
  engine rather than by an author's line.
- **FR-017**: System MUST NOT vary anything on a training screen according to an evaluation — not
  colour, icon, sound, haptic, animation, arrow, highlight, move-list styling, progress
  indicator, wording, **or latency**.
- **FR-018**: System MUST NOT show an evaluation, an evaluation bar, a best move, a hint, or any
  derivative of them at any point before the session reaches review.
- **FR-019**: System MUST NOT make the player wait for, or become aware of, engine work while
  training. Any such work MUST be invisible in the app's behaviour.
- **FR-020**: System MUST keep the evaluation out of reach of the training layer entirely, so
  that displaying it there is not something a later change can do by accident.

#### Environment

- **FR-021**: Positions and their evaluations MUST survive the app being closed, reopened and
  updated.
- **FR-022**: Sessions played before this feature MUST remain readable and unchanged.

### Key Entities

- **Position without an author's line**: a trainable position whose starting point was given but
  whose continuation was not. Distinguished from an authored position by what it lacks, not by
  anything the player sees while training.
- **Evaluation**: what the engine determined about a position — its preferred continuation, and
  enough to say how another line compares. Held with the position, read only at review.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A study chapter consisting of a position and no moves imports as a trainable
  position, where before this feature it was rejected. Demonstrated on the study that prompted
  this feature.
- **SC-002**: 100% of entries that were rejected for having no moves, and that declare a starting
  position, are now accepted.
- **SC-003**: Entries rejected for any other reason are rejected at exactly the same rate as
  before — this feature changes one rule.
- **SC-004**: A player cannot tell, from any training screen, which positions in a session have an
  author's line and which do not. Confirmed by comparing everything a screen reader would
  announce for the two kinds, not by eye.
- **SC-005**: The pause between committing an analysis and the next position appearing is
  indistinguishable between the two kinds of position, over a whole session — no difference a
  player could notice, and none a stopwatch finds outside ordinary variation.
- **SC-006**: Training and reviewing an engine-judged position works with the device fully
  offline, in 100% of cases.
- **SC-007**: Starting a session never waits on an evaluation — 0 sessions blocked, however
  recently the position was imported.
- **SC-008**: Reviewing the same position twice produces the same engine verdict, every time.
- **SC-009**: A position whose evaluation is unavailable is still trainable, and its review says
  so in words the player can act on. 0 blank or broken reviews.
- **SC-010**: No training screen contains an evaluation, a best move, or any word derived from
  them, confirmed by inspection of what is reachable from that screen rather than by looking at
  it.

## Assumptions

- The study that prompted this feature — "Probando probando" — contains one chapter with a
  position and no moves. That is what the import report said on 2026-08-15: *"1 of the 1 entries
  could not be used: 1 entry has no moves, so there is no solution."* The chapter's contents have
  not otherwise been inspected, because the study is private.
- "No moves" means no moves at all beyond the declared starting position. A chapter with a single
  move is an authored line, however short, and is out of scope for engine judgement.
- The player still grades themselves, on the same scale, for both kinds of position. This feature
  adds a second source of *solutions*, not a second kind of session.
- An evaluation is about the position as set up. This feature does not evaluate every node of a
  player's analysis tree; what it must support is showing a best line and saying how the player's
  line compares to it.
- Existing stored positions are unaffected. Nothing is re-evaluated retroactively, and no
  migration re-imports anything.
- The app remains Android-first, and whatever supplies the evaluation must not preclude iOS.

## Out of Scope

- Scheduling, spaced repetition, and anything that shows how a position has gone for the player
  before. Still deferred, still the feature that has to argue for itself.
- Engine analysis as a browsing tool — evaluating arbitrary positions the player navigates to,
  an evaluation bar, or an "analyse this" mode. This feature supplies a standard of correctness
  for positions that lack one, and nothing else.
- Changing how authored positions are compared. Feature 001's comparison is untouched.
- Accepting entries with no starting position. That rejection stands, for the reason 003 gave.
- Difficulty ratings, themes, or any other engine-derived classification of a position.
- Re-evaluating or re-importing anything already in the library.
