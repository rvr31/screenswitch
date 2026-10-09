import CoreGraphics
import Testing
@testable import ScreenSwitchCore

private let dell = PhysicalDisplay(
    id: 4, name: "DELL U5226KW", isBuiltin: false,
    nativeLogical: DisplaySize(width: 2048, height: 1280),
    nativePixels: DisplaySize(width: 4096, height: 2560), refreshRate: 120)
private let remembered = [
    RememberedOff(id: 1, name: "Built-in Retina Display"),
    RememberedOff(id: 5, name: "LG UltraFine"),
]

@Test func everyRememberedDisplayTurnsOnWhenNoneIsOnline() {
    #expect(RememberedOff.toRecover(online: [], turnedOff: remembered) == [1, 5])
}

@Test func nothingTurnsOnWhileADisplayIsOnline() {
    #expect(RememberedOff.toRecover(online: [dell], turnedOff: remembered) == [])
}
