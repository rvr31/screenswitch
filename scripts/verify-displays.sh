#!/bin/sh
# Exercises every DisplayManager operation on the real displays. Screens go
# dark and flicker while it runs. Usage: scripts/verify-displays.sh [EXTERNAL_ID] [BUILTIN_ID]
set -u
cd "$(dirname "$0")/.."
EXTERNAL=${1:-4}
BUILTIN=${2:-1}
swift build -c release --product screenswitch-cli >/dev/null || exit 1
CLI="$(swift build -c release --show-bin-path)/screenswitch-cli"

observe() {
    echo "  [observer: $1]"
    "$CLI" status | grep -E "active=|id=|turnedOff="
}

echo "== off/on $EXTERNAL, each in a fresh process (on reads the persisted list)"
"$CLI" off "$EXTERNAL"; sleep 3; observe "after off"
"$CLI" menu | grep "Turn on"
"$CLI" on "$EXTERNAL"; sleep 3; observe "after on"

echo "== off/on $BUILTIN"
"$CLI" off "$BUILTIN"; sleep 3; observe "after off"
"$CLI" on "$BUILTIN"; sleep 3; observe "after on"

echo "== last active display cannot be turned off"
"$CLI" off "$EXTERNAL" off "$BUILTIN"
"$CLI" on "$EXTERNAL"; sleep 3; observe "after on"

echo "== one process: virtual 2304x1440 on $EXTERNAL, replaced by 1920x1200, native, 2304x1440 again, native"
"$CLI" scale "$EXTERNAL" 2304x1440 wait 4 scale "$EXTERNAL" 1920x1200 wait 4 native "$EXTERNAL" wait 4 \
    scale "$EXTERNAL" 2304x1440 wait 4 native "$EXTERNAL" wait 4 &
sleep 3; observe "2304x1440"
sleep 4; observe "1920x1200"
sleep 4; observe "native"
sleep 4; observe "2304x1440 again"
sleep 4; observe "native, scaling process still alive"
wait

echo "== turning off a scaled display restores it first"
"$CLI" scale "$EXTERNAL" 2304x1440 wait 3 off "$EXTERNAL" wait 3 status on "$EXTERNAL" wait 3 status | grep -E "^>|error|active=|DELL|turnedOff"

echo "== virtual size on the built-in display"
"$CLI" scale "$BUILTIN" 1544x1003 wait 4 native "$BUILTIN" wait 3 &
sleep 3; observe "1544x1003"
sleep 4; observe "native"
wait

echo "== process exits while scaled (restoreAll, the app's quit path)"
"$CLI" scale "$EXTERNAL" 2304x1440 wait 3 &
sleep 2; observe "scaled"
wait; sleep 2; observe "after exit"

echo "== process dies while scaled (no restoreAll)"
"$CLI" scale "$EXTERNAL" 2304x1440 wait 3 crash &
sleep 2; observe "scaled"
wait; sleep 2; observe "after crash"
