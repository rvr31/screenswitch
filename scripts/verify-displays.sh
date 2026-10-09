#!/bin/sh
# One pass over every display operation on the real displays, about 45 seconds.
# Screens go dark and flicker while it runs. Whatever fails, the exit trap
# turns both displays back on and drops the virtual display.
# Usage: scripts/verify-displays.sh [EXTERNAL_ID] [BUILTIN_ID]
set -eu
cd "$(dirname "$0")/.."
EXTERNAL=${1:-4}
BUILTIN=${2:-1}
swift build -c release --product screenswitch-cli >/dev/null
CLI="$(swift build -c release --show-bin-path)/screenswitch-cli"
SCALER=

observe() {
    echo "  [$1]"
    "$CLI" status | grep -E "active=|id=|turnedOff="
}

is_active() {
    "$CLI" status | grep -Eq "active=\[([0-9]+, )*$1(, [0-9]+)*\]"
}

restore() {
    status=$?
    trap - EXIT INT TERM
    set +e
    echo "== restore"
    # The virtual display and its mirror end with the process that owns them.
    if [ -n "$SCALER" ]; then
        kill "$SCALER" 2>/dev/null
        wait "$SCALER" 2>/dev/null
        sleep 2
    fi
    for id in "$EXTERNAL" "$BUILTIN"; do
        is_active "$id" || "$CLI" on "$id"
    done
    sleep 2
    observe "after restore"
    exit "$status"
}
trap restore EXIT
trap 'exit 130' INT TERM

step() {
    label=$1
    shift
    echo "== $label"
    observe "before"
    "$CLI" "$@"
    sleep 3
    observe "after"
}

step "turn off $EXTERNAL" off "$EXTERNAL"
step "turn on $EXTERNAL" on "$EXTERNAL"
step "turn off $BUILTIN" off "$BUILTIN"
step "turn on $BUILTIN" on "$BUILTIN"

echo "== virtual on $EXTERNAL: 2304x1440, resize to 1920x1200, native, 2304x1440 again, native"
observe "before"
"$CLI" scale "$EXTERNAL" 2304x1440 wait 3 status \
    scale "$EXTERNAL" 1920x1200 wait 3 status \
    native "$EXTERNAL" wait 3 status \
    scale "$EXTERNAL" 2304x1440 wait 3 status \
    native "$EXTERNAL" &
SCALER=$!
wait "$SCALER"
SCALER=
sleep 3
observe "native"
