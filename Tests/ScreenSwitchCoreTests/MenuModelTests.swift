import CoreGraphics
import Testing
@testable import ScreenSwitchCore

private let builtin = PhysicalDisplay(
    id: 1, key: DisplayKey(vendor: 0x610, model: 1, serial: 0), name: "Built-in Retina Display", isBuiltin: true,
    nativeLogical: DisplaySize(width: 1800, height: 1169),
    nativePixels: DisplaySize(width: 3600, height: 2338), refreshRate: 120)
private let dell = PhysicalDisplay(
    id: 4, key: DisplayKey(vendor: 0x10ac, model: 2, serial: 7), name: "DELL U5226KW", isBuiltin: false,
    nativeLogical: DisplaySize(width: 2048, height: 1280),
    nativePixels: DisplaySize(width: 4096, height: 2560), refreshRate: 120)

private func entries(
    _ displays: [PhysicalDisplay],
    virtual: [CGDirectDisplayID: DisplaySize] = [:],
    off: [RememberedOff] = [],
    profiles: [String] = [],
    active: String? = nil,
    opensAtLogin: Bool = false
) -> [MenuEntry] {
    MenuModel.entries(
        displays: displays, virtualSizes: virtual, turnedOff: off,
        profiles: profiles.map { Profile(name: $0, targets: [dell.key: .native]) }, activeProfile: active,
        opensAtLogin: opensAtLogin)
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
        id: 1, key: builtin.key, name: "Built-in Retina Display", isBuiltin: true,
        nativeLogical: DisplaySize(width: 1800, height: 1169),
        nativePixels: DisplaySize(width: 3024, height: 1964), refreshRate: 120)
    let (steps, selected) = try #require(slider(for: scaledBuiltin.name, in: entries([scaledBuiltin])))
    #expect(steps.map(\.size.width) == [1512, 1640, 1768, 1800, 1896, 2024, 2152, 2280, 2408, 2536])
    #expect(steps[selected].action == .setNative(1))
}

@Test func rememberedDisplaysShowOffWithoutASlider() {
    let off = RememberedOff(id: 4, name: dell.name, key: dell.key)
    let all = entries([builtin], off: [off])
    #expect(all.contains(.display(name: dell.name, isOn: false, toggle: .turnOn(4))))
    #expect(slider(for: dell.name, in: all) == nil)
    #expect(!entries([builtin]).contains { if case .display(_, false, _) = $0 { true } else { false } })
}

@Test func openAtLoginIsCheckedWhenRegistered() {
    #expect(entries([builtin], opensAtLogin: true).contains(.item("Open at Login", action: .toggleOpenAtLogin, checked: true)))
    #expect(entries([builtin]).contains(.item("Open at Login", action: .toggleOpenAtLogin, checked: false)))
}

@Test func profilesAreListedByNameAfterTheDisplaysWithTheActiveOneChecked() throws {
    let off = RememberedOff(id: 1, name: builtin.name, key: builtin.key)
    let all = entries([dell], off: [off], profiles: ["Zed", "desk", "Alpha"], active: "desk")
    let start = try #require(all.firstIndex(of: .header("Profiles")))
    #expect(Array(all[start...].prefix(4)) == [
        .header("Profiles"),
        .item("Alpha", action: .applyProfile("Alpha")),
        .item("desk", action: .applyProfile("desk"), checked: true),
        .item("Zed", action: .applyProfile("Zed")),
    ])
    let lastDisplay = try #require(all.lastIndex { if case .display = $0 { true } else { false } })
    #expect(lastDisplay < start)
    #expect(start < all.firstIndex(of: .item("Open at Login", action: .toggleOpenAtLogin))!)
}

@Test func deleteSubmenuIsShownOnlyWhenProfilesExist() {
    let save = MenuEntry.item("Save Current Setup as Profile…", action: .saveProfile)
    let none = entries([builtin, dell])
    #expect(none.contains(save))
    #expect(!none.contains { if case .submenu = $0 { true } else { false } })
    let some = entries([builtin, dell], profiles: ["Desk"])
    #expect(some.contains(save))
    #expect(some.contains(.submenu("Delete Profile", [.item("Desk", action: .deleteProfile("Desk"))])))
}
