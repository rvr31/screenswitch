#!/bin/sh
# One pass over profile switching on the real displays, about 30 seconds.
# Screens go dark and flicker while it runs. Whatever fails, the exit trap
# returns to the starting setup and deletes the verify-* profiles.
# Usage: scripts/verify-profiles.sh [EXTERNAL_ID] [BUILTIN_ID]
set -eu
cd "$(dirname "$0")/.."
# A running app owns its own virtual displays and mirrors, which this script
# cannot see or undo.
if pgrep -f "ScreenSwitch.app/Contents/MacOS/ScreenSwitch" >/dev/null; then
    echo "Quit the ScreenSwitch app first." >&2
    exit 1
fi
EXTERNAL=${1:-4}
BUILTIN=${2:-1}
swift build -c release --product screenswitch-cli >/dev/null
CLI="$(swift build -c release --show-bin-path)/screenswitch-cli"
SWITCHER=

# Online, not active: a mirrored display is missing from the active list but is on.
is_online() {
    "$CLI" status | grep -Eq "online=\[([0-9]+, )*$1(, [0-9]+)*\]"
}

restore() {
    status=$?
    trap - EXIT INT TERM
    set +e
    echo "== restore"
    # The virtual display and its mirror end with the process that owns them.
    if [ -n "$SWITCHER" ]; then
        kill "$SWITCHER" 2>/dev/null
        wait "$SWITCHER" 2>/dev/null
        sleep 2
    fi
    is_online "$EXTERNAL" || "$CLI" on "$EXTERNAL"
    "$CLI" apply verify-start
    for name in verify-start verify-both verify-desk verify-scaled; do
        "$CLI" delete "$name" >/dev/null
    done
    sleep 2
    "$CLI" status profiles
    exit "$status"
}
trap restore EXIT
trap 'exit 130' INT TERM

echo "== save the starting setup"
"$CLI" status save verify-start
is_online "$BUILTIN" || "$CLI" on "$BUILTIN"
SIZE=$("$CLI" sizes "$EXTERNAL" | sed -n 2p)

echo "== save desk (built-in off) and scaled ($EXTERNAL at $SIZE), then switch: both, scaled, desk, desk again"
"$CLI" save verify-both \
    off "$BUILTIN" save verify-desk \
    scale "$EXTERNAL" "$SIZE" wait 2 save verify-scaled profiles \
    apply verify-both wait 3 status profiles \
    apply verify-scaled wait 3 status profiles \
    apply verify-desk wait 3 status profiles \
    apply verify-desk status profiles &
SWITCHER=$!
wait "$SWITCHER"
SWITCHER=
