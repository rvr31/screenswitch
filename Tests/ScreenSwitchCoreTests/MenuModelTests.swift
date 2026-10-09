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

private func actions(_ entries: [MenuEntry]) -> [MenuAction?] {
    entries.flatMap { entry -> [MenuAction?] in
        switch entry {
        case .item(_, let action, _): [action]
        case .submenu(_, let children): actions(children)
        case .header, .separator: []
        }
    }
}

private func checked(_ entries: [MenuEntry]) -> [String] {
    entries.flatMap { entry -> [String] in
        switch entry {
        case .item(let title, _, let isChecked): isChecked ? [title] : []
        case .submenu(_, let children): checked(children)
        case .header, .separator: []
        }
    }
}

@Test func turnOffIsDisabledForTheOnlyDisplay() {
    let entries = MenuModel.entries(displays: [builtin], virtualSizes: [:], turnedOff: [])
    #expect(!actions(entries).contains(.turnOff(1)))
    #expect(entries.contains(.item("Turn off display", action: nil)))
}

@Test func eachDisplayCanBeTurnedOffWhenTwoAreActive() {
    let entries = MenuModel.entries(displays: [builtin, dell], virtualSizes: [:], turnedOff: [])
    #expect(actions(entries).contains(.turnOff(1)))
    #expect(actions(entries).contains(.turnOff(4)))
}

@Test func activeVirtualSizeIsCheckedInsteadOfNative() {
    let size = DisplaySize(width: 2304, height: 1440)
    let entries = MenuModel.entries(displays: [builtin, dell], virtualSizes: [4: size], turnedOff: [])
    #expect(checked(entries) == ["Native 1800 × 1169", "2304 × 1440"])
    #expect(actions(entries).contains(.setNative(4)))
}

@Test func rememberedDisplaysOfferTurnOn() {
    let off = RememberedOff(id: 4, name: "DELL U5226KW")
    let entries = MenuModel.entries(displays: [builtin], virtualSizes: [:], turnedOff: [off])
    #expect(entries.contains(.item("Turn on DELL U5226KW", action: .turnOn(4))))
    #expect(!MenuModel.entries(displays: [builtin], virtualSizes: [:], turnedOff: []).contains {
        if case .item(let title, _, _) = $0 { title.hasPrefix("Turn on") } else { false }
    })
}
