# ScreenSwitch

A macOS menu bar app that turns displays off and on without unplugging them, and gives a display a scaled "looks like" size that macOS does not offer. It has no Dock icon.

Per display, the menu shows:

- the display name with an on/off switch. The switch is disabled when it is the only active display. A display that ScreenSwitch turned off stays in the menu with its switch off, also after a restart.
- a resolution slider from the largest text to the most space. Its steps are Native and the virtual HiDPI sizes from half to the full panel width, at the panel's aspect ratio. Dragging shows the size; the display changes when you release the slider.

Below the displays, "Open at Login" starts ScreenSwitch when you log in.

## Download

Download `ScreenSwitch-<version>.zip` from [Releases](../../releases/latest), unzip it and move `ScreenSwitch.app` to `/Applications`. The app runs on Apple silicon and Intel.

The app is signed ad hoc and not notarized, so Gatekeeper blocks the first launch. Remove the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/ScreenSwitch.app
```

Each release also has `screenswitch-cli` as a tarball and a `SHA256SUMS` file.

## Build

Requires macOS 14 or later and the Xcode command line tools.

```sh
./build-app.sh
```

The script runs `swift build -c release` and writes `build/ScreenSwitch.app` with bundle id `nl.vanraan.screenswitch` and `LSUIElement` set, signed ad hoc.

Run the unit tests with `./test.sh`. It adds the swift-testing paths that the command line tools leave out.

## Install

```sh
ditto build/ScreenSwitch.app /Applications/ScreenSwitch.app
open /Applications/ScreenSwitch.app
```

To start it at login, choose "Open at Login" in the menu. It registers the app as a login item with `SMAppService`, so it also shows up in System Settings > General > Login Items. Register it from the copy in `/Applications`: the login item points at the app the menu runs from.

## How it changes displays

ScreenSwitch uses two private macOS APIs. Either can change or disappear in a macOS update.

- `CGSConfigureDisplayEnabled` from the SkyLight framework turns a display off and on. ScreenSwitch loads it at run time with `dlsym`, so a missing symbol shows an error instead of crashing. A display that is turned off stays off after ScreenSwitch quits. ScreenSwitch remembers it, so the "Turn on" item is back in the menu at the next launch.
- The `CGVirtualDisplay` classes in CoreGraphics create a virtual HiDPI display. `Sources/PrivateDisplay/include/PrivateDisplay.h` declares them. For a virtual size, ScreenSwitch mirrors the panel onto a virtual display at that size. The GPU renders a 2x framebuffer and scales it onto the panel, and the panel keeps its native signal. Each panel gets one virtual display, and ScreenSwitch disables it on Native and reuses it for the next size. Releasing a mirrored virtual display breaks later display changes in the same process on macOS 26.

Quit unmirrors every scaled display. The virtual displays end with the process, so a crash also returns the panels to their own mode.

## Verify on real displays

> **Warning:** this script turns real displays off and on and switches resolutions. Screens go dark and flicker for about 30 seconds. Save your work and do not use the Mac while it runs.

```sh
scripts/verify-displays.sh [EXTERNAL_ID] [BUILTIN_ID]
```

The IDs default to 4 (external) and 1 (built-in). Run `swift run screenswitch-cli status` to see yours, which only reads the display lists. The 2304 × 1440 step assumes an external display that offers that size, such as the 2048 × 1280 Dell U5226KW. The script does one pass:

1. Turn the external display off, then on.
2. Turn the built-in display off, then on.
3. Mirror the external display onto a 2304 × 1440 virtual display, then return to native.

It prints the active display list before and after each step. If a step fails, or you press Ctrl-C, an exit trap ends the scaling process and turns both displays back on.

## Release

Every push to `main` runs the Release workflow. It runs the tests, builds universal binaries (arm64 and x86_64) and publishes a GitHub release with the app zip, the CLI tarball and `SHA256SUMS`. The version is the previous release with the patch number raised by one, starting at v0.1.0. For a minor or major bump, create a release such as `v0.2.0` by hand; the next push continues from there.
