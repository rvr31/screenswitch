public enum DisplayTarget: Codable, Hashable, Sendable, CustomStringConvertible {
    case off
    case native
    case virtual(DisplaySize)

    public var description: String {
        switch self {
        case .off: "off"
        case .native: "native"
        case .virtual(let size): "virtual \(size)"
        }
    }
}

/// The target keys are also the trigger: a profile covers exactly the set of
/// displays it has a target for.
public struct Profile: Codable, Hashable, Sendable {
    public var name: String
    public var targets: [DisplayKey: DisplayTarget]

    public init(name: String, targets: [DisplayKey: DisplayTarget]) {
        self.name = name
        self.targets = targets
    }

    /// The changes that take `current` to this profile. Displays turn on first
    /// and off last, so a switch never leaves no display active on the way.
    /// Displays already at their target and displays not connected get no step.
    public func steps(from current: [DisplayKey: DisplayTarget]) -> [ProfileStep] {
        var turnOn: [ProfileStep] = [], change: [ProfileStep] = [], turnOff: [ProfileStep] = []
        for (key, target) in targets.sorted(by: { $0.key < $1.key }) {
            guard let now = current[key], now != target else { continue }
            if now == .off { turnOn.append(.turnOn(key)) }
            switch target {
            case .off: turnOff.append(.turnOff(key))
            case .native where now != .off: change.append(.setNative(key))
            case .native: break
            case .virtual(let size): change.append(.setVirtual(key, size))
            }
        }
        return turnOn + change + turnOff
    }
}

public enum ProfileStep: Equatable, Sendable {
    case turnOn(DisplayKey)
    case setNative(DisplayKey)
    case setVirtual(DisplayKey, DisplaySize)
    case turnOff(DisplayKey)
}

/// Saved profiles, most recently applied first, so that among profiles covering
/// the same displays the automatic switch picks the one used last.
public struct ProfileList: Equatable, Sendable {
    public private(set) var profiles: [Profile]

    public init(_ profiles: [Profile] = []) {
        self.profiles = profiles
    }

    public subscript(name: String) -> Profile? {
        profiles.first { $0.name == name }
    }

    /// Adds the profile as the most recent one, replacing a profile with the same name.
    public mutating func save(_ profile: Profile) {
        delete(name: profile.name)
        profiles.insert(profile, at: 0)
    }

    public mutating func markApplied(_ name: String) {
        if let profile = self[name] { save(profile) }
    }

    public mutating func delete(name: String) {
        profiles.removeAll { $0.name == name }
    }

    public func matching(connected: Set<DisplayKey>) -> Profile? {
        profiles.first { Set($0.targets.keys) == connected }
    }

    /// `current` has an entry for exactly the connected displays, so equality
    /// also requires the profile to cover the connected set.
    public func active(current: [DisplayKey: DisplayTarget]) -> Profile? {
        profiles.first { $0.targets == current }
    }
}
