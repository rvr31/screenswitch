import AppKit
import ScreenSwitchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = DisplayManager()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "ScreenSwitch")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        // `kill`/`pkill` should restore scaled displays like Quit does.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        terminationSignal = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.unmirrorAllBeforeExit()
    }

    func menuWillOpen(_ menu: NSMenu) {
        manager.refresh()
        menu.items = MenuModel.entries(for: manager).map(menuItem)
    }

    private func menuItem(_ entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .header(let title):
            return .sectionHeader(title: title)
        case .separator:
            return .separator()
        case let .item(title, action, checked):
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: action == .quit ? "q" : "")
            item.target = self
            item.representedObject = action
            item.isEnabled = action != nil
            item.state = checked ? .on : .off
            return item
        case let .submenu(title, entries):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            submenu.items = entries.map(menuItem)
            item.submenu = submenu
            return item
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        do throws(DisplayError) {
            switch action {
            case .setNative(let id): try manager.setNative(id)
            case .setVirtual(let id, let size): try manager.setVirtual(id, size: size)
            case .turnOff(let id): try manager.turnOff(id)
            case .turnOn(let id): try manager.turnOn(id)
            case .quit: NSApp.terminate(nil)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "\(sender.title) failed"
            alert.informativeText = error.description
            NSApp.activate()
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
