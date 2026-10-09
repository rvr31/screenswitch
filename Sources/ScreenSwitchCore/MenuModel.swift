import CoreGraphics

public enum MenuAction: Equatable, Sendable {
    case setNative(CGDirectDisplayID)
    case setVirtual(CGDirectDisplayID, DisplaySize)
    case turnOff(CGDirectDisplayID)
    case turnOn(CGDirectDisplayID)
    case quit
}

/// The status menu as data. A nil action renders as a disabled item.
public indirect enum MenuEntry: Equatable, Sendable {
    case item(String, action: MenuAction?, checked: Bool = false, indented: Bool = false)
    case submenu(String, [MenuEntry], indented: Bool = false)
    case separator
}

public enum MenuModel {
    public static func entries(
        displays: [PhysicalDisplay],
        virtualSizes: [CGDirectDisplayID: DisplaySize],
        turnedOff: [RememberedOff]
    ) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        for display in displays {
            let virtual = virtualSizes[display.id]
            let resolutions: [MenuEntry] =
                [.item("Native \(display.nativeLogical)", action: .setNative(display.id), checked: virtual == nil),
                 .separator,
                 .item("Virtual HiDPI", action: nil)]
                + display.scaledSizes.map {
                    .item($0.description, action: .setVirtual(display.id, $0), checked: virtual == $0)
                }
            entries += [
                .item(display.name, action: nil),
                .submenu("Resolution", resolutions, indented: true),
                .item("Turn off display", action: displays.count > 1 ? .turnOff(display.id) : nil, indented: true),
            ]
        }
        if !turnedOff.isEmpty {
            entries.append(.separator)
            entries += turnedOff.map { .item("Turn on \($0.name)", action: .turnOn($0.id)) }
        }
        entries += [.separator, .item("Quit ScreenSwitch", action: .quit)]
        return entries
    }

    @MainActor
    public static func entries(for manager: DisplayManager) -> [MenuEntry] {
        entries(
            displays: manager.online,
            virtualSizes: manager.scaling.compactMapValues {
                if case .virtual(let screen) = $0 { return screen.size }
                return nil
            },
            turnedOff: manager.turnedOff)
    }
}
