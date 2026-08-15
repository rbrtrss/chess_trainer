#!/usr/bin/env bash
#
# Total bytes this app's uid has sent and received, according to Android.
#
# **What it is for.** `no_network_during_training_test.dart` proves the app does
# not *call* the Lichess client outside an explicit import or login. This proves
# the whole installed app did not put anything on the wire — which is a
# different claim, and the one SC-004 and SC-009 actually make.
#
# It is better than packet inspection for this, because it attributes traffic to
# this app rather than to the device. A proxy sees the phone; this sees the uid.
#
# Read it, do the thing, read it again:
#
#   before=$(./tools/device/netbytes.sh)
#   ./tools/device/drive.sh stop && ./tools/device/drive.sh launch
#   after=$(./tools/device/netbytes.sh)
#   echo $(( after - before ))
#
# On 2026-08-15 that was **0** across four cold starts with an account
# connected and a username on screen, and 11,448 for the one action that should
# fetch — the study picker. Always take the second number too. A counter that
# never moves is indistinguishable from a counter that does not work, and the
# fetch is the control that tells them apart.

set -euo pipefail

[ -d "$HOME/Android/Sdk/platform-tools" ] && PATH="$HOME/Android/Sdk/platform-tools:$PATH"
export PATH

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PKG="${PKG:-$(sed -nE 's/.*applicationId *= *"([^"]+)".*/\1/p' \
  "$ROOT/android/app/build.gradle.kts" | head -1)}"

# Resolve the uid from the package, so this cannot be pointed at the wrong app
# by a stale number — and so it keeps working across reinstalls.
UID_APP="${UID_APP:-$(adb shell dumpsys package "$PKG" 2>/dev/null \
  | grep -m1 -oE 'userId=[0-9]+' | grep -oE '[0-9]+')}"
[ -n "$UID_APP" ] || { echo "could not resolve uid for $PKG — is it installed?" >&2; exit 2; }

# Ask the stats service to flush first: the counters are polled, and reading
# them without this can miss traffic that has just happened.
adb shell dumpsys netstats poll >/dev/null 2>&1 || true

adb shell dumpsys netstats detail 2>/dev/null \
  | awk -v uid="uid=$UID_APP " '
      index($0, uid)          { inblock = 1; next }
      /uid=/ && !index($0, uid) { inblock = 0 }
      inblock && /rb=/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^rb=/) { sub(/^rb=/, "", $i); rx += $i }
          if ($i ~ /^tb=/) { sub(/^tb=/, "", $i); tx += $i }
        }
      }
      END { printf "%d\n", rx + tx }'
