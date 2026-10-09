#!/bin/sh
# Runs the unit tests. With Command Line Tools only, swift-testing lives in a
# framework directory that `swift test` does not search on its own.
set -eu
cd "$(dirname "$0")/.."
D=/Library/Developer/CommandLineTools/Library/Developer
exec swift test -Xswiftc -F"$D/Frameworks" \
    -Xlinker -F"$D/Frameworks" -Xlinker -rpath -Xlinker "$D/Frameworks" \
    -Xlinker -rpath -Xlinker "$D/usr/lib" "$@"
