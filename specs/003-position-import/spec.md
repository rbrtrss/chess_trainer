# Feature Specification: Position Import

**Feature Branch**: `003-position-import`

**Created**: 2026-08-14

**Status**: Draft

**Input**: User description: "Position import: the app's content stops being the three bundled samples. The player brings in their own positions — a PGN file on the device, or a study fetched from their Lichess account — organised into named collections, and chooses which collection a session draws from. Still no scheduling."

## Overview

Features 001 and 002 built a training loop and made its output durable, both over three sample
positions shipped inside the app. Those three exist to prove the loop, not to train on. A
calculation trainer whose content cannot change is a demo.

This feature makes the content the player's own. Positions arrive two ways: from a PGN file
already on the device, and from Lichess — a study of theirs, public or private, fetched by the
app after they log in. Either way the result is the same thing: a named collection of trainable
positions that a session can be pointed at.

Bringing Lichess in makes this the first feature to touch the network, and the constitution is
specific about what that costs. Fetching happens only when the player asks for it, never in the
background and never while a screen waits to draw. Training itself keeps reading from local
storage alone, so a session begun on an imported study runs identically on a plane. And Lichess
issues no refresh tokens, so an expired login is presented as "log in again" rather than
patched over with a refresh path that cannot exist.

Import is also where Principle I is most exposed. Everything a study carries that makes it
useful to a human reader — the chapter title, the author's commentary, the `!!` on the key
move, the `1-0` in the headers, the file's own name — is evidence about the position, and all
of it arrives at once, attached to the thing being trained. Feature 001 withheld five known
metadata fields authored by us. This feature accepts arbitrary text written by someone else and
must withhold all of it, including kinds we did not anticipate. That is the requirement this
specification exists to pin down.

## Clarifications

### Session 2026-08-14

- Q: Is a file on the device the only import source, or should Lichess studies be fetched too? → A: Fetch them too, including private studies, which means logging in to Lichess from the app.
- Q: What happens to an imported entry with no starting-position header, the common case for a PGN of a played game? → A: Reject it with the reason stated. A trainable position must declare where it starts; importing a whole game and calling move 1 the starting point is not a calculation exercise.
- Q: What becomes of the three bundled sample positions once the player imports their own? → A: They are seeded on first run as an ordinary collection, deletable like any other. No permanent special case.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Train on a study file I already have (Priority: P1)

A player has a PGN file: a study exported from Lichess, with a dozen chapters, each a position
with the author's analysis in variations and comments. They bring it into the app, give it a
name, and are told what came in — how many positions, and plainly which entries could not be
read and why. They start a session on it. The training screen shows a position and whose turn it
is, exactly as it does for the samples: no chapter title, no comment, no glyph, no result, no
collection name. At review, everything the file carried is theirs to read.

**Why this priority**: This is the whole feature reduced to its smallest working form. It proves
the part that everything else depends on — that arbitrary study PGN becomes positions that train
well and leak nothing — without a single network call. The Lichess path in Story 2 ends by
handing the very same text to the very same code.

**Independent Test**: Import a multi-chapter study PGN containing comments, glyphs, variations
and result headers, run a full session on it, and confirm that the training screen shows
nothing but the board and the side to move, while review shows the author's analysis and notes
for each position.

**Acceptance Scenarios**:

1. **Given** a valid PGN file on the device, **When** the player imports it, **Then** its
   positions become available to train on and are grouped under a name the player chose.
2. **Given** an import has finished, **When** the player looks at the result, **Then** they are
   told how many positions were added, and for each entry that was rejected, which one it was
   and why — an import must never fail silently or partly-silently.
3. **Given** a file where some entries are valid and others are not, **When** it is imported,
   **Then** the valid ones are added and the invalid ones are reported; one bad chapter does not
   discard the rest.
4. **Given** an entry with no starting-position header, **When** the file is imported, **Then**
   that entry is rejected with the reason given, and the rest of the file is unaffected.
5. **Given** an imported position under training, **When** the player looks at any part of the
   training screen, **Then** no title, comment, annotation glyph, result, collection name, file
   name, or any other text from the file is shown, and nothing distinguishes it from a bundled
   position beyond the pieces on the board.
