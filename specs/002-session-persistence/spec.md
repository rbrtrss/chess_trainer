# Feature Specification: Session Persistence

**Feature Branch**: `002-session-persistence`

**Created**: 2026-08-12

**Status**: Draft

**Input**: User description: "Session persistence: everything the training loop produces survives the app being closed. An interrupted session can be resumed exactly where it was, finished sessions remain readable afterwards, and a position's earlier grades are visible at review. Still bundled positions only, still no network, still no scheduling."

## Overview

Feature 001 proved the training loop but deliberately let everything it produced die with the
process: kill the app mid-session and the work is gone. That was acceptable while the only
question was whether withholding feedback feels good to use. It is not acceptable now.

This feature makes the loop's output durable. It adds no new content source, no accounts, and
no scheduling — it stores what 001 already produces and gives the player two things they
cannot have today: the ability to be interrupted without losing the session, and the ability
to look back at what they did.

Persistence also opens a way for the product's central rule to be broken: a resumed session
could reveal something a fresh one would not. That is addressed as a requirement rather than
left to care. The other risk — a record of past performance acting as evidence about the
position on screen — is avoided outright by not building one; see Out of Scope.

## Clarifications

### Session 2026-08-12

- Q: When the app is killed mid-analysis on a position not yet committed, should those moves come back on resume? → A: No — only committed attempts survive; the current position is resumed with an empty board.
- Q: Should a session reopened from history show the solution as it was when played, even after an app update changes it? → A: Yes — each session stores its own frozen copy of the solutions, notes and metadata it used.
- Q: What happens when starting a new session while one is unfinished? → A: Warn that the unfinished one is discarded and its answers forfeited, in the same words as abandoning, then discard on confirmation.
- Q: Should a position's earlier grades be shown at review in this feature? → A: No — drop per-position history entirely. Grades are stored with the session that gave them; cross-session history and its display belong to the scheduling feature.
- Q: When a grade is changed from a past review, is the old grade kept? → A: No — one grade per position per session; re-grading overwrites it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Resume an interrupted session (Priority: P1)

A player is part way through a session — some positions committed, the current one half
analysed. The phone rings, the app is backgrounded, and Android kills it. When they open the
app again they are offered to carry on, and doing so returns them to the session: the same
position, the same place in the count, and every analysis they had committed. The position
they were in the middle of starts over with an empty board, and they are told so rather than
left to wonder. Nothing about how they are doing has appeared.

**Why this priority**: This is the pain feature 001 knowingly left behind. A calculation
session is twenty minutes of concentrated work, and losing it to an interruption makes the app
feel unsafe to start. It is also the requirement most likely to change behaviour: a player who
trusts the app will start longer sessions.

**Independent Test**: Start a five-position session, commit two, enter a branching analysis on
the third, kill the app from the recents screen, reopen it, and confirm the session resumes at
position three of five with both committed attempts kept, the board back at the starting
position, and nothing revealed.

**Acceptance Scenarios**:

1. **Given** a session in progress, **When** the app is killed and reopened, **Then** the
   player is offered to continue that session.
2. **Given** the player continues, **When** the training screen appears, **Then** it shows the
   same position and the same position count as before the interruption.
3. **Given** the player had entered moves without committing them, **When** the session
   resumes, **Then** the board is back at that position's starting point with no moves
   entered, and the player is told that the analysis in progress was not kept — so that an
   empty board reads as a known consequence rather than as lost work or a fault.
4. **Given** a resumed session, **When** the player looks at any part of the training screen,
   **Then** nothing indicates correctness and no withheld metadata appears — resuming reveals
   exactly as much as never having been interrupted, which is nothing.
5. **Given** a resumed session, **When** the player commits the final position, **Then** review
   begins and shows every attempt, including those committed before the interruption.
6. **Given** a session that was abandoned, **When** the app is reopened, **Then** it is not
   offered for resumption and no answers from it are shown.
7. **Given** a session that was completed, **When** the app is reopened, **Then** no
   resumption is offered and the player starts fresh.

---

### User Story 2 - Look back at a finished session (Priority: P2)

Having finished a session, the player can find it again later: when it was, how many positions
it had, and what they graded each one. Opening it shows the same review they saw at the time —
their tree beside the solution, the divergence, the author's notes.

**Why this priority**: Without this, the review is something you see once and can never return
to, and the grades the player recorded vanish the moment they close the app. It depends on the
storage that Story 1 introduces but delivers value independently of it.

**Independent Test**: Complete a session, close the app, reopen it, open the history, open that
session, and confirm the review content is identical to what was shown when the session ended.

**Acceptance Scenarios**:

1. **Given** finished sessions exist, **When** the player opens the history, **Then** each is
   listed with when it happened and how many positions it had.
