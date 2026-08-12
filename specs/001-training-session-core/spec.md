# Feature Specification: Training Session Core

**Feature Branch**: `001-training-session-core`

**Created**: 2026-08-12

**Status**: Draft

**Input**: User description: "Training session core: the complete delayed-feedback training loop running on bundled sample positions, with no network and no database. A session presents N chess positions one at a time. For each position the user sees only the board and whose turn it is, and builds a tree of variations by playing moves for both colours; rewinding and playing a different move silently creates a branch. The user taps Done to commit and move to the next position. Nothing anywhere may indicate correctness during this phase. After the last position, a review phase reveals for each position: the user's tree replayed beside the solution, the divergence point, the author's annotations, a match indicator comparing the user's primary line to the solution mainline, and self-grade buttons whose result is the authoritative grade."

## Overview

This feature builds the entire training experience end to end, using a small fixed set of
positions supplied with the app. It deliberately excludes all content sourcing, accounts,
and persistence, so that the product's central and unproven claim — that withholding
feedback until the end of a session produces better calculation practice — can be
evaluated before any supporting infrastructure is built around it.

If this loop does not feel good to use, nothing else in the product matters.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Analyse one position without feedback (Priority: P1)

A player opens the app and is shown a chess position. The only thing they are told is
whose turn it is. They work out what they think happens: they play a candidate move, then
the reply they expect from the opponent, then their follow-up, continuing as deep as their
calculation goes. When they want to test a different idea, they step back to an earlier
point and play a different move; their new idea is kept alongside the earlier one rather
than replacing it. Nothing on screen reacts to whether any move is good. When satisfied,
they commit their analysis and the answer is revealed.

**Why this priority**: This is the product. With a session length of one position, this
story alone is a complete, usable training tool and validates the core thesis.

**Independent Test**: Launch the app with a single-position session, enter a branching
analysis, commit, and confirm the answer appears only afterward and that nothing before
that point varied with correctness.

**Acceptance Scenarios**:

1. **Given** a position is presented, **When** the player views it, **Then** they are told
   whose turn it is and nothing else about the position — no goal, no difficulty, no
   theme, no title, no indication of how long the solution is.
2. **Given** a position is presented, **When** the player plays a legal move for the side
   to move, **Then** the move is accepted and it becomes the opponent's turn to be played
   by the same player.
3. **Given** the player has played a sequence of moves, **When** they step back two plies
   and play a move different from the one already recorded there, **Then** a new branch is
   created at that point, the previously recorded continuation remains intact, and the app
   gives no indication that anything notable happened.
4. **Given** the player has played any move, **When** the move is displayed, **Then** its
   colour, styling, sound, haptic, and animation are identical regardless of whether the
   move matches the solution.
5. **Given** the player attempts an illegal move, **When** the move is rejected, **Then**
   the rejection is presented identically for all illegal moves and reveals nothing about
   the position's solution.
6. **Given** the player has entered their analysis, **When** they commit it, **Then** the
   analysis is locked and cannot be edited.

---

### User Story 2 - Complete a multi-position session (Priority: P2)

A player starts a session of several positions. They analyse and commit each one in turn.
Throughout, they can see how far through the session they are but learn nothing about how
they have done. Only after the final position is committed does the review begin.

**Why this priority**: Deferring feedback across several positions is what separates this
from a slower puzzle app. It also creates the desirable difficulty of moving on while
still uncertain. It depends on Story 1 being in place.

**Independent Test**: Run a session of five positions, confirm no correctness information
appears at any point during the five, and that review begins only after the fifth commit.

**Acceptance Scenarios**:

1. **Given** a session of N positions, **When** the player commits a position, **Then**
   the next position is presented immediately with no interstitial result of any kind.
2. **Given** a session in progress, **When** the player views the screen, **Then** they can
   see their position within the session (e.g. "3 of 5") and this indicator's appearance
   does not vary with performance.
3. **Given** the final position is committed, **When** the commit completes, **Then** the
   session enters review.
4. **Given** a session in progress, **When** the player abandons it, **Then** they are
   warned that abandoning forfeits the review, and on confirmation the session ends
   without revealing any answers.

---

### User Story 3 - Review the session and grade yourself (Priority: P3)

After the last position, the player walks through each position in turn. For each, they
see their own analysis replayed next to the intended solution, where the two first
diverged, and any explanatory notes attached to the solution. They then judge their own
performance and record that judgement.

