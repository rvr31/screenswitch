import CoreGraphics

public enum MenuAction: Equatable, Sendable {
    case setNative(CGDirectDisplayID)
    case setVirtual(CGDirectDisplayID, DisplaySize)
    case turnOff(CGDirectDisplayID)
    case turnOn(CGDirectDisplayID)
    case toggleOpenAtLogin
    case quit
}

/// One stop on a display's resolution slider.
public struct ResolutionStep: Equatable, Sendable {
    public let size: DisplaySize
    /// `.setNative` or `.setVirtual`.
    public let action: MenuAction

    public var title: String {
        if case .setNative = action { "\(size) (Native)" } else { size.description }
    }
}

/// The status menu as data. A nil action renders as a disabled control.
public enum MenuEntry: Equatable, Sendable {
    /// A display's name with an on/off switch.
    case display(name: String, isOn: Bool, toggle: MenuAction?)
    /// Steps ordered from the largest text to the most space.
    case resolution(display: String, steps: [ResolutionStep], selected: Int)
    case item(String, action: MenuAction?, checked: Bool = false)
    case separator
}

public enum MenuModel {
    public static func entries(
        displays: [PhysicalDisplay],
        virtualSizes: [CGDirectDisplayID: DisplaySize],
        turnedOff: [RememberedOff],
        opensAtLogin: Bool
    ) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        for display in displays {
            let steps = ([ResolutionStep(size: display.nativeLogical, action: .setNative(display.id))]
                + display.scaledSizes.map { ResolutionStep(size: $0, action: .setVirtual(display.id, $0)) })
                .sorted { $0.size.width < $1.size.width }
            let current = virtualSizes[display.id] ?? display.nativeLogical
            entries += [
                .display(name: display.name, isOn: true, toggle: displays.count > 1 ? .turnOff(display.id) : nil),
                .resolution(display: display.name, steps: steps, selected: steps.firstIndex { $0.size == current } ?? 0),
                .separator,
            ]
        }
        for off in turnedOff {
            entries += [.display(name: off.name, isOn: false, toggle: .turnOn(off.id)), .separator]
        }
        entries += [
            .item("Open at Login", action: .toggleOpenAtLogin, checked: opensAtLogin),
            .item("Quit ScreenSwitch", action: .quit),
        ]
        return entries
    }

    @MainActor
    public static func entries(for manager: DisplayManager, opensAtLogin: Bool) -> [MenuEntry] {
        entries(
            displays: manager.online,
            virtualSizes: manager.virtualSizes,
            turnedOff: manager.turnedOff,
            opensAtLogin: opensAtLogin)
    }
}