6. **Given** an imported position at review, **When** the review is shown, **Then** the author's
   solution, comments, annotations and the position's title are all available to read.
7. **Given** a study chapter whose analysis contains branching variations, **When** it is
   imported, **Then** those branches are preserved as alternatives in the solution, not
   flattened to a single line.
8. **Given** a file the app cannot read at all, **When** the player imports it, **Then** they
   are told plainly and nothing is added.

---

### User Story 2 - Import a study straight from Lichess (Priority: P2)

The player keeps their material in Lichess studies, some public, some private. Rather than
exporting a file and moving it onto the phone, they log in to Lichess from the app once, pick a
study of theirs — or paste its address — and it becomes a collection. Later they open the app on
a train with no signal and train on it exactly as if it had come from a file, because by then it
is a local collection like any other.

**Why this priority**: The export-and-transfer dance in Story 1 is the kind of friction that
stops a training habit before it starts, and private studies cannot be reached at all without
logging in. It is second rather than first because it is strictly larger — it is the only part
of this feature that needs a network, a login, and everything that follows from both — and
because it reduces, once the study is fetched, to work Story 1 has already done.

**Independent Test**: Log in to Lichess from the app, import a private study of the account's,
put the device in airplane mode, and run a full session on it.

**Acceptance Scenarios**:

1. **Given** the player is not logged in, **When** they import a public study by its address,
   **Then** it is imported without a login being required.
2. **Given** the player is not logged in, **When** they try to import one of their private
   studies, **Then** they are asked to log in to Lichess, and after doing so the import
   proceeds.
3. **Given** the player is logged in, **When** they choose to import, **Then** they can pick
   from their own studies rather than having to know an address.
4. **Given** a study is fetched, **When** the import finishes, **Then** it produces a collection
   indistinguishable in behaviour from one imported from a file, with the same report of what
   was added and what was rejected.
5. **Given** an imported study, **When** the device is offline, **Then** every position in it can
   still be trained and reviewed.
6. **Given** the device is offline, **When** the player tries to import from Lichess, **Then**
   they are told the import needs a connection, and nothing else in the app is impaired —
   sessions on existing collections start and run normally.
7. **Given** the login has expired, **When** the player next imports something needing it,
   **Then** they are asked to log in again, and are never left looking at a failure they cannot
   act on.
8. **Given** a fetch fails part way — connection lost, server error, rate limit — **When** the
   player looks at the app, **Then** they are told what happened and no partial collection has
   been created.
9. **Given** the app is opened, or a session is started, or review is reached, **When** any of
   those happen, **Then** no network request is made — fetching only ever follows the player
   explicitly asking for it.

---

### User Story 3 - Choose what a session draws from (Priority: P3)

The player has several collections — a set of rook endgames, a tactics study, a mating-patterns
study pulled from Lichess. Starting a session, they choose which collection to work through, and
how many positions. The chosen collection's name is on the setup screen and nowhere after it.

**Why this priority**: One collection is usable without this; several are not, because a session
that mixes rook endgames with mating attacks is a different exercise from either. It is small,
but it depends on there being something to choose between.

**Independent Test**: Import two collections, start a session restricted to one of them, and
confirm every position in the session came from that collection and that its name never appears
on a training screen.

**Acceptance Scenarios**:

1. **Given** more than one collection exists, **When** the player starts a session, **Then**
   they can choose which one it draws from.
2. **Given** a collection is chosen, **When** the session runs, **Then** every position in it
   comes from that collection.
3. **Given** a collection with fewer positions than the requested session length, **When** the
   player starts, **Then** they are told how many are available and the session is that long,
   rather than repeating positions to make up the number.
4. **Given** a session is under way, **When** the player is on a training screen, **Then** the
   collection's name is not shown there.
5. **Given** an empty collection, **When** the player tries to start a session on it, **Then**
   they are told it has no positions and the session does not start.

---

### User Story 4 - Manage what I have imported (Priority: P4)

The player can see what is in the app: each collection, where it came from, when it was
imported, and how many positions it holds. They can rename one, and delete one they are done
with — including the bundled samples, once they have material of their own — after being told
what deletion costs. They can also disconnect their Lichess account, which forgets the login
without touching anything already imported. Sessions they already played remain readable
throughout.

