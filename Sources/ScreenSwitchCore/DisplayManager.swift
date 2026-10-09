import AppKit
import CoreGraphics
import PrivateDisplay

/// Single owner of all display state ScreenSwitch changes. Main thread only.
@MainActor
public final class DisplayManager {
    public private(set) var online: [PhysicalDisplay] = []
    public private(set) var turnedOff: [RememberedOff] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(turnedOff), forKey: Self.turnedOffKey) }
    }

    /// Each physical display gets one virtual display, created on first use and
    /// kept until the process exits. Releasing a virtual display that was
    /// mirrored leaves this process's display list reporting it, after which
    /// every display configuration fails with kCGErrorFailure (measured on macOS 26).
    private enum Virtual {
        /// Disabled, so it is not an empty extra desktop; the panel shows its own mode.
        case parked(CGVirtualDisplay)
        case mirrored(CGVirtualDisplay, DisplaySize)
    }
    private var virtuals: [CGDirectDisplayID: Virtual] = [:]

    /// The virtual logical size each scaled display mirrors. Absent means native.
    public var virtualSizes: [CGDirectDisplayID: DisplaySize] {
        virtuals.compactMapValues { if case .mirrored(_, let size) = $0 { size } else { nil } }
    }

    /// The state of every connected display: online ones and the ones turned off here.
    public var current: [DisplayKey: DisplayTarget] {
        let online = online.map { display in
            (display.key, virtualSizes[display.id].map(DisplayTarget.virtual) ?? .native)
        }
        let off = turnedOff.map { ($0.key, DisplayTarget.off) }
        return Dictionary(online + off, uniquingKeysWith: { first, _ in first })
    }

    public var connected: Set<DisplayKey> { Set(current.keys) }

    public func id(for key: DisplayKey) -> CGDirectDisplayID? {
        online.first { $0.key == key }?.id ?? turnedOff.first { $0.key == key }?.id
    }

    /// Runs after the refresh that follows each display reconfiguration.
    public var onReconfigure: (@MainActor () -> Void)?

    /// NSScreen names lag behind CoreGraphics in a process that is not running
    /// an app event loop, and a disabled or mirrored display has no NSScreen.
    private var knownNames: [CGDirectDisplayID: String] = [:]
    public let defaults: UserDefaults
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
            Task { @MainActor in
                manager.refresh()
                manager.onReconfigure?()
            }
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
                if case .mirrored = virtuals[id], let known = previous[id] { return known }
                return Self.physicalDisplay(id, name: knownNames[id])
            }
            .sorted { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }

        let onlineIDs = Set(online.map(\.id))
        // An unplugged display leaves its virtual screen behind as an empty desktop.
        for (id, state) in virtuals where !onlineIDs.contains(id) {
            if case .mirrored(let virtual, _) = state {
                Self.park(virtual)
                virtuals[id] = .parked(virtual)
            }
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
        turnedOff.append(RememberedOff(id: id, name: display.name, key: display.key))
        refresh()
    }

    public func turnOn(_ id: CGDirectDisplayID) throws(DisplayError) {
        try DisplayConfiguration.apply { SkyLight.configureEnabled($0, id, true) }
        turnedOff.removeAll { $0.id == id }
        refresh()
    }

    /// With no display online, nothing shows the menu's "Turn on" items, as when
    /// the only active display is unplugged while the others are turned off.
    /// Turns every remembered display on, built-in first. Does nothing when
    /// macOS already brought one back.
    public func turnOnRememberedIfNoneOnline() throws(DisplayError) {
        guard online.isEmpty, !turnedOff.isEmpty else { return }
        var failure: DisplayError?
        for remembered in turnedOff.sorted(by: { CGDisplayIsBuiltin($0.id) > CGDisplayIsBuiltin($1.id) }) {
            do { try turnOn(remembered.id) } catch { failure = error }
        }
        if online.isEmpty, let failure { throw failure }
    }

    /// Mirrors the display onto a virtual HiDPI display at `size`, so the GPU
    /// renders a 2x framebuffer at that size and scales it onto the panel, which
    /// keeps its own native signal.
    public func setVirtual(_ id: CGDirectDisplayID, size: DisplaySize) throws(DisplayError) {
        guard let display = display(id) else { throw .unknownDisplay(id) }
        guard display.scaledSizes.contains(size) else { throw .sizeNotOffered(size) }
        // Changing the settings of a live mirrored virtual display leaves its
        // mode as it was (measured on macOS 26), so every size change goes
        // through the parked state.
        if case .mirrored = virtuals[id] { try setNative(id) }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [CGVirtualDisplayMode(
            width: UInt32(size.width), height: UInt32(size.height),
            refreshRate: display.refreshRate > 0 ? display.refreshRate : 60)]

        let virtual: CGVirtualDisplay
        switch virtuals[id] {
        case .mirrored: fatalError("unreachable: setNative parks a mirrored display")
        case .parked(let parked): virtual = parked
        case nil:
            guard let created = CGVirtualDisplay(descriptor: Self.descriptor(for: display)) else {
                throw .virtualDisplayFailed
            }
            virtual = created
        }
        do throws(DisplayError) {
            guard virtual.apply(settings), virtual.displayID != kCGNullDirectDisplay else { throw .virtualDisplayFailed }
            if case .parked = virtuals[id] {
                try DisplayConfiguration.apply { SkyLight.configureEnabled($0, virtual.displayID, true) }
            }
            try DisplayConfiguration.apply { CGConfigureDisplayMirrorOfDisplay($0, id, virtual.displayID) }
            // A fresh virtual display lists no modes until its first configuration
            // has completed, and WindowServer then starts it in the 1x mode that
            // matches the panel (measured), so the 2x mode is set afterwards.
            try Self.ensureHiDPIMode(of: virtual.displayID, size: size)
        } catch {
            try? DisplayConfiguration.apply { CGConfigureDisplayMirrorOfDisplay($0, id, kCGNullDirectDisplay) }
            Self.park(virtual)
            virtuals[id] = .parked(virtual)
            throw error
        }
        virtuals[id] = .mirrored(virtual, size)
        refresh()
    }

    /// Switches the virtual display to the 2x mode for `size` unless it is in it
    /// already. The mode list fills in asynchronously on the descriptor's queue,
    /// the main queue, so the poll spins the main run loop instead of sleeping.
    private static func ensureHiDPIMode(of id: CGDirectDisplayID, size: DisplaySize) throws(DisplayError) {
        func is2x(_ mode: CGDisplayMode) -> Bool {
            mode.width == size.width && mode.height == size.height && mode.pixelWidth == size.width * 2
        }
        var modes: [CGDisplayMode] = []
        for _ in 0..<30 {
            if let current = CGDisplayCopyDisplayMode(id), is2x(current) { return }
            modes = allModes(of: id)
            if let mode = modes.first(where: is2x) {
                try DisplayConfiguration.apply { CGConfigureDisplayWithDisplayMode($0, id, mode, nil) }
                return
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        throw .hiDPIModeMissing(size, offered: modes.map { "\($0.width)x\($0.height)@\($0.pixelWidth)x\($0.pixelHeight)" })
    }

    private static func allModes(of id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let array = CGDisplayCopyAllDisplayModes(id, options) else { return [] }
        return (0..<CFArrayGetCount(array)).map {
            unsafeBitCast(CFArrayGetValueAtIndex(array, $0), to: CGDisplayMode.self)
        }
    }

    public func setNative(_ id: CGDirectDisplayID) throws(DisplayError) {
        guard case .mirrored(let virtual, _) = virtuals[id] else { return }
        try DisplayConfiguration.apply { config in
            let result = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
            return result == .success ? SkyLight.configureEnabled(config, virtual.displayID, false) : result
        }
        virtuals[id] = .parked(virtual)
        refresh()
    }

    /// Unmirrors every scaled display in one configuration and changes nothing
    /// else. Run right before the process exits, which removes the virtual
    /// displays; unmirroring first keeps panels from depending on WindowServer
    /// cleaning up after the process.
    public func unmirrorAllBeforeExit() {
        let scaled = Array(virtualSizes.keys)
        guard !scaled.isEmpty else { return }
        try? DisplayConfiguration.apply { config in
            for id in scaled {
                let result = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
                guard result == .success else { return result }
            }
            return .success
        }
    }

    private static func descriptor(for display: PhysicalDisplay) -> CGVirtualDisplayDescriptor {
        // Large enough for every offered size, since the display is reused for each.
        let largest = display.scaledSizes.last ?? display.nativeLogical
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "\(display.name) (scaled)"
        descriptor.queue = .main
        descriptor.vendorID = virtualVendorID
        descriptor.productID = 0x5357
        // Per physical display, so macOS keeps arrangement settings for each apart.
        descriptor.serialNum = display.id
        descriptor.maxPixelsWide = UInt32(largest.width * 2)
        descriptor.maxPixelsHigh = UInt32(largest.height * 2)
        let millimeters = CGDisplayScreenSize(display.id)
        descriptor.sizeInMillimeters = millimeters.width > 0 ? millimeters : CGSize(width: 600, height: 340)
        descriptor.redPrimary = CGPoint(x: 0.68, y: 0.32)
        descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.69)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.329)
        return descriptor
    }

    /// Disables an unused virtual display so it is not an empty extra desktop.
    private static func park(_ virtual: CGVirtualDisplay) {
        try? DisplayConfiguration.apply { SkyLight.configureEnabled($0, virtual.displayID, false) }
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
        // The panel's pixel size comes from its native-flagged mode, so a display
        // running a scaled or 1x mode still offers sizes at the panel's aspect ratio.
        let nativeFlag: UInt32 = 0x0200_0000
        let modes = allModes(of: id)
        let panel = (modes.filter { $0.ioFlags & nativeFlag != 0 }.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight })
            ?? modes.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
            ?? mode
        return PhysicalDisplay(
            id: id,
            key: DisplayKey(id),
            name: name ?? (isBuiltin ? "Built-in Display" : "Display \(id)"),
            isBuiltin: isBuiltin,
            nativeLogical: DisplaySize(width: mode.width, height: mode.height),
            nativePixels: DisplaySize(width: panel.pixelWidth, height: panel.pixelHeight),
            refreshRate: mode.refreshRate)
    }
}