**Why this priority**: This is the payoff, but a minimal version — simply showing the
solution — is enough to make Story 1 viable, so the richer comparison can follow.

**Independent Test**: Complete a session, then confirm each position's review shows the
committed analysis, the solution, the divergence point, the notes, and records a grade.

**Acceptance Scenarios**:

1. **Given** review has begun, **When** the player views a position, **Then** their
   committed analysis and the intended solution are both shown and can be stepped through.
2. **Given** the player's primary line differs from the solution, **When** the review is
   shown, **Then** the first point of difference is identified.
3. **Given** the solution carries explanatory notes, **When** the review is shown,
   **Then** those notes are displayed at the moves they belong to.
4. **Given** a review of a position, **When** it is displayed, **Then** a match indicator
   states how far the player's primary line agreed with the solution's main line.
5. **Given** a reviewed position, **When** the player records a self-grade, **Then** that
   grade is retained as the authoritative assessment of the position, taking precedence
   over the match indicator.
6. **Given** a position where the player's alternative branch differs from the solution,
   **When** the review is shown, **Then** the app does not assert that the branch is wrong,
   because it has no basis for that judgement.

---

### Edge Cases

- **Empty analysis**: The player commits without playing a single move. This is a valid
  "I have no idea" answer, must be accepted, and must be gradeable at review.
- **Analysis longer than the solution**: The player calculates ten plies where the
  solution records four. The match indicator is bounded by the solution's length and the
  extra moves are neither credited nor faulted.
- **Analysis shorter than the solution**: Reported as agreement up to where the player
  stopped, explicitly distinguished from a wrong move.
- **Player reaches checkmate, stalemate, or a dead position** while entering their line:
  the line ends there; no further moves can be added to that branch. Because this is a
  natural consequence of the rules rather than a judgement, it does not violate the
  no-feedback rule — but the app must not comment on it.
- **Repeated identical move at a branch point**: Stepping back and replaying the *same*
  move must navigate into the existing branch rather than create a duplicate sibling.
- **Deep or wide trees**: A tree with many branches must remain navigable on a phone
  screen.
- **Interruption**: The app is backgrounded or killed mid-session. Session state is
  in-memory for this feature; the session is lost and the player restarts. This is
  acceptable here and is revisited when persistence exists.
- **Promotion**: The player promotes a pawn while entering a line and must be able to
  choose the piece; the chooser must not hint at which promotion is correct.

## Requirements *(mandatory)*

### Functional Requirements

#### Position presentation

- **FR-001**: System MUST present one position at a time, showing the board and the side
  to move.
- **FR-002**: System MUST orient the board from the perspective of the side to move.
- **FR-003**: System MUST NOT display, during the training phase, any of: the goal or
  expected result, difficulty or rating, themes or tags, source title or chapter name,
  solution length, annotations, evaluation glyphs, or move quality symbols.

#### Building the analysis

- **FR-004**: Users MUST be able to play legal moves for both colours, alternating, from
  the presented position.
- **FR-005**: System MUST reject illegal moves identically in all cases, with no
  explanation that could disclose anything about the position.
- **FR-006**: Users MUST be able to step backward and forward through the moves they have
  entered, and to return to the starting position.
- **FR-007**: System MUST create a new branch when the user, positioned at an existing
  node, plays a move other than one already recorded from that node.
- **FR-008**: System MUST navigate into the existing branch, rather than duplicate it,
  when the user plays a move already recorded from the current node.
- **FR-009**: System MUST create branches without confirmation, announcement, or any other
  interruption.
- **FR-010**: Users MUST be able to see the structure of the analysis they have entered
  and to navigate to any point in it.
- **FR-011**: Users MUST be able to delete a branch they have entered.
- **FR-012**: System MUST treat the first move entered from the starting position as the
  primary line, and likewise at every branch point, unless the user explicitly promotes
  another branch.
- **FR-013**: Users MUST be able to promote a branch to become the primary line.

#### Committing and session flow

- **FR-014**: Users MUST be able to commit their analysis for the current position at any
  time, including with no moves entered.
- **FR-015**: System MUST make a committed analysis immutable.
- **FR-016**: System MUST advance directly to the next position on commit, with no
  intervening result screen.