**Why this priority**: Import without deletion is a one-way accumulation, and a mistaken import
would be permanent. It is last because a player can live with a wrong collection for a while,
but not with no way to import at all.

**Independent Test**: Import a collection, play a session on it, delete it, and confirm it can
no longer be trained while the played session still shows its full review.

**Acceptance Scenarios**:

1. **Given** imported collections exist, **When** the player opens the list, **Then** each is
   shown with its name, where it came from, when it was imported, and how many positions it
   holds.
2. **Given** a collection, **When** the player renames it, **Then** the new name is used
   wherever the old one was — and, as before, on no training screen.
3. **Given** a collection, **When** the player deletes it, **Then** they are warned first that
   its positions can no longer be trained and that the deletion cannot be undone.
4. **Given** the bundled sample collection, **When** the player deletes it, **Then** it is
   removed like any other collection and does not return on the next launch.
5. **Given** a deleted collection, **When** the player opens a past session that used it,
   **Then** the review still shows that session's positions, solutions and notes in full,
   because the session holds its own copy of them.
6. **Given** a collection whose positions are in the session currently in progress, **When** the
   player deletes it, **Then** they are told the unfinished session will be discarded, in the
   same terms as abandoning it.
7. **Given** the player is logged in to Lichess, **When** they disconnect the account, **Then**
   the stored login is forgotten, everything already imported is untouched, and importing from
   Lichess again asks them to log in.
8. **Given** no collections remain, **When** the player opens the app, **Then** they are shown
   how to import something rather than an error or an empty screen with no way forward.

---

### Edge Cases

#### Content

- **A file that is not PGN at all**: A photo, a spreadsheet, an empty file. Rejected with a
  message that says what was expected, not a parser error.
- **Enormous file or study**: A database of thousands of games, or a study with hundreds of
  chapters. The import either completes without the app appearing to hang, or is refused with a
  stated limit — it must not freeze mid-way with no indication of progress.
- **An entry with no moves**: A chapter that is only a position and a title. It has no solution,
  so there is nothing to compare an analysis against; it is rejected as unusable rather than
  imported as a position that cannot be graded.
- **An entry with no starting position**: A played game, exported as PGN, with no position
  header. Rejected with the reason stated: the app cannot know which of its eighty positions was
  meant to be the exercise, and guessing move 1 would produce a position nobody can train.
- **An illegal move part way through a chapter**: Everything before it is fine. The chapter is
  rejected as a whole rather than silently truncated, because a solution ending early is
  indistinguishable, at review, from a solution that ends there on purpose.
- **A non-standard variant**: Chess960, Crazyhouse, Atomic. Rejected with the reason given.
  Training assumes standard chess, and a variant position that trains as standard chess is
  worse than no position.
- **The same content imported twice**: Two collections with the same content. The player is told
  the content looks like something already imported, and decides; the app does not silently
  merge, deduplicate, or refuse.

#### Principle I

- **Names that leak**: A collection called "Back-rank mates", or a file called `mate-in-3.pgn`,
  or a Lichess study titled "Winning the opposition". The player is free to use such names — the
  constraint is on the app, which must never put a collection, file, or study name on a training
  screen.
- **Headers nobody anticipated**: A file carrying `[Annotator]`, `[Opening]`, `[Termination]`,
  or something invented by whoever wrote it. Unknown text is withheld by default; the rule
  cannot be a list of field names, because the list is not ours to write.
- **Adjacent positions that share a theme**: A collection is often a themed set, so its second
  position hints at its third. That is inherent to the player's own choice of material and is
  not something the app can or should undo; what the app must not do is *state* the theme, group
  positions under a visible label during training, or otherwise draw attention to the
  relationship.

#### Network and login

- **No connection at import time**: Reported as needing a connection. Everything local continues
  to work, including starting and finishing a session.
- **Login expired**: Lichess tokens are long-lived and there is no refresh token, so expiry is
  presented as logging in again. There is no silent renewal to attempt.
- **Rate limited**: The app backs off rather than retrying immediately, tells the player the
  import can be tried again shortly, and leaves nothing half-imported.
- **The study is gone or was made private**: Reported as not available to this account, not as a
  fault of the app.
- **An address that is not a study**: A game, a profile, an unrelated site. Rejected with a
  message saying what kind of address was expected.
