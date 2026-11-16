import CoreGraphics
import Foundation

/// Built-in displays turned on for sleep, and when to turn them off again.
///
/// A display can be unplugged while the Mac sleeps. A Mac that wakes with its
/// built-in display turned off and no other display shows a black screen, and
/// no menu can reach it. So the built-in display goes to sleep turned on, and
/// goes off again after wake once another display is back online.
public struct SleepHold: Sendable {
    /// External displays can take several seconds after wake to come back.
    public static let window: TimeInterval = 60

    private var ids: [CGDirectDisplayID] = []
    /// Nil while asleep: the turn-on itself reconfigures the displays, and that
    /// must not turn them off again before the Mac sleeps.
    private var deadline: Date?

    public init() {}

    public mutating func sleep(holding ids: [CGDirectDisplayID]) {
        self.ids = ids
        deadline = nil
    }

    public mutating func wake(at now: Date) {
        deadline = now.addingTimeInterval(Self.window)
    }

    /// The held displays to turn off again now. Returns them once, when another
    /// display is online within the window after wake, and drops them after it.
    public mutating func due(online: [CGDirectDisplayID], now: Date) -> [CGDirectDisplayID] {
        guard !ids.isEmpty, let deadline else { return [] }
        guard now < deadline else {
            ids = []
            return []
        }
        guard online.contains(where: { !ids.contains($0) }) else { return [] }
        defer { ids = [] }
        return ids.filter(online.contains)
    }
}
