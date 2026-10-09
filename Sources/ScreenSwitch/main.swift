import AppKit
import ScreenSwitchCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = DisplayManager()
    private let updater = Updater()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var terminationSignal: DispatchSourceSignal?
    private var pending: (MenuAction, String)?

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

        updater?.startChecking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.unmirrorAllBeforeExit()
    }

    func menuWillOpen(_ menu: NSMenu) {
        manager.refresh()
        let opensAtLogin = SMAppService.mainApp.status == .enabled
        menu.items = MenuModel.entries(for: manager, opensAtLogin: opensAtLogin, update: updater?.state).map(menuItem)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard let (action, title) = pending else { return }
        pending = nil
        // Out of the menu's tracking loop, like an ordinary item's action.
        DispatchQueue.main.async { self.perform(action, title: title) }
    }

    private func menuItem(_ entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case let .item(title, action, checked):
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: action == .quit ? "q" : "")
            item.target = self
            item.representedObject = action
            item.isEnabled = action != nil
            item.state = checked ? .on : .off
            return item
        case let .display(name, isOn, toggle):
            let item = NSMenuItem()
            item.view = DisplayRowView(name: name, isOn: isOn, isEnabled: toggle != nil) { [weak self] in
                guard let toggle else { return }
                self?.performAfterClose(toggle, title: isOn ? "Turn off \(name)" : "Turn on \(name)")
            }
            return item
        case let .resolution(name, steps, selected):
            let item = NSMenuItem()
            item.view = ResolutionSliderView(steps: steps, selected: selected) { [weak self] step in
                self?.performAfterClose(step.action, title: "\(name) at \(step.size)")
            }
            return item
        }
    }

    /// A control inside a view item keeps the menu open. Display changes move
    /// and resize the menu bar, so the menu closes first.
    private func performAfterClose(_ action: MenuAction, title: String) {
        pending = (action, title)
        statusItem.menu?.cancelTracking()
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        perform(action, title: sender.title)
    }

    private func perform(_ action: MenuAction, title: String) {
        do throws(DisplayError) {
            switch action {
            case .setNative(let id): try manager.setNative(id)
            case .setVirtual(let id, let size): try manager.setVirtual(id, size: size)
            case .turnOff(let id): try manager.turnOff(id)
            case .turnOn(let id): try manager.turnOn(id)
            case .checkForUpdates: Task { await checkForUpdates() }
            case .installUpdate:
                if case .available(let update) = updater?.state { Task { await install(update) } }
            case .toggleOpenAtLogin: toggleOpenAtLogin(title)
            case .quit: NSApp.terminate(nil)
            }
        } catch {
            showFailure(title, error.description)
        }
    }

    private func checkForUpdates() async {
        guard let updater else { return }
        do {
            guard let update = try await updater.check() else {
                showAlert("ScreenSwitch \(updater.current) is up to date")
                return
            }
            let choice = showAlert(
                "ScreenSwitch \(update.version) is available", "You have version \(updater.current).",
                buttons: ["Install", "Later"])
            if choice == .alertFirstButtonReturn { await install(update) }
        } catch {
            showFailure("Checking for updates", error.localizedDescription)
        }
    }

    private func install(_ update: AvailableUpdate) async {
        do {
            try await updater?.install(update)
        } catch {
            showFailure("Updating to ScreenSwitch \(update.version)", error.localizedDescription)
        }
    }

    private func toggleOpenAtLogin(_ title: String) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showFailure(title, error.localizedDescription)
        }
    }

    private func showFailure(_ title: String, _ message: String) {
        showAlert("\(title) failed", message)
    }

    @discardableResult
    private func showAlert(_ message: String, _ info: String = "", buttons: [String] = []) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate()
        return alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