2. **Given** a completed session in the history, **When** the player opens it, **Then** they can
   step through each position's committed analysis and the solution, and see the divergence,
   the notes, and the grade they gave.
3. **Given** an abandoned session in the history, **When** the player opens it, **Then** it is
   shown as abandoned and **no** solution, note, or withheld metadata for its positions is
   revealed — abandoning forfeits the answers permanently, not just until the app restarts.
4. **Given** a past review, **When** the player records a different grade, **Then** the new
   grade replaces the old one and is the one that counts.
5. **Given** stored history, **When** the player chooses to delete it, **Then** they are warned
   that it cannot be recovered, and on confirmation everything stored is removed.

---

### Edge Cases

- **Killed mid-analysis**: The app dies while the player is part way through a position they
  have not committed. Those moves are gone by design; what must not happen is the app implying
  they were kept, or presenting the empty board as an error.
- **Killed mid-commit**: The app dies between the player tapping Done and the attempt being
  stored. The attempt is either wholly stored or not stored at all; the session must never
  resume in a state where a position is half committed.
- **Storage unavailable or full**: The device cannot write. The player is told plainly, and
  already-stored data is not damaged. A session that cannot be stored must not silently behave
  as though it had been.
- **Stored data unreadable**: Corrupt or partially written data is treated as absent rather
  than crashing the app, and the player starts a fresh session.
- **App updated and the supplied positions changed**: A position is corrected or removed in a
  later version of the app. Sessions already played are unaffected — they carry their own copy
  of what was shown — and continue to display exactly what the player saw and graded against.
- **Starting a session while one is unfinished**: Only one session may be in progress. Starting
  a new one discards the unfinished one, and that forfeits its answers — so it carries the same
  warning as abandoning.
- **A long history**: Hundreds of sessions accumulate. The list stays usable and opening it does
  not delay the app's start.
- **Device clock changes**: Timestamps already recorded are not rewritten; a session does not
  move around in the history because the clock was adjusted.
- **Same position appearing twice in one session**: Its grades are recorded per encounter, not
  overwritten, so the position's history is a sequence rather than a single value.

## Requirements *(mandatory)*

### Functional Requirements

#### Storing a session in progress

- **FR-001**: System MUST store the state of a session in progress so that it survives the app
  being closed, killed by the operating system, or the device restarting.
- **FR-002**: System MUST store a committed attempt at the moment it is committed.
- **FR-003**: System MUST resume the current position with no moves entered, and MUST tell the
  player that an analysis in progress was not kept, so that an empty board is understood as a
  known consequence rather than as lost work. Uncommitted analysis is deliberately not stored.
- **FR-004**: System MUST record which position of the session the player is currently on.
- **FR-005**: System MUST store an attempt atomically: after any interruption, a position is
  either committed or not committed, never partly so.

#### Resuming

- **FR-006**: System MUST offer to resume an unfinished session when the app is opened.
- **FR-007**: System MUST restore, on resumption, the current position, the position count, and
  every previously committed attempt.
- **FR-008**: System MUST present a resumed training phase identically to how it would have been
  presented had the session never been interrupted, revealing nothing about correctness and no
  withheld metadata.
- **FR-009**: System MUST NOT offer abandoned or completed sessions for resumption.
- **FR-010**: System MUST allow at most one session in progress at a time, and MUST warn — in
  the same terms as abandoning — that starting a new session discards the unfinished one and
  forfeits its answers.
- **FR-011**: Users MUST be able to decline resumption and start a fresh session instead, which
  discards the unfinished one under the same warning.

#### Keeping finished sessions

- **FR-012**: System MUST retain a session after it ends, recording when it happened, which
  positions it contained, the committed attempts, and the grades.
- **FR-013**: Users MUST be able to see a list of past sessions.
- **FR-014**: Users MUST be able to reopen the review of a completed session and see the same
  analysis, solution, divergence, notes, and metadata that were shown when it ended.
- **FR-015**: System MUST retain, with each session, its own copy of the solutions, notes and
  metadata used for that session's positions, so that a later change to the supplied positions
  cannot alter a session already played. A grade is a judgement against the answer the player
  was shown, and that answer must therefore be part of the record.
- **FR-016**: System MUST record an abandoned session as abandoned, and MUST NOT reveal any
  solution, note, or withheld metadata for the positions it contained.
- **FR-017**: Users MUST be able to record a different grade when reopening a past review. A
  position holds exactly one grade per session, and re-grading overwrites it; no earlier grade
  is retained.
- **FR-018**: Users MUST be able to delete all stored sessions and grades, after a warning that
  the deletion cannot be undone.

#### Guarding against history as a hint

