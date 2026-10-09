import AppKit
import CoreGraphics
import ScreenSwitchCore

// Drives DisplayManager without the menu bar, for verification. Commands run in
// order in one process, then the process exits through the same restoreAll()
// the app runs on quit:
//   screenswitch-cli status off 4 wait 3 status on 4 status
//   screenswitch-cli scale 4 2304x1440 wait 5 status native 4 status

let usage = """
    usage: screenswitch-cli <command>...
      status            displays, scaling state and the CoreGraphics display lists
      menu              the status menu as the app would show it
      off ID | on ID    turn a display off or on
      scale ID WxH      mirror display ID onto a virtual HiDPI display of WxH
      native ID         back to the display's own mode
      wait SECONDS      keep the process (and its virtual displays) alive
      crash             exit immediately, skipping restoreAll()
    """

func displayList(_ get: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError) -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    _ = get(16, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

@MainActor func printStatus(_ manager: DisplayManager) {
    manager.refresh()
    print("  active=\(displayList(CGGetActiveDisplayList)) online=\(displayList(CGGetOnlineDisplayList))")
    for id in displayList(CGGetActiveDisplayList) {
        guard let mode = CGDisplayCopyDisplayMode(id) else { continue }
        print("    id=\(id) mode=\(mode.width)x\(mode.height) px=\(mode.pixelWidth)x\(mode.pixelHeight) mirrorOf=\(CGDisplayMirrorsDisplay(id)) main=\(CGDisplayIsMain(id) != 0)")
    }
    for display in manager.online {
        let scaling = manager.virtualSizes[display.id].map { "virtual \($0)" } ?? "native"
        print("  \(display.id) \(display.name): native \(display.nativeLogical) (px \(display.nativePixels)), \(scaling)")
    }
    print("  turnedOff=\(manager.turnedOff.map { "\($0.id) \($0.name)" })")
}

func outline(_ entries: [MenuEntry], depth: Int = 1) -> [String] {
    entries.flatMap { entry -> [String] in
        let pad = String(repeating: "  ", count: depth)
        switch entry {
        case .separator:
            return [pad + "----"]
        case let .header(title):
            return [pad + "[" + title + "]"]
        case let .item(title, action, checked):
            return [pad + (checked ? "* " : "  ") + title + (action == nil ? "  (disabled)" : "")]
        case let .submenu(title, children):
            return [pad + "  " + title + " >"] + outline(children, depth: depth + 2)
        }
    }
}

let arity = ["off": 1, "on": 1, "scale": 2, "native": 1, "wait": 1]

/// Returns false when the command or its operands are not understood.
@MainActor func execute(_ command: String, _ operands: [String], on manager: DisplayManager) throws(DisplayError) -> Bool {
    let id = operands.first.flatMap { CGDirectDisplayID($0) }
    switch (command, id) {
    case ("status", _): printStatus(manager)
    case ("menu", _): print(outline(MenuModel.entries(for: manager)).joined(separator: "\n"))
    case ("off", let id?): try manager.turnOff(id)
    case ("on", let id?): try manager.turnOn(id)
    case ("native", let id?): try manager.setNative(id)
    case ("scale", let id?):
        let parts = operands[1].split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return false }
        try manager.setVirtual(id, size: DisplaySize(width: parts[0], height: parts[1]))
    case ("wait", _):
        guard let seconds = operands.first.flatMap(Double.init) else { return false }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    case ("crash", _): exit(0)
    default: return false
    }
    return true
}

@MainActor func run(_ arguments: [String]) -> Int32 {
    let manager = DisplayManager()
    defer { manager.restoreAll() }
    var args = arguments[...]
    if args.isEmpty { print(usage); return 2 }
    while let command = args.popFirst() {
        let operands = Array(args.prefix(arity[command, default: 0]))
        args = args.dropFirst(operands.count)
        print(([">", command] + operands).joined(separator: " "))
        do {
            let understood = try autoreleasepool { () throws(DisplayError) in
                try execute(command, operands, on: manager)
            }
            guard understood, operands.count == arity[command, default: 0] else { print(usage); return 2 }
        } catch {
            print("  error: \(error)")
            return 1
        }
    }
    return 0
}

exit(MainActor.assumeIsolated { run(Array(CommandLine.arguments.dropFirst())) })
