import CoreGraphics
import Foundation
import Testing
@testable import ScreenSwitchCore

private let builtin = PhysicalDisplay(
    id: 1, name: "Built-in Retina Display", isBuiltin: true,
    nativeLogical: DisplaySize(width: 1800, height: 1169),
    nativePixels: DisplaySize(width: 3600, height: 2338), refreshRate: 120)
private let dell = PhysicalDisplay(
    id: 4, name: "DELL U5226KW", isBuiltin: false,
    nativeLogical: DisplaySize(width: 2048, height: 1280),
    nativePixels: DisplaySize(width: 4096, height: 2560), refreshRate: 120)

private func entries(
    _ displays: [PhysicalDisplay],
    virtual: [CGDirectDisplayID: DisplaySize] = [:],
    off: [RememberedOff] = [],
    opensAtLogin: Bool = false,
    update: UpdateState? = nil
) -> [MenuEntry] {
    MenuModel.entries(displays: displays, virtualSizes: virtual, turnedOff: off, opensAtLogin: opensAtLogin, update: update)
}

private func entryAboveOpenAtLogin(_ update: UpdateState?) -> MenuEntry? {
    let all = entries([builtin], update: update)
    guard let index = all.firstIndex(where: { if case .item("Open at Login", _, _) = $0 { true } else { false } }),
          index > 0
    else { return nil }
    return all[index - 1]
}

private func slider(for name: String, in entries: [MenuEntry]) -> (steps: [ResolutionStep], selected: Int)? {
    for case let .resolution(display, steps, selected) in entries where display == name { return (steps, selected) }
    return nil
}

@Test func theOnlyDisplayShowsOnWithADisabledSwitch() {
    #expect(entries([builtin]).contains(.display(name: builtin.name, isOn: true, toggle: nil)))
}

@Test func eachDisplaySwitchesOffWhenTwoAreActive() {
    let all = entries([builtin, dell])
    #expect(all.contains(.display(name: builtin.name, isOn: true, toggle: .turnOff(1))))
    #expect(all.contains(.display(name: dell.name, isOn: true, toggle: .turnOff(4))))
}

@Test func sliderRunsFromNativeToThePanelWidthAndSelectsNative() throws {
    let (steps, selected) = try #require(slider(for: dell.name, in: entries([builtin, dell])))
    #expect(steps.map(\.size.width) == [2048, 2304, 2560, 2816, 3072, 3328, 3584, 3840, 4096])
    #expect(steps[selected] == ResolutionStep(size: dell.nativeLogical, action: .setNative(4)))
    #expect(steps[selected].title == "2048 × 1280 (Native)")
    #expect(steps[1].action == .setVirtual(4, DisplaySize(width: 2304, height: 1440)))
}

@Test func sliderSelectsTheActiveVirtualSize() throws {
    let size = DisplaySize(width: 2304, height: 1440)
    let (steps, selected) = try #require(slider(for: dell.name, in: entries([builtin, dell], virtual: [4: size])))
    #expect(steps[selected].size == size)
}

@Test func nativeSortsAmongTheVirtualSizesByWidth() throws {
    let scaledBuiltin = PhysicalDisplay(
        id: 1, name: "Built-in Retina Display", isBuiltin: true,
        nativeLogical: DisplaySize(width: 1800, height: 1169),
        nativePixels: DisplaySize(width: 3024, height: 1964), refreshRate: 120)
    let (steps, selected) = try #require(slider(for: scaledBuiltin.name, in: entries([scaledBuiltin])))
    #expect(steps.map(\.size.width) == [1512, 1640, 1768, 1800, 1896, 2024, 2152, 2280, 2408, 2536])
    #expect(steps[selected].action == .setNative(1))
}

@Test func rememberedDisplaysShowOffWithoutASlider() {
    let off = RememberedOff(id: 4, name: dell.name)
    let all = entries([builtin], off: [off])
    #expect(all.contains(.display(name: dell.name, isOn: false, toggle: .turnOn(4))))
    #expect(slider(for: dell.name, in: all) == nil)
    #expect(!entries([builtin]).contains { if case .display(_, false, _) = $0 { true } else { false } })
}

@Test func openAtLoginIsCheckedWhenRegistered() {
    #expect(entries([builtin], opensAtLogin: true).contains(.item("Open at Login", action: .toggleOpenAtLogin, checked: true)))
    #expect(entries([builtin]).contains(.item("Open at Login", action: .toggleOpenAtLogin, checked: false)))
}

@Test func updateItemFollowsTheUpdateState() throws {
    let version = try #require(Version("0.2.0"))
    let url = try #require(URL(string: "https://example.com"))
    let update = AvailableUpdate(version: version, archive: url, checksums: url, page: url)
    #expect(entryAboveOpenAtLogin(.idle) == .item("Check for Updates…", action: .checkForUpdates))
    #expect(entryAboveOpenAtLogin(.checking) == .item("Checking for Updates…", action: nil))
    #expect(entryAboveOpenAtLogin(.available(update)) == .item("Install ScreenSwitch 0.2.0…", action: .installUpdate))
    #expect(entryAboveOpenAtLogin(.installing(version)) == .item("Installing ScreenSwitch 0.2.0…", action: nil))
}

@Test func noUpdateItemWithoutAVersion() {
    #expect(entryAboveOpenAtLogin(nil) == .separator)
}
