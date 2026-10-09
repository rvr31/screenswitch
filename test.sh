#!/bin/sh
# Command Line Tools ship swift-testing outside the default search paths.
set -e
D=/Library/Developer/CommandLineTools/Library/Developer
exec swift test \
  -Xswiftc -F"$D/Frameworks" \
  -Xlinker -F"$D/Frameworks" \
  -Xlinker -rpath -Xlinker "$D/Frameworks" \
  -Xlinker -rpath -Xlinker "$D/usr/lib" "$@"
