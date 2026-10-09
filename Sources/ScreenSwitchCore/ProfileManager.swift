import CoreGraphics
import Foundation

/// Saved profiles and switching between them. Main thread only.
@MainActor
public final class ProfileManager {
    public let displays: DisplayManager
    private var list: ProfileList {
        didSet { displays.defaults.set(try? JSONEncoder().encode(list.profiles), forKey: Self.profilesKey) }
    }
    /// Receives failures of `reconcile()`, which has no caller to throw to.
    public var onError: (@MainActor (_ title: String, _ error: DisplayError) -> Void)?
    /// Nil until the first `reconcile()`, so launch counts as a change: virtual
    /// sizes end with the process, and a profile has to apply them again.
    private var lastConnected: Set<DisplayKey>?
    private var applying = false
    private var reconcileMissed = false
    private static let profilesKey = "profiles"

    public init(_ displays: DisplayManager) {
        self.displays = displays
        let saved = displays.defaults.data(forKey: Self.profilesKey)
            .flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
        list = ProfileList(saved ?? [])
    }

    /// Most recently applied first.
    public var profiles: [Profile] { list.profiles }

    public var active: Profile? { list.active(current: displays.current) }

    public func saveCurrent(name: String) {
        list.save(Profile(name: name, targets: displays.current))
    }

    public func delete(name: String) {
        list.delete(name: name)
    }

    public func apply(name: String) throws(DisplayError) {
        guard let profile = list[name] else { throw .unknownProfile(name) }
        try apply(profile)
    }

    /// Turns displays back on when none is online, then applies the profile for
    /// the connected displays when that set changed since the last call.
    public func reconcile() {
        // Applying a profile spins the run loop while it waits for a virtual
        // display's modes, which can run this from a reconfiguration callback.
        guard !applying else {
            reconcileMissed = true
            return
        }
        do throws(DisplayError) {
            try displays.turnOnRememberedIfNoneOnline()
        } catch {
            onError?("Turning displays back on", error)
        }
        let connected = displays.connected
        guard connected != lastConnected else { return }
        lastConnected = connected
        guard let profile = list.matching(connected: connected) else { return }
        do throws(DisplayError) {
            try apply(profile)
        } catch {
            onError?("Applying profile \(profile.name)", error)
        }
    }

    private func apply(_ profile: Profile) throws(DisplayError) {
        applying = true
        defer {
            applying = false
            if reconcileMissed {
                reconcileMissed = false
                reconcile()
            }
        }
        for step in profile.steps(from: displays.current) {
            try perform(step)
        }
        list.markApplied(profile.name)
    }

    private func perform(_ step: ProfileStep) throws(DisplayError) {
        switch step {
        case .turnOn(let key): try displays.turnOn(id(key))
        case .setNative(let key): try displays.setNative(id(key))
        case .setVirtual(let key, let size): try displays.setVirtual(id(key), size: size)
        case .turnOff(let key): try displays.turnOff(id(key))
        }
    }

    private func id(_ key: DisplayKey) throws(DisplayError) -> CGDirectDisplayID {
        guard let id = displays.id(for: key) else { throw .displayNotConnected(key) }
        return id
    }
}