- **The study changes on Lichess after import**: The local collection does not change. Positions
  already trained keep their meaning, and sessions already played keep their own frozen copy.
  Getting the newer version means importing it again.
- **Connection lost mid-fetch**: Nothing half-imported is left behind, and retrying is safe.

#### Storage and sessions

- **A collection deleted while a session using it is unfinished**: The session cannot continue
  without its positions, so deletion forfeits it under the existing warning.
- **Every collection deleted**: The app has nothing to train. It says so and offers import,
  rather than presenting a broken session setup.
- **Storage full during import**: The import fails as a whole, with the reason given, and
  nothing half-imported is left behind.

## Requirements *(mandatory)*

### Functional Requirements

#### Bringing positions in from a file

- **FR-001**: Users MUST be able to import positions from PGN held on the device, with no
  network connection.
- **FR-002**: System MUST accept a PGN containing multiple games or chapters and produce a
  position from each usable entry.
- **FR-003**: System MUST take each entry's declared starting position as where training begins,
  and MUST reject an entry that declares none, stating that reason. A trainable position has to
  say where it starts; a game record does not.
- **FR-004**: System MUST preserve an entry's branching variations as alternatives within the
  solution, rather than reducing them to a single line. A study's variations are most of what
  makes it worth training against.
- **FR-005**: System MUST carry an entry's comments and annotations through to the position, for
  display at review.
- **FR-006**: System MUST reject, with a stated reason, an entry that cannot be trained: one
  whose moves are illegal or unparseable, ~~one with no moves at all,~~ one with no starting
  position, or one in a variant other than standard chess.
  > **Superseded in one clause by feature 005 (FR-001), 2026-08-15.** An entry with a position
  > and no moves is now imported, not rejected: an engine supplies the standard of correctness
  > the author did not. This requirement was right for an app whose only standard was an
  > author's line, and it refused the most natural way a player authors an exercise for
  > themselves — which is how the gap was found, on a real device, with a study made by hand.
  > Every other rejection in this requirement stands unchanged, and feature 005 adds one:
  > a position with no legal move at all.
- **FR-007**: System MUST import the usable entries of a source even when others are rejected,
  and MUST report both outcomes together — how many positions were added, and which entries were
  rejected and why.
- **FR-008**: System MUST NOT partially import an entry. A position is created from a whole
  entry or not at all.
- **FR-009**: Users MUST be able to name a collection at import, and the name MUST NOT be
  required to be unique.
- **FR-010**: System MUST tell the player when the content being imported appears to duplicate a
  collection already present, and MUST let them proceed anyway.

#### Bringing positions in from Lichess

- **FR-011**: Users MUST be able to import a Lichess study by its address, and a public study
  MUST NOT require logging in.
- **FR-012**: Users MUST be able to log in to their Lichess account from the app in order to
  import studies that are not public.
- **FR-013**: Users MUST be able to choose from their own studies once logged in, rather than
  having to know an address.
- **FR-014**: System MUST produce, from a fetched study, a collection that behaves in every way
  like one imported from a file — same rejection rules, same report, same withholding.
- **FR-015**: System MUST make network requests only in direct response to the player asking to
  import or to log in. Nothing MUST fetch on launch, on a timer, in the background, or as a side
  effect of starting a session.
- **FR-016**: System MUST NOT require a network connection to start, run, or review a session,
  and no screen MUST wait on a network request in order to appear.
- **FR-017**: System MUST treat an expired login as an invitation to log in again. There MUST be
  no attempt at silent renewal, because Lichess issues no refresh token and a renewal path
  cannot work.
- **FR-018**: System MUST respect the service's rate limiting by backing off rather than
  retrying immediately, and MUST tell the player the import can be retried.
- **FR-019**: System MUST leave no partial collection behind when a fetch fails for any reason,
  and retrying an import MUST be safe.
- **FR-020**: System MUST report a failed import as a failed import — the player ends up with no
  new positions, never with a broken session, damaged collection, or unusable app.
- **FR-021**: System MUST hold the login credential so that it is not readable by other
  applications and is not carried into device backups, MUST send it only to Lichess, and MUST
  NOT write it to logs or diagnostics.
