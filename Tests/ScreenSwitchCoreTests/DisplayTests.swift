import Testing
@testable import ScreenSwitchCore

private func display(_ width: Int, _ height: Int) -> PhysicalDisplay {
    PhysicalDisplay(
        id: 1, name: "Test", isBuiltin: false,
        nativeLogical: DisplaySize(width: width, height: height),
        nativePixels: DisplaySize(width: width * 2, height: height * 2),
        refreshRate: 60)
}

@Test func dellOffersFourSizesEachSideOfNative() {
    let widths = display(2048, 1280).scaledSizes.map(\.width)
    #expect(widths == [1536, 1664, 1792, 1920, 2176, 2304, 2432, 2560])
}

@Test func scaledSizesKeepTheAspectRatio() {
    let sizes = display(2048, 1280).scaledSizes
    #expect(sizes.contains(DisplaySize(width: 2304, height: 1440)))
    #expect(sizes.allSatisfy { Double($0.width) / Double($0.height) == 1.6 })
}

@Test func builtinRoundsHeightAndStaysWithinRange() {
    let sizes = display(1800, 1169).scaledSizes
    #expect(sizes.map(\.width) == [1416, 1544, 1672, 1928, 2056, 2184])
    #expect(sizes.first == DisplaySize(width: 1416, height: 920))
    #expect(sizes.allSatisfy { $0.width >= 1350 && $0.width <= 2250 })
}
