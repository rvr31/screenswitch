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

public struct PhysicalDisplay: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
    /// The "looks like" size of the display's own mode, the size "Native" restores.
    public let nativeLogical: DisplaySize
    public let nativePixels: DisplaySize
    public let refreshRate: Double

    /// Virtual logical sizes offered in the Resolution menu: steps of 128 px
    /// around the native width, within 75% to 125% of it, at the native aspect ratio.
    public var scaledSizes: [DisplaySize] {
        let width = nativeLogical.width
        let aspect = Double(nativeLogical.height) / Double(width)
        let steps = Int(Double(width) * 0.25 / 128)
        return (-steps...steps)
            .filter { $0 != 0 }
            .map { width + $0 * 128 }
            .map { DisplaySize(width: $0, height: Int((Double($0) * aspect).rounded())) }
    }
}

public struct RememberedOff: Codable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
}
