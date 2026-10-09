import AppKit
import CoreGraphics
import PrivateDisplay

public enum ScalingState {
    case native
    case virtual(VirtualScreen)
}

/// A virtual HiDPI display the physical display mirrors. The display exists
/// only as long as this object (and the process) lives.
public final class VirtualScreen {
    public let size: DisplaySize
    let display: CGVirtualDisplay

    init(size: DisplaySize, display: CGVirtualDisplay) {
        self.size = size
        self.display = display
    }
}

/// Single owner of all display state ScreenSwitch changes.
@MainActor
public final class DisplayManager {
    public private(set) var online: [PhysicalDisplay] = []
    public private(set) var scaling: [CGDirectDisplayID: ScalingState] = [:]
    public private(set) var turnedOff: [RememberedOff] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(turnedOff), forKey: Self.turnedOffKey) }
    }

    /// NSScreen names lag behind CoreGraphics in a process that is not running
    /// an app event loop, and a disabled or mirrored display has no NSScreen.
    private var knownNames: [CGDirectDisplayID: String] = [:]
    private let defaults: UserDefaults
    private static let defaultsDomain = "nl.vanraan.screenswitch"
    private static let turnedOffKey = "turnedOff"
    /// Marks the virtual displays this app creates. After a mirrored virtual display
    /// is released, this process's online display list keeps reporting it (measured
    /// on macOS 26), so its id cannot be trusted to identify a physical display.
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
        // Monitors coming and going change what the menu offers, and a scaled
        // display that is unplugged must release its virtual screen.
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in manager.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    public func scaling(of id: CGDirectDisplayID) -> ScalingState {
        scaling[id] ?? .native
    }

    public func display(_ id: CGDirectDisplayID) -> PhysicalDisplay? {
        online.first { $0.id == id }
    }

    public var canTurnOffAnyDisplay: Bool { online.count > 1 }

    /// Re-reads the online displays and reconciles remembered state with them.
    public func refresh() {
        knownNames.merge(Self.screenNames()) { _, new in new }
        let previous = Dictionary(online.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        online = Self.onlineDisplayIDs()
            .filter { CGDisplayVendorNumber($0) != Self.virtualVendorID }
            .compactMap { id in
                // A mirrored display's mode may report the virtual screen, so keep
                // what it looked like before it was scaled.
                if case .virtual = scaling(of: id), let known = previous[id] { return known }
                return Self.physicalDisplay(id, name: knownNames[id])
            }
            .sorted { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }

        let onlineIDs = Set(online.map(\.id))
        for id in scaling.keys where !onlineIDs.contains(id) {
            scaling[id] = nil
        }
        // A remembered display that is online again was turned on elsewhere
        // (System Settings, reboot); it no longer needs a "Turn on" entry.
        turnedOff.removeAll { onlineIDs.contains($0.id) }
    }

    public func turnOff(_ id: CGDirectDisplayID) throws(DisplayError) {
        guard let display = display(id) else { throw .unknownDisplay(id) }
        guard canTurnOffAnyDisplay else { throw .onlyActiveDisplay }
        try setNative(id)
        try SkyLight.setEnabled(id, false)
        // A disabled display vanishes from both the active and the online display
        // lists, so this record is the only way to find it again to turn it on.
        turnedOff.removeAll { $0.id == id }
        turnedOff.append(RememberedOff(id: id, name: display.name))
        refresh()
    }

    public func turnOn(_ id: CGDirectDisplayID) throws(DisplayError) {
        try SkyLight.setEnabled(id, true)
        turnedOff.removeAll { $0.id == id }
        refresh()
    }

    public func setNative(_ id: CGDirectDisplayID) throws(DisplayError) {
        guard case .virtual = scaling(of: id) else { return }
        try DisplayConfiguration.apply { CGConfigureDisplayMirrorOfDisplay($0, id, kCGNullDirectDisplay) }
        scaling[id] = nil
        refresh()
    }

    /// Mirrors the display onto a new virtual HiDPI display of `size`, so the GPU
    /// renders a 2x framebuffer at that size and scales it onto the panel, which
    /// keeps its own native signal.
    public func setVirtual(_ id: CGDirectDisplayID, size: DisplaySize) throws(DisplayError) {
        guard let display = display(id) else { throw .unknownDisplay(id) }
        try setNative(id)
        let screen = try Self.makeVirtualScreen(for: display, size: size)
        try DisplayConfiguration.apply {
            CGConfigureDisplayMirrorOfDisplay($0, id, screen.display.displayID)
        }
        scaling[id] = .virtual(screen)
        refresh()
    }

    private static func makeVirtualScreen(for display: PhysicalDisplay, size: DisplaySize) throws(DisplayError) -> VirtualScreen {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "\(display.name) (scaled)"
        descriptor.queue = .main
        descriptor.vendorID = Self.virtualVendorID
        descriptor.productID = 0x5357
        // Per physical display, so macOS keeps arrangement settings for each apart.
        descriptor.serialNum = display.id
        descriptor.maxPixelsWide = UInt32(size.width * 2)
        descriptor.maxPixelsHigh = UInt32(size.height * 2)
        let millimeters = CGDisplayScreenSize(display.id)
        descriptor.sizeInMillimeters = millimeters.width > 0 ? millimeters : CGSize(width: 600, height: 340)
        descriptor.redPrimary = CGPoint(x: 0.68, y: 0.32)
        descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.69)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.329)

        guard let virtual = CGVirtualDisplay(descriptor: descriptor) else { throw .virtualDisplayFailed }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [
            CGVirtualDisplayMode(
                width: UInt32(size.width), height: UInt32(size.height),
                refreshRate: display.refreshRate > 0 ? display.refreshRate : 60),
        ]
        guard virtual.apply(settings), virtual.displayID != kCGNullDirectDisplay else { throw .virtualDisplayFailed }
        return VirtualScreen(size: size, display: virtual)
    }

    /// Restores every scaled display to its own mode. Run before the process exits,
    /// so panels do not depend on WindowServer cleaning up after a dead process.
    public func restoreAll() {
        for id in scaling.keys {
            try? setNative(id)
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
