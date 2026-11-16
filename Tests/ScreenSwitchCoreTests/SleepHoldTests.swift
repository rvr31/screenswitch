import CoreGraphics
import Foundation
import Testing
@testable import ScreenSwitchCore

private let builtin: CGDirectDisplayID = 1
private let dell: CGDirectDisplayID = 4
private let wake = Date(timeIntervalSince1970: 1_000)

@Test func heldDisplayStaysOnWhileAsleep() {
    var hold = SleepHold()
    hold.sleep(holding: [builtin])
    #expect(hold.due(online: [builtin, dell], now: wake).isEmpty)
}

@Test func heldDisplayGoesOffOnceAnotherDisplayIsBackAfterWake() {
    var hold = SleepHold()
    hold.sleep(holding: [builtin])
    hold.wake(at: wake)
    #expect(hold.due(online: [builtin], now: wake).isEmpty)
    #expect(hold.due(online: [builtin, dell], now: wake + 5) == [builtin])
    #expect(hold.due(online: [builtin, dell], now: wake + 6).isEmpty)
}

@Test func holdEndsWhenNoOtherDisplayReturnsInTime() {
    var hold = SleepHold()
    hold.sleep(holding: [builtin])
    hold.wake(at: wake)
    #expect(hold.due(online: [builtin], now: wake + SleepHold.window).isEmpty)
    #expect(hold.due(online: [builtin, dell], now: wake + 1).isEmpty)
}
