#!/usr/bin/env python3
"""Check the icon macOS loads from a built or installed app bundle."""
import plistlib
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

app = Path(sys.argv[1] if len(sys.argv) > 1 else "build/ScreenSwitch.app")
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
name = info.get("CFBundleIconFile")
assert name, f"{app}: missing CFBundleIconFile"
icon = app / "Contents/Resources" / name
if not icon.suffix:
    icon = icon.with_suffix(".icns")
assert icon.is_file(), f"{app}: missing icon resource {icon.name}"

with tempfile.TemporaryDirectory(prefix="screenswitch-icon-check-") as temp:
    iconset = Path(temp) / "AppIcon.iconset"
    subprocess.run(["iconutil", "-c", "iconset", "-o", str(iconset), str(icon)], check=True)
    for points in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            suffix = "@2x" if scale == 2 else ""
            png = (iconset / f"icon_{points}x{points}{suffix}.png").read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n"
            assert struct.unpack(">II", png[16:24]) == (points * scale, points * scale)
print(f"{app}: valid app icon at all ten macOS sizes")