- **FR-022**: Users MUST be able to disconnect their Lichess account, which forgets the stored
  login and leaves everything already imported in place.
- **FR-023**: System MUST NOT send anything the player has produced — sessions, analyses, grades,
  or timings — anywhere. Network traffic in this feature is fetching content, and nothing else.

#### Withholding what the content carries

- **FR-024**: System MUST treat every piece of text and annotation arriving with an imported
  entry as withheld metadata: chapter and event titles, study names, comments, annotation glyphs
  and numeric annotations, result headers, player names, dates, site and source headers, and any
  header the app does not recognise. All are stored and revealed at review; none may appear on a
  training screen.
- **FR-025**: System MUST withhold unrecognised content by default. Where feature 001 withheld a
  fixed list of fields we authored ourselves, imported content carries text we did not
  anticipate, so the rule MUST be that nothing from the source reaches a training screen unless
  it is the position itself.
- **FR-026**: System MUST NOT display a collection's name, a source file's or study's name, or a
  position's place within its collection on any training screen.
- **FR-027**: System MUST NOT vary anything on a training screen according to which collection a
  position came from, how it was imported, or how many positions the collection holds.
- **FR-028**: System MUST reveal, at review, the imported position's solution, comments,
  annotations and title, as it does for bundled positions.

#### Choosing what to train

- **FR-029**: Users MUST be able to choose which collection a session draws from.
- **FR-030**: System MUST draw every position in a session from the chosen collection.
- **FR-031**: System MUST tell the player when a collection holds fewer positions than the
  session length they asked for, and MUST run the shorter session rather than repeating
  positions within it.
- **FR-032**: System MUST refuse to start a session on a collection with no positions, saying
  why.

#### Managing collections

- **FR-033**: System MUST seed the positions bundled with the app, on first run, as an ordinary
  collection — deletable, renamable, and in every respect like an imported one. It MUST NOT
  reappear after being deleted.
- **FR-034**: Users MUST be able to see every collection with its name, where it came from, when
  it was imported, and how many positions it holds.
- **FR-035**: Users MUST be able to rename a collection.
- **FR-036**: Users MUST be able to delete a collection, after a warning that its positions can
  no longer be trained and that this cannot be undone.
- **FR-037**: System MUST leave sessions already played fully readable after the collection they
  used is deleted, including their solutions and notes, on the strength of the copy each session
  already holds.
- **FR-038**: System MUST warn, when deleting a collection that the unfinished session depends
  on, that the session will be discarded and its answers forfeited — in the same terms as
  abandoning it.
- **FR-039**: System MUST guide the player to import something when no collections remain,
  rather than presenting an empty or broken session setup.

#### Environment

- **FR-040**: Imported collections and positions MUST survive the app being closed and updated.
- **FR-041**: System MUST report a failed import plainly and leave nothing half-imported behind.

### Key Entities

- **Collection**: A named group of positions produced by one import, recording where it came
  from — a file, a Lichess study, or the app itself — and when. Its name is for the player's use
  outside training and is withheld inside it.
- **Imported Position**: One trainable position from one entry of an imported source: its
  starting point, the author's analysis as a solution with variations, and everything else the
  entry carried, held as withheld metadata.
- **Import Report**: The outcome of one import — how many positions were added and which entries
  were rejected, each with a reason. Shown to the player when the import finishes.
- **Lichess Connection**: The fact that the player has logged in, and the credential that proves
  it. Long-lived, not renewable, forgettable on request, and never shared with anything but
  Lichess.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A player can take a study PGN exported from Lichess and be training on its
  positions in under a minute, without consulting documentation.
- **SC-002**: A player who has never logged in can go from opening the app to training on a
  private study of theirs in under three minutes, including the login.
- **SC-003**: Zero elements on any training screen are derived from an imported source's text,
  headers, annotations, or the collection's, file's, or study's name. Verified by exhaustive
  audit and repeated as an automated check that imports content whose every text field is filled
  with distinctive content and asserts none of it is reachable from the training screen.
- **SC-004**: A training screen showing an imported position is indistinguishable from one
  showing a bundled position at the same point, apart from the pieces on the board. Verified by
  an automated check.
- **SC-005**: A real multi-chapter Lichess study imports with every chapter that a human reader
  would call trainable becoming a position, verified against fixture files kept in the
  repository.
