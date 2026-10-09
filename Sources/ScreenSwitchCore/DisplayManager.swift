import AppKit
import CoreGraphics
import PrivateDisplay

/// Single owner of all display state ScreenSwitch changes. Main thread only.
@MainActor
public final class DisplayManager {
    public private(set) var online: [PhysicalDisplay] = []
    /// The virtual logical size each scaled display mirrors. Absent means native.
    public private(set) var virtualSizes: [CGDirectDisplayID: DisplaySize] = [:]
    public private(set) var turnedOff: [RememberedOff] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(turnedOff), forKey: Self.turnedOffKey) }
    }

    /// One virtual display per physical display, created on first use and kept
    /// until the process exits; it is enabled exactly while its display has a
    /// virtual size. Releasing a virtual display that was mirrored leaves this
    /// process's display list reporting it, after which every display
    /// configuration fails with kCGErrorFailure (measured on macOS 26).
    private var virtualDisplays: [CGDirectDisplayID: CGVirtualDisplay] = [:]
    /// NSScreen names lag behind CoreGraphics in a process that is not running
    /// an app event loop, and a disabled or mirrored display has no NSScreen.
    private var knownNames: [CGDirectDisplayID: String] = [:]
    private let defaults: UserDefaults
    private static let defaultsDomain = "nl.vanraan.screenswitch"
    private static let turnedOffKey = "turnedOff"
    private static let virtualVendorID: UInt32 = 0x5353

    public init() {
        // The app and the CLI share one defaults domain. Inside the app bundle
        // that domain is `.standard`; UserDefaults rejects its own bundle id as a suite.
        defaults = Bundle.main.bundleIdentifier == Self.defaultsDomain
            ? .standard
            : UserDefaults(suiteName: Self.defaultsDomain)!
        if let data = defaults.data(forKey: Self.turnedOffKey),
           let saved = try? JSONDecoder().decode([RememberedOff].self, from: data) {
            turnedOff = saved
            for display in saved { knownNames[display.id] = display.name }
        }
        refresh()
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in manager.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    public func display(_ id: CGDirectDisplayID) -> PhysicalDisplay? {
        online.first { $0.id == id }
    }

    /// Re-reads the online displays and reconciles remembered state with them.
    public func refresh() {
        knownNames.merge(Self.screenNames()) { _, new in new }
        let previous = Dictionary(online.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        online = Self.onlineDisplayIDs()
            .filter { CGDisplayVendorNumber($0) != Self.virtualVendorID }
            .compactMap { id in
                // A mirrored display's mode may report the virtual screen, so keep
                // what it looked like before it was scaled.
                if virtualSizes[id] != nil, let known = previous[id] { return known }
                return Self.physicalDisplay(id, name: knownNames[id])
            }
            .sorted { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }

        let onlineIDs = Set(online.map(\.id))
        // An unplugged display leaves its virtual screen behind as an empty desktop.
        for id in virtualSizes.keys where !onlineIDs.contains(id) {
            if let virtual = virtualDisplays[id] { Self.park(virtual) }
            virtualSizes[id] = nil
        }
        // A remembered display that is online again was turned on elsewhere
        // (System Settings, reboot); it no longer needs a "Turn on" entry.
        turnedOff.removeAll { onlineIDs.contains($0.id) }
    }

    public func turnOff(_ id: CGDirectDisplayID) throws(DisplayError) {
        guard let display = display(id) else { throw .unknownDisplay(id) }
        guard online.count > 1 else { throw .onlyActiveDisplay }
        try setNative(id)
        try DisplayConfiguration.apply { SkyLight.configureEnabled($0, id, false) }
        // A disabled display vanishes from both the active and the online display
        // lists, so this record is the only way to find it again to turn it on.
        turnedOff.removeAll { $0.id == id }
        turnedOff.append(RememberedOff(id: id, name: display.name))
        refresh()
    }

    public func turnOn(_ id: CGDirectDisplayID) throws(DisplayError) {
        try DisplayConfiguration.apply { SkyLight.configureEnabled($0, id, true) }
        turnedOff.removeAll { $0.id == id }
        refresh()
    }

    /// Mirrors the display onto a virtual HiDPI display at `size`, so the GPU
    /// renders a 2x framebuffer at that size and scales it onto the panel, which
    /// keeps its own native signal.
    public func setVirtual(_ id: CGDirectDisplayID, size: DisplaySize) throws(DisplayError) {
        guard let display = display(id) else { throw .unknownDisplay(id) }
        let wasNative = virtualSizes[id] == nil
        if let parked = virtualDisplays[id] {
            try switchVirtual(parked, of: id, to: size, enable: wasNative)
        } else {
            // A new virtual display starts in its first mode, and its mode list is
            // not readable until WindowServer has set it up.
            let virtual = try Self.makeVirtualDisplay(for: display, startingAt: size)
            virtualDisplays[id] = virtual
            do throws(DisplayError) {
                try DisplayConfiguration.apply { CGConfigureDisplayMirrorOfDisplay($0, id, virtual.displayID) }
            } catch {
                Self.park(virtual)
                throw error
            }
        }
        virtualSizes[id] = size
        refresh()
    }

    private func switchVirtual(
        _ virtual: CGVirtualDisplay, of id: CGDirectDisplayID, to size: DisplaySize, enable: Bool
    ) throws(DisplayError) {
        do throws(DisplayError) {
            // A parked display is disabled, and enabling must complete before it
            // accepts a mode or a mirror.
            if enable {
                try DisplayConfiguration.apply { SkyLight.configureEnabled($0, virtual.displayID, true) }
            }
            guard let mode = Self.hiDPIMode(of: virtual.displayID, size: size) else { throw .modeUnavailable(size) }
            try DisplayConfiguration.apply { config in
                let result = CGConfigureDisplayWithDisplayMode(config, virtual.displayID, mode, nil)
                return result == .success ? CGConfigureDisplayMirrorOfDisplay(config, id, virtual.displayID) : result
            }
        } catch {
            if enable { Self.park(virtual) }
            throw error
        }
    }

    public func setNative(_ id: CGDirectDisplayID) throws(DisplayError) {
        guard virtualSizes[id] != nil, let virtual = virtualDisplays[id] else { return }
        try DisplayConfiguration.apply { config in
            let result = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
            return result == .success ? SkyLight.configureEnabled(config, virtual.displayID, false) : result
        }
        virtualSizes[id] = nil
        refresh()
    }

    /// Restores every scaled display to its own mode. Run before the process exits,
    /// so panels do not depend on WindowServer cleaning up after it.
    public func restoreAll() {
        for id in virtualSizes.keys {
            try? setNative(id)
        }
    }

    private static func makeVirtualDisplay(
        for display: PhysicalDisplay, startingAt size: DisplaySize
    ) throws(DisplayError) -> CGVirtualDisplay {
        let sizes = [size] + display.scaledSizes.filter { $0 != size }
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "\(display.name) (scaled)"
        descriptor.queue = .main
        descriptor.vendorID = virtualVendorID
        descriptor.productID = 0x5357
        // Per physical display, so macOS keeps arrangement settings for each apart.
        descriptor.serialNum = display.id
        descriptor.maxPixelsWide = UInt32(sizes.map(\.width).max()! * 2)
        descriptor.maxPixelsHigh = UInt32(sizes.map(\.height).max()! * 2)
        let millimeters = CGDisplayScreenSize(display.id)
        descriptor.sizeInMillimeters = millimeters.width > 0 ? millimeters : CGSize(width: 600, height: 340)
        descriptor.redPrimary = CGPoint(x: 0.68, y: 0.32)
        descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.69)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.329)

        guard let virtual = CGVirtualDisplay(descriptor: descriptor) else { throw .virtualDisplayFailed }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        let refreshRate = display.refreshRate > 0 ? display.refreshRate : 60
        settings.modes = sizes.map {
            CGVirtualDisplayMode(width: UInt32($0.width), height: UInt32($0.height), refreshRate: refreshRate)
        }
        guard virtual.apply(settings), virtual.displayID != kCGNullDirectDisplay else { throw .virtualDisplayFailed }
        return virtual
    }

    /// Disables an unused virtual display so it is not an empty extra desktop.
    private static func park(_ virtual: CGVirtualDisplay) {
        try? DisplayConfiguration.apply { SkyLight.configureEnabled($0, virtual.displayID, false) }
    }

    private static func hiDPIMode(of id: CGDirectDisplayID, size: DisplaySize) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        return modes.first {
            $0.width == size.width && $0.height == size.height && $0.pixelWidth == size.width * 2
        }
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return Dictionary(
            NSScreen.screens.compactMap { screen in
                (screen.deviceDescription[key] as? CGDirectDisplayID).map { ($0, screen.localizedName) }
            },
            uniquingKeysWith: { a, _ in a })
    }

    private static func physicalDisplay(_ id: CGDirectDisplayID, name: String?) -> PhysicalDisplay? {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        let isBuiltin = CGDisplayIsBuiltin(id) != 0
        return PhysicalDisplay(
            id: id,
            name: name ?? (isBuiltin ? "Built-in Display" : "Display \(id)"),
            isBuiltin: isBuiltin,
            nativeLogical: DisplaySize(width: mode.width, height: mode.height),
            nativePixels: DisplaySize(width: mode.pixelWidth, height: mode.pixelHeight),
            refreshRate: mode.refreshRate)
    }
}
