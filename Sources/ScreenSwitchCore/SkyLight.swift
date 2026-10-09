import CoreGraphics
import Foundation

/// `CGSConfigureDisplayEnabled` from the private SkyLight framework, the call
/// behind detaching a display without unplugging it.
enum SkyLight {
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError

    private static let configureEnabledSymbol: ConfigureEnabled? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let symbol = dlsym(handle, "CGSConfigureDisplayEnabled")
        else { return nil }
        return unsafeBitCast(symbol, to: ConfigureEnabled.self)
    }()

    static func configureEnabled(_ config: CGDisplayConfigRef, _ id: CGDirectDisplayID, _ enabled: Bool) -> CGError {
        configureEnabledSymbol?(config, id, enabled) ?? .notImplemented
    }
}

enum DisplayConfiguration {
    static func apply(_ change: (CGDisplayConfigRef) -> CGError) throws(DisplayError) {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { throw .coreGraphics(begin) }
        let result = change(config)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw .coreGraphics(result)
        }
        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        guard complete == .success else { throw .coreGraphics(complete) }
    }
}

public enum DisplayError: Error, CustomStringConvertible {
    case coreGraphics(CGError)
    case modeUnavailable(DisplaySize)
    case virtualDisplayFailed
    case onlyActiveDisplay
    case unknownDisplay(CGDirectDisplayID)

    public var description: String {
        switch self {
        case .coreGraphics(.notImplemented): "a private macOS display API is missing on this macOS version"
        case .coreGraphics(let error): "CoreGraphics error \(error.rawValue)"
        case .modeUnavailable(let size): "the virtual display has no \(size) HiDPI mode"
        case .virtualDisplayFailed: "macOS refused to create the virtual display"
        case .onlyActiveDisplay: "this is the only active display"
        case .unknownDisplay(let id): "no display with id \(id)"
        }
    }
}
