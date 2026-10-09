// Step-by-step diagnostic of the virtual display path on one physical display.
// Runs with the same process setup as the app (AppKit touched, reconfiguration
// callback registered), then tries three strategies in a row and logs the
// virtual display's mode list after every step:
//   A. create, apply settings, mirror
//   B. set the 2x mode explicitly while mirrored
//   C. unmirror and disable, enable, apply settings, mirror (the parked path)
// Usage: swiftc -import-objc-header Sources/PrivateDisplay/include/PrivateDisplay.h \
//            -framework AppKit scripts/diag-virtual.swift -o build/diag-virtual
//        build/diag-virtual <physical display id>
import AppKit
import CoreGraphics

typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError
let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)!
let configureEnabled = unsafeBitCast(dlsym(skyLight, "CGSConfigureDisplayEnabled")!, to: ConfigureEnabledFn.self)

let physical = CGDirectDisplayID(CommandLine.arguments[1])!
let panel = CGDisplayCopyDisplayMode(physical)!
let (w, h) = (panel.pixelWidth / 2, panel.pixelHeight / 2)

func lists() -> String {
    var n: UInt32 = 0
    var a = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetActiveDisplayList(16, &a, &n)
    let act = Array(a.prefix(Int(n)))
    CGGetOnlineDisplayList(16, &a, &n)
    let onl = Array(a.prefix(Int(n)))
    return "active=\(act) online=\(onl)"
}
func describe(_ m: CGDisplayMode) -> String { "\(m.width)x\(m.height)@\(m.pixelWidth)x\(m.pixelHeight)" }
let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
func allModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
    guard let array = CGDisplayCopyAllDisplayModes(id, opts) else { return [] }
    return (0..<CFArrayGetCount(array)).map { unsafeBitCast(CFArrayGetValueAtIndex(array, $0), to: CGDisplayMode.self) }
}
func modes(_ id: CGDirectDisplayID) -> String {
    let cur = CGDisplayCopyDisplayMode(id).map(describe) ?? "none"
    return "current=\(cur) modes=\(allModes(id).map(describe))"
}
func spin(_ s: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: s)) }
func config(_ f: (CGDisplayConfigRef) -> CGError) -> String {
    var c: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&c)
    let r = f(c!)
    let e = CGCompleteDisplayConfiguration(c, .permanently)
    return "configure=\(r.rawValue) complete=\(e.rawValue)"
}
func report(_ label: String, _ id: CGDirectDisplayID) {
    spin(2)
    print("\(label): \(lists()) \(modes(id))")
}
func unmirrorAndDisable(_ id: CGDirectDisplayID) -> String {
    config { c in
        let r = CGConfigureDisplayMirrorOfDisplay(c, physical, kCGNullDirectDisplay)
        return r == .success ? configureEnabled(c, id, false) : r
    }
}
func twoX(_ id: CGDirectDisplayID) -> CGDisplayMode? {
    allModes(id).first { $0.width == w && $0.height == h && $0.pixelWidth == w * 2 }
}

// Same process setup as the app.
_ = NSScreen.screens
CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
    if !flags.contains(.beginConfigurationFlag) { print("  (reconfiguration callback)") }
}, nil)

let d = CGVirtualDisplayDescriptor()
d.name = "Diag"
d.queue = .main
d.vendorID = 0x5353
d.productID = 0x5357
d.serialNum = physical
d.maxPixelsWide = UInt32(panel.pixelWidth * 2)
d.maxPixelsHigh = UInt32(panel.pixelHeight * 2)
d.sizeInMillimeters = CGDisplayScreenSize(physical)
d.redPrimary = CGPoint(x: 0.68, y: 0.32)
d.greenPrimary = CGPoint(x: 0.265, y: 0.69)
d.bluePrimary = CGPoint(x: 0.15, y: 0.06)
d.whitePoint = CGPoint(x: 0.3127, y: 0.329)
print("panel \(describe(panel)); virtual \(w)x\(h) hiDPI; \(lists())")
let vd = CGVirtualDisplay(descriptor: d)!
let s = CGVirtualDisplaySettings()
s.hiDPI = 1
s.modes = [CGVirtualDisplayMode(width: UInt32(w), height: UInt32(h), refreshRate: 120)]
let id = vd.displayID
print("A: apply=\(vd.apply(s)) id=\(id)")
report("A: after apply", id)
print("A: mirror \(config { CGConfigureDisplayMirrorOfDisplay($0, physical, id) })")
report("A: after mirror", id)

if let m = twoX(id) {
    print("B: set 2x while mirrored \(config { CGConfigureDisplayWithDisplayMode($0, id, m, nil) })")
    report("B: after mode set", id)
} else {
    print("B: skipped, no 2x mode listed")
}

print("C: unmirror+disable \(unmirrorAndDisable(id))")
report("C: parked", id)
print("C: enable \(config { configureEnabled($0, id, true) })")
report("C: enabled", id)
print("C: apply=\(vd.apply(s))")
report("C: after apply", id)
print("C: mirror \(config { CGConfigureDisplayMirrorOfDisplay($0, physical, id) })")
report("C: after mirror", id)
if let m = twoX(id), CGDisplayCopyDisplayMode(id).map({ $0.pixelWidth != w * 2 }) ?? true {
    print("C: set 2x while mirrored \(config { CGConfigureDisplayWithDisplayMode($0, id, m, nil) })")
    report("C: after mode set", id)
}

print("end: unmirror+disable \(unmirrorAndDisable(id))")
spin(1)
print("end: \(lists())")
