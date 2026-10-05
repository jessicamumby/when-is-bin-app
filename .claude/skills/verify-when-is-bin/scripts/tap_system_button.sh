#!/usr/bin/env bash
# Taps an iOS system alert button (e.g. "Allow" on the notification permission
# prompt) on ONE simulator, by its visible label. The Flutter test cannot see
# OS alerts and `simctl privacy` has no notifications service, so this is the
# real user tap, done from the host:
#   1. polls `xcrun simctl io <udid> screenshot` until Vision OCR finds a line
#      exactly equal to <label> (so "Allow" never matches "Don't Allow");
#   2. maps that point into the Simulator window titled "<device> – iOS <ver>"
#      (found via System Events, so it never clicks another simulator's window);
#   3. clicks it with System Events, then re-screenshots to confirm the label is gone.
# Coordinates come from a fresh screenshot every time, never hard-coded.
# Needs: Accessibility permission for the terminal (System Events), the
# simulator's window visible on the current Space.
# Usage: [TAP_DELAY=<s>] tap_system_button.sh <udid> <label> [timeout-seconds=60] [evidence-dir]
#   e.g. TAP_DELAY=8 tap_system_button.sh "$UDID" Allow 240 "$RUN_DIR"
#   TAP_DELAY waits that long after the label appears before tapping, like a
#   user reading the alert (the app stops waiting for the verdict after 5s).
# Exit: 0 tapped and gone, 3 label never appeared, 4 window not found, 5 still there after tap.
set -uo pipefail
UDID="$1"; LABEL="$2"; TIMEOUT="${3:-60}"; OUT="${4:-$(mktemp -d)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OCR="${TMPDIR:-/tmp}/verify-when-is-bin-ocr"
[ -x "$OCR" ] || xcrun swiftc -O -o "$OCR" "$HERE/ocr.swift" || { echo "FAIL: could not build OCR helper"; exit 1; }

IFS=$'\t' read -r NAME VER < <(xcrun simctl list devices -j | python3 -c '
import json, sys
for rt, devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["udid"] == sys.argv[1]:
            print(d["name"] + "\t" + rt.rsplit("iOS-", 1)[-1].replace("-", "."))
' "$UDID")
[ -n "${VER:-}" ] || { echo "FAIL: no simulator $UDID"; exit 4; }
TITLE="$NAME – iOS $VER"

# Find and raise the window once, before polling, so the tap follows the alert
# within about a second (the app stops waiting for the verdict after 5 s).
# Geometry is read BEFORE raising: raising reorders `windows`, so an index
# reference taken in a loop would then point at a different simulator.
geo=$(osascript -e "
tell application \"Simulator\" to activate
tell application \"System Events\" to tell process \"Simulator\"
  set matches to (every window whose name is \"$TITLE\")
  if (count of matches) is not 1 then return \"\"
  set w to item 1 of matches
  set p to position of group 1 of w
  set s to size of group 1 of w
  perform action \"AXRaise\" of w
  return ((item 1 of p) as string) & \" \" & ((item 2 of p) as string) & \" \" & ((item 1 of s) as string) & \" \" & ((item 2 of s) as string)
end tell" 2>&1)
read -r GX GY GW GH <<<"$geo"
[ -n "${GH:-}" ] || { echo "WINDOW NOT FOUND: no visible Simulator window titled \"$TITLE\" ($geo). Open it via Simulator > Window, on this Space."; exit 4; }


shot="$OUT/alert-$(date +%H%M%S).png"
end=$(( $(date +%s) + TIMEOUT )); hit=""
while [ "$(date +%s)" -lt "$end" ]; do
  xcrun simctl io "$UDID" screenshot "$shot" >/dev/null 2>&1
  hit=$("$OCR" "$shot" | awk -F'\t' -v l="$LABEL" '$1 == l { print $2, $3; exit }')
  [ -n "$hit" ] && break
  sleep 0.3
done
[ -n "$hit" ] || { echo "NOT FOUND: \"$LABEL\" did not appear on $UDID within ${TIMEOUT}s (last screen: $shot)"; exit 3; }
read -r PX PY <<<"$hit"
echo "seen \"$LABEL\" at $(date +%H:%M:%S) ($shot)"
if [ "${TAP_DELAY:-0}" -gt 0 ]; then sleep "$TAP_DELAY"; fi
read -r W H < <(sips -g pixelWidth -g pixelHeight "$shot" | awk '/pixel/ { printf "%s ", $2 }')

X=$(python3 -c "print(round($GX + $PX * $GW / $W))"); Y=$(python3 -c "print(round($GY + $PY * $GH / $H))")
echo "found \"$LABEL\" at pixel $PX,$PY in $shot; clicking screen point $X,$Y in \"$TITLE\""
# System Events (not cliclick): its clicks reach the simulated screen; cliclick
# moves the pointer but its click did not register in the Simulator window.
osascript -e "tell application \"System Events\" to click at {$X, $Y}" >/dev/null
sleep 2
after="$OUT/alert-after-$(date +%H%M%S).png"
xcrun simctl io "$UDID" screenshot "$after" >/dev/null 2>&1
if "$OCR" "$after" | awk -F'\t' -v l="$LABEL" '$1 == l { f=1 } END { exit !f }'; then
  echo "STILL THERE: \"$LABEL\" visible after the tap ($after)"; exit 5
fi
echo "TAPPED: \"$LABEL\" gone ($after)"