- **FR-017**: System MUST show session progress as a plain position count.
- **FR-018**: System MUST begin the review phase only after the final position is
  committed.
- **FR-019**: System MUST allow a session to be abandoned, warning first that no answers
  will be shown, and revealing none.

#### Review

- **FR-020**: System MUST present, for each position in the session, the user's committed
  analysis and the intended solution together, both navigable.
- **FR-021**: System MUST identify the first move at which the user's primary line differs
  from the solution's main line.
- **FR-022**: System MUST display any notes attached to the solution at their corresponding
  moves.
- **FR-023**: System MUST display a match indicator reporting the length of agreement
  between the user's primary line and the solution's main line.
- **FR-024**: System MUST NOT characterise the user's non-primary branches as correct or
  incorrect.
- **FR-025**: System MUST reveal, at review only, the metadata withheld under FR-003.
- **FR-026**: Users MUST be able to record a self-grade for each reviewed position.
- **FR-027**: System MUST treat the self-grade as the authoritative assessment, and the
  match indicator as advisory.
- **FR-028**: Users MUST be able to move freely between positions during review.

#### Content and environment

- **FR-029**: System MUST source this feature's positions from a fixed set supplied with
  the app.
- **FR-030**: System MUST function with no network connection.
- **FR-031**: Each supplied position MUST carry a starting position, a solution with
  optional branches, and optional notes.

### Key Entities

- **Training Position**: A chess position to be analysed. Holds the starting position,
  the side to move, the intended solution as a tree of moves with optional notes, and
  descriptive metadata that is withheld during training and revealed at review.
- **Variation Tree**: A rooted tree of chess moves. Each node holds one move and its
  resulting position; a node's children are the alternatives considered at that point,
  the first being the primary continuation. Used both for the intended solution and for
  the user's analysis.
- **Attempt**: One user's committed analysis of one position — the tree they entered,
  frozen at commit, plus the time spent.
- **Session**: An ordered set of positions and the state of progress through them:
  building attempts, then reviewing, then complete.
- **Comparison Result**: The derived relationship between an attempt and a solution — the
  agreement length and the first point of difference. Advisory only.
- **Grade**: The user's own assessment of one reviewed position; the authoritative record.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Across the entire training phase, zero screen elements vary with the
  correctness of the user's input. Verified by exhaustive audit of every element reachable
  during training, repeated as an automated check.
- **SC-002**: A user can create an alternative branch — step back and record a different
  idea — in no more than three interactions, without consulting documentation.
- **SC-003**: A complete session of five positions can be started, analysed, committed,
  and reviewed with the device offline.
- **SC-004**: In review, a user can determine where their line first departed from the
  solution within ten seconds of the position being displayed.
- **SC-005**: Nine out of ten first-time users correctly understand, without instruction,
  that entering a move for the opponent is expected of them rather than a malfunction.
- **SC-006**: Board interaction remains responsive with an analysis of at least 40 moves
  across at least 8 branches.
- **SC-007**: No user-entered analysis is lost between being committed and being reviewed.

## Assumptions

- The user knows how to play chess and reads standard board conventions; no tutorial on
  the rules is needed.
- Sessions are short — roughly three to ten positions — and completed in one sitting.
  Resuming an interrupted session is out of scope for this feature.
- A single user per device. No accounts, profiles, or sharing.
- Session results need not survive app restart in this feature; persistence arrives with a
  later feature, at which point SC-007 extends across restarts.
- The supplied positions are few and hand-picked, chosen to span a plain tactic, a quiet
  positional choice, and an endgame technique, so the loop is exercised against genuinely
  different kinds of thinking.
- The solution's main line is the intended answer. Where a supplied position records
  alternatives, they are shown at review but are not required of the user.
- Because no engine evaluates the user's moves, the app cannot judge lines the solution
  does not contain. This is why the user's self-grade is authoritative, and it is a
  deliberate scope decision rather than a limitation to be worked around.
- "Whose turn it is" is not considered a hint; it is the minimum information required for
  the position to be playable at all.

## Out of Scope

- Fetching positions from any external source.
- Accounts, authentication, and synchronisation.
- Storing sessions, history, statistics, or scheduling repeat practice.
- Any engine evaluation, best-move suggestion, or accuracy scoring.
- An opponent that plays back against the user.
- Hints, retries, or per-move validation in any form.
