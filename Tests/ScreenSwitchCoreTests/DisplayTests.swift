import Testing
@testable import ScreenSwitchCore

private func display(_ width: Int, _ height: Int, pixels: (Int, Int)) -> PhysicalDisplay {
    PhysicalDisplay(
        id: 1, name: "Test", isBuiltin: false,
        nativeLogical: DisplaySize(width: width, height: height),
        nativePixels: DisplaySize(width: pixels.0, height: pixels.1),
        refreshRate: 60)
}

@Test func dellAt2xOffersEightStepsUpToThePanelWidth() {
    let widths = display(2048, 1280, pixels: (4096, 2560)).scaledSizes.map(\.width)
    #expect(widths == [2304, 2560, 2816, 3072, 3328, 3584, 3840, 4096])
}

@Test func scaledSizesKeepThePanelAspectRatio() {
    let sizes = display(2048, 1280, pixels: (4096, 2560)).scaledSizes
    #expect(sizes.contains(DisplaySize(width: 2304, height: 1440)))
    #expect(sizes.allSatisfy { Double($0.width) / Double($0.height) == 1.6 })
}

@Test func dellAt1xOffers2xAndLeavesOutTheCurrentSize() {
    let sizes = display(3072, 2560, pixels: (3072, 2560)).scaledSizes
    #expect(sizes.map(\.width) == [1536, 1728, 1920, 2112, 2304, 2496, 2688, 2880])
    #expect(sizes.first == DisplaySize(width: 1536, height: 1280))
}

@Test func builtinInAScaledModeUsesThePanelNotTheCurrentMode() {
    let sizes = display(1800, 1169, pixels: (3024, 1964)).scaledSizes
    #expect(sizes.map(\.width) == [1512, 1640, 1768, 1896, 2024, 2152, 2280, 2408, 2536])
    #expect(sizes.first == DisplaySize(width: 1512, height: 982))
}
