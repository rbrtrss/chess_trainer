#!/usr/bin/env bash
#
# Drive the app on an attached Android device, without ever capturing anything
# that is not the app.
#
# **Why this exists.** Feature 003's device pass was stopped after a back-press
# left the app and the next screenshot caught the device owner's personal
# messages — twice. The phone these features are verified on is somebody's
# actual phone. So every capture here is gated on the foreground package being
# ours, checked immediately before the capture, and the script refuses and exits
# non-zero rather than capturing anything else.
#
# Prove the guard before trusting it: press HOME, run `guard`, and watch it
# refuse. A guard nobody has seen fail is a guard nobody knows works.
#
#   ./tools/device/drive.sh guard          # is our app in front?
#   ./tools/device/drive.sh text           # everything a screen reader announces
#   ./tools/device/drive.sh dump           # the raw UI hierarchy
#   ./tools/device/drive.sh taptext "Start"
#   ./tools/device/drive.sh launch [seconds]
#   ./tools/device/drive.sh stop
#
# `text` is the one to reach for. It is content only, never a pixel, so nothing
# personal can survive in the output — and it is also exactly what a screen
# reader would say, which is what the Principle I checks actually need. Feature
# 003's device pass found its worst near-miss this way rather than by eye.

set -euo pipefail

[ -d "$HOME/Android/Sdk/platform-tools" ] && PATH="$HOME/Android/Sdk/platform-tools:$PATH"
export PATH

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Read the id from the build file rather than repeating it here, so a rename
# cannot leave this script guarding the wrong package — which would fail open.
PKG="${PKG:-$(sed -nE 's/.*applicationId *= *"([^"]+)".*/\1/p' \
  "$ROOT/android/app/build.gradle.kts" | head -1)}"
[ -n "$PKG" ] || { echo "could not read applicationId" >&2; exit 2; }

foreground() {
  adb shell dumpsys activity activities 2>/dev/null \
    | grep -m1 'topResumedActivity' \
    | sed -E 's/.*ActivityRecord\{[^ ]+ [^ ]+ ([^ /]+)\/.*/\1/'
}

current_user() { adb shell am get-current-user 2>/dev/null | tr -d '\r\n'; }

# ALLOW_EXTRA widens the guard to one more package — the system file picker,
# say, which has to be driven to exercise `file_selector` and which is worse to
# drive blind than to look at.
#
# It is refused on the primary user. A secondary user created for a test has
# never held anyone's data; user 0 is where the owner's life is.
guard() {
  local fg
  fg="$(foreground)"

  if [ -n "${ALLOW_EXTRA:-}" ] && [ "$fg" = "$ALLOW_EXTRA" ]; then
    local user
    user="$(current_user)"
    if [ "$user" = "0" ]; then
      echo "ABORT: ALLOW_EXTRA is not permitted on the primary user — that is" \
           "where the owner's data is" >&2
      return 1
    fi
    return 0
  fi

  if [ "$fg" != "$PKG" ]; then
    echo "ABORT: foreground is '${fg:-<none>}', not $PKG — refusing to capture" >&2
    return 1
  fi
}

# Pull the hierarchy to stdout. Callers parse it; see `_parse` for why not grep.
_dump_xml() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb shell cat /sdcard/ui.xml
  adb shell rm -f /sdcard/ui.xml
}

# **Parse the XML, do not grep it.** `uiautomator` writes attributes with single
# quotes when the value itself contains a double quote — so a message like
#   This looks like "Endgames", which you already have.
# comes out as content-desc='...' and a `content-desc="[^"]*"` pattern drops it
# silently. That cost an hour on 2026-08-15 and made a correct duplicate warning
# look like a missing widget. A real parser cannot make that mistake.
_parse() {
  python3 -c '
import sys, xml.etree.ElementTree as ET
mode = sys.argv[1]
want = sys.argv[2] if len(sys.argv) > 2 else None
root = ET.fromstring(sys.stdin.read())
for node in root.iter("node"):
    # Flutter publishes its semantics as content-desc; native views use text.
    label = node.get("content-desc") or node.get("text") or ""
    if not label:
        continue
    if mode == "text":
        print(label)
    elif mode == "bounds" and label == want:
        print(node.get("bounds", ""))
        break
' "$@"
}

case "${1:-}" in
  fg)    foreground ;;
  guard) guard && echo "OK: $PKG in foreground" ;;
  dump)  guard || exit 1; _dump_xml ;;
  text)  guard || exit 1; _dump_xml | _parse text ;;

  tap)
    guard || exit 1
    adb shell input tap "$2" "$3"
    sleep "${4:-1}"
    ;;

  # Tap the centre of the first node whose label is exactly $2.
  #
  # Bounds are read fresh every time on purpose. The phone rotates, layouts
  # reflow, and a coordinate remembered from three commands ago lands somewhere
  # useless — usually (0,0), because a node scrolled out of view reports zero
  # bounds and the tap silently hits the corner. If this says "not on screen",
  # scroll first; do not reach for a remembered coordinate.
  taptext)
    guard || exit 1
    bounds="$(_dump_xml | _parse bounds "$2")"
    [ -n "$bounds" ] || { echo "no node labelled '$2'" >&2; exit 1; }
    read -r x1 y1 x2 y2 <<<"$(echo "$bounds" | grep -o '[0-9]\+' | tr '\n' ' ')"
    if [ "$x1" = "0" ] && [ "$y1" = "0" ] && [ "$x2" = "0" ] && [ "$y2" = "0" ]; then
      echo "'$2' has zero bounds — it is not on screen; scroll to it first" >&2
      exit 1
    fi
    adb shell input tap $(( (x1 + x2) / 2 )) $(( (y1 + y2) / 2 ))
    sleep "${3:-1}"
    ;;

  launch)
    adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep "${2:-3}"
    guard && echo "launched"
    ;;

  stop) adb shell am force-stop "$PKG"; echo "stopped" ;;

  *)
    echo "usage: $(basename "$0") {fg|guard|dump|text|tap X Y [s]|taptext LABEL [s]|launch [s]|stop}" >&2
    exit 2
    ;;
esac
