import CoreGraphics

public struct DisplaySize: Hashable, Codable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width) × \(height)" }
}

/// Identifies a display across ports and reconnects, which change its CGDirectDisplayID.
public struct DisplayKey: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32

    public init(vendor: UInt32, model: UInt32, serial: UInt32) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }

    init(_ id: CGDirectDisplayID) {
        self.init(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
    }

    public static func < (a: DisplayKey, b: DisplayKey) -> Bool {
        (a.vendor, a.model, a.serial) < (b.vendor, b.model, b.serial)
    }

    public var description: String { String(format: "%04x:%04x:%08x", vendor, model, serial) }
}

public struct PhysicalDisplay: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let key: DisplayKey
    public let name: String
    public let isBuiltin: Bool
    /// The "looks like" size of the display's current mode, the size "Native" restores.
    public let nativeLogical: DisplaySize
    /// The panel's own pixel size, from its native mode, whatever mode it runs now.
    public let nativePixels: DisplaySize
    public let refreshRate: Double

    /// Virtual HiDPI sizes offered in the Resolution menu, at the panel's aspect
    /// ratio: eight steps from half the panel width (plain 2x) up to the full
    /// panel width (a 2x framebuffer scaled down to the panel). The current
    /// native size is left out; the Native item covers it.
    public var scaledSizes: [DisplaySize] {
        let half = nativePixels.width / 2
        let aspect = Double(nativePixels.height) / Double(nativePixels.width)
        let step = max(64, half / 8 / 64 * 64)
        return (0...8)
            .map { half + $0 * step }
            .filter { $0 <= nativePixels.width }
            .map { DisplaySize(width: $0, height: Int((Double($0) * aspect).rounded())) }
            .filter { $0 != nativeLogical }
    }
}

public struct RememberedOff: Codable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let key: DisplayKey

    public init(id: CGDirectDisplayID, name: String, key: DisplayKey) {
        self.id = id
        self.name = name
        self.key = key
    }

    /// Entries saved before profiles existed have no key. A disabled display
    /// still reports its vendor, model and serial (measured on macOS 26), so
    /// the key comes from the remembered ID.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CGDirectDisplayID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        key = try container.decodeIfPresent(DisplayKey.self, forKey: .key) ?? DisplayKey(id)
    }
}