- **FR-019**: System MUST NOT display, during the training phase, anything derived from the
  player's past encounters with the position on screen — no earlier grade, no count of previous
  attempts, no date last seen, no difference in ordering or emphasis. Nothing in this feature
  produces such a display today; the requirement exists so that the storage this feature does
  create cannot quietly grow one.

#### Content and environment

- **FR-020**: System MUST continue to source positions from the fixed set supplied with the app.
- **FR-021**: All stored data MUST remain on the device, and MUST NOT be sent anywhere.
- **FR-022**: Every path in this feature MUST function with no network connection.
- **FR-023**: System MUST treat missing or unreadable stored data as absent — reporting it
  plainly where the player would otherwise be waiting for it — rather than failing to start.
- **FR-024**: System MUST tell the player when their work could not be stored, rather than
  letting them believe it was.
- **FR-025**: Stored data MUST survive an update to the app.

### Key Entities

- **Stored Session**: A session that has been persisted — when it started, when it ended, which
  positions it contained, and whether it is in progress, complete, or abandoned. It also holds
  the frozen copy of each position's solution, notes and metadata as used by that session.
- **Position Snapshot**: One position exactly as it was presented in one session: its starting
  point, its solution, its notes and its metadata. Immutable once the session has begun.
- **Stored Attempt**: A committed analysis of one position within a stored session, together
  with the time spent. Immutable, as it is today.
- **Grade**: The player's self-assessment of one position within one session, recorded against
  that session. Sessions are the only thing grades belong to in this feature; nothing
  aggregates them across sessions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: No committed attempt is ever lost. After killing the app at any point in a
  session and resuming, every attempt committed before the interruption is present — verified
  by interrupting at each of: mid-analysis, immediately after a commit, and during review.
- **SC-002**: An interrupted session is back on screen, at the right position and with the
  right analysis, within three seconds of the app being opened.
- **SC-003**: Across the training phase of a resumed session, zero screen elements differ from
  those of an uninterrupted session at the same point. Verified by exhaustive audit and
  repeated as an automated check.
- **SC-004**: Zero elements anywhere in the training phase are derived from the player's history
  with the position on screen. Verified by exhaustive audit and repeated as an automated check.
- **SC-005**: A completed session reopened from the history shows review content identical to
  what was shown when the session ended.
- **SC-006**: A player can find and reopen a session from a week ago in under thirty seconds,
  without consulting documentation.
- **SC-007**: A full session — start, interruption, resumption, completion, review, and a later
  visit to the history — can be carried out with the device offline throughout.
- **SC-008**: Stored sessions and grades survive an app update, verified by installing a new
  build over an existing one and reopening the history.
- **SC-009**: The app opens to a usable screen in under two seconds with a history of at least
  two hundred sessions.

## Assumptions

- A single user per device, with no accounts, profiles, or synchronisation. Unchanged from
  feature 001.
- Positions continue to come from the fixed bundled set. Fetching content from anywhere is a
  later feature, and this one must not anticipate it beyond storing a position's identity.
- Only one session may be in progress at a time. A player who wants to start something else
  must give up the unfinished one, because two half-finished sessions would make "resume" an
  ambiguous offer.
- Uncommitted analysis is **not** stored; only committed attempts are. An interruption
  therefore costs the player the position they were in the middle of, and nothing else. This
  keeps storage writes tied to a deliberate act — tapping Done — rather than to every move, and
  removes the need to write to the database while the player is calculating.
- History is kept indefinitely. A session is a few positions and a handful of small move trees,
  so volume is not a reason to discard anything; the player can delete everything if they want.
- Grades may be revised when a past review is reopened, and revising overwrites rather than
  appends. The player's own assessment is authoritative, and that includes an assessment they
  later revise; keeping the superseded one would serve no reader now that cross-session history
  is out of scope.
- Timestamps are recorded when things happen and displayed in the device's local time.
- Aggregate statistics — streaks, accuracy over time, charts — are deliberately absent. They are
  a different feature and would need their own argument against Principle I.

## Out of Scope

- Fetching positions from any external source.
- Accounts, authentication, synchronisation, cloud backup, and export.
- Scheduling repeat practice, spaced repetition, or choosing which positions come next.
- Any cross-session view of how a position has gone before — a per-position history, an
  encounter count, a "last seen" date, or anything else that aggregates grades across sessions.
  The grades are recorded, so a later feature can build this; this one deliberately does not,
  because displaying it is the one thing here that would put evidence about a position in front
  of a player who is still calculating.
- Aggregate statistics, charts, streaks, or any score derived from grades.
- Editing a committed analysis. Commits remain immutable.
- Sharing or exporting a session or an analysis.
