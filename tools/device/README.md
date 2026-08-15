# Device-pass tools

Two scripts for verifying this app on a real Android phone. They exist because
three of the four defects features 003 and 004 shipped were found on hardware
and none was found by the suite — and because the phone in question is somebody's
actual phone.

| | |
|---|---|
| [`drive.sh`](./drive.sh) | Read and tap the app, refusing to capture anything that is not the app |
| [`netbytes.sh`](./netbytes.sh) | How many bytes this app's uid has actually put on the wire |

## The rule that matters

**Nothing is captured unless the app is verifiably in front.** Feature 003's
device pass was stopped after a back-press left the app and the next screenshot
caught the device owner's personal messages — twice, and the artifacts had to be
deleted from host and device.

So `drive.sh` reads `topResumedActivity` immediately before every dump and
refuses otherwise. Two habits go with it:

- **Prove the guard before trusting it.** Press HOME, run `guard`, watch it
  refuse. A guard nobody has seen fail is a guard nobody knows works. This is
  the same reason `no_network_during_training_test.dart` has a control case.
- **Prefer `text` to screenshots.** It returns content and never a pixel, so
  nothing personal can survive in the output — and it is what a screen reader
  would announce, which is what the Principle I checks actually need. Reach for
  a screenshot only when the question is visual, like whether a bar is clipped.

`ALLOW_EXTRA` widens the guard to one more package, for driving the system file
picker. It is refused on the primary user: a secondary user created for a test
has never held anyone's data, and user 0 is where the owner's life is.

## Two things that cost an hour each

Both are guarded against in the scripts; they are written down because the next
person will otherwise rediscover them the same way.

**`uiautomator` writes single-quoted attributes.** When a label contains a double
quote — `This looks like "Endgames", which you already have.` — the attribute
comes back as `content-desc='...'`, and a `content-desc="[^"]*"` pattern drops it
without a word. That made a *correct* duplicate warning look like a missing
widget and sent a defect hunt in the wrong direction. `drive.sh` parses the XML
instead of grepping it, so the class of bug is gone rather than handled.

**Coordinates go stale instantly.** The phone rotates; layouts reflow; a node
scrolled out of view reports zero bounds and a tap on its "centre" silently hits
(0,0). `taptext` re-reads bounds every time and refuses on zero bounds with a
message telling you to scroll. Never carry a coordinate between commands.

## A fresh install without wiping anything

Feature 004's T039 needed a never-connected first launch, on a phone holding two
collections and six sessions of real history. Android's multi-user support gives
it for free — a secondary user has its own data directory, so the app cannot tell
the difference:

```bash
adb shell pm create-user t039              # prints a user id, e.g. 10
adb shell am start-user 10
adb shell pm install-existing --user 10 dev.chesstrainer.chess_trainer
adb shell am switch-user 10                # takes the screen; reversible
# ... run the scenario ...
adb shell am switch-user 0
adb shell pm remove-user 10
```

Switching back leaves the phone on its lock screen, which is expected.

**What this cannot do is test the file picker.** `adb push` writes to user 0
whatever the foreground user is, and copying across users is refused, so there is
no way to put a PGN where a secondary user's picker can see it. Exercising
`file_selector` needs a file already in the profile under test, which in practice
means the owner picking it by hand — which is the right division of labour
anyway, since browsing someone's file picker means reading their files.

## Things worth not doing

- **Do not tap Disconnect on the owner's account without asking.** `logOut()`
  revokes the token server-side, and getting back needs their credentials in a
  browser.
- **Do not try to induce a `429`.** It means deliberately hammering Lichess,
  which this app is built not to do — requests are serialised and there is no
  retry loop precisely so the limit is never approached. That row of the error
  contract is recorded as not reproducible, and that is the honest answer.