- **SC-006**: Every variation present in an imported chapter is present in the solution shown at
  review, verified by comparing the imported result against the source.
- **SC-007**: Importing 100 positions completes in under 10 seconds from a file, with visible
  progress or completion throughout, and never leaves the app unresponsive.
- **SC-008**: 100% of rejected entries are reported with an identifying reference and a reason a
  player can act on. No entry is dropped without mention.
- **SC-009**: Every path outside importing and logging in — starting, running, reviewing,
  resuming a session, browsing history, managing collections — works with the device offline
  throughout, and none of them issues a network request. Verified by running the full training
  flow with networking disabled and by an automated check that no request is made outside an
  explicit import.
- **SC-010**: A study imported from Lichess is fully trainable and reviewable with the device
  offline, verified by importing one and immediately disabling networking.
- **SC-011**: 100% of network failures — offline, timeout, server error, rate limit, expired
  login, missing or private study — produce a message naming what happened and what the player
  can do, and leave zero partial collections behind. Verified case by case.
- **SC-012**: Sessions played against a collection remain fully readable after that collection is
  deleted, verified by deleting one and reopening a session that used it.

## Assumptions

- **PGN is the interchange format** for both sources, because it is what Lichess studies export
  as, what the app already parses for its bundled positions, and what any other source of chess
  content can be converted to. Fetching a study yields PGN and then follows exactly the file
  path, so there is one parser and one set of rejection rules.
- Studies are the only thing fetched from Lichess. Puzzles, games, broadcasts and everything else
  the service offers are separate content models with their own rules — the puzzle ply offset
  described in the constitution being the obvious example — and none of them is needed to answer
  this feature's question.
- A trainable position must declare where it starts. This is why a game record without a
  position header is rejected rather than trained from move 1: the app has no way to know which
  moment in the game was meant to be the exercise.
- Standard chess only. Positions in other variants are rejected at import rather than accepted
  and trained incorrectly.
- Re-importing the same content creates a second collection rather than updating the first. The
  app warns about the apparent duplicate and leaves the decision to the player: updating in place
  would need rules about what happens to a position whose solution changed under a session that
  has already used it, and this feature does not need them. It follows that a study edited on
  Lichess does not change what is already on the device.
- A position belongs to exactly one collection — the import that created it. Positions are not
  moved or copied between collections, and there are no tags, folders, or nesting.
- Collections are not editable content. The player cannot change an imported position's moves,
  comments, or starting square inside the app; to change something they change the source and
  import it again. This app trains against a solution; it is not a study editor.
- Nothing here schedules, orders, or prioritises. Which positions a session takes from the
  chosen collection follows whatever rule 001 already uses; choosing them by past performance is
  a later feature.
- Imported content is kept indefinitely and is not deduplicated automatically. The player deletes
  what they no longer want.
- One user per device, one Lichess account at a time, no profiles. Logging in identifies a
  library to import from; it does not create an account in this app, and nothing about a session
  is associated with it.

## Out of Scope

- Fetching anything from Lichess other than studies — puzzles, games, broadcasts, opening
  explorer, tournament data.
- Sending anything to Lichess: uploading studies, posting results, or associating a session,
  analysis, or grade with the account.
- Background, automatic, scheduled, or startup synchronisation. Every fetch follows an explicit
  request by the player.
- Keeping an imported collection in step with a study that changes on Lichess.
- Editing positions, solutions, comments, or starting positions inside the app.
- Creating a position by hand — setting up a board, entering moves, authoring a solution.
- Importing a played game and choosing a moment in it to train from. Rejected at clarification;
  it would need a way to pick a ply, and that is a feature of its own.
- Tags, folders, nested collections, search, or filtering across collections.
- Moving or copying positions between collections, and merging collections.
- Exporting or sharing anything the app holds.
- Scheduling, spaced repetition, or choosing which positions come next by performance.
- Any cross-session view of how a position has gone before — unchanged from 002, and unchanged
  in reason.
- Automatic detection of what a position is "about": themes, difficulty ratings, or tactical
  motifs computed by the app. Beyond being work this feature does not need, a computed
  difficulty is precisely the kind of evidence Principle I withholds.
