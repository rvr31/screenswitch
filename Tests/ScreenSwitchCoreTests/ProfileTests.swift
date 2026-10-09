import Foundation
import Testing
@testable import ScreenSwitchCore

private let builtin = DisplayKey(vendor: 0x610, model: 1, serial: 0)
private let dell = DisplayKey(vendor: 0x10ac, model: 2, serial: 7)
private let lg = DisplayKey(vendor: 0x1e6d, model: 3, serial: 9)
private let scaled = DisplaySize(width: 2304, height: 1440)

@Test func stepsTurnOnFirstThenResizeThenTurnOffLast() {
    let profile = Profile(name: "Desk", targets: [builtin: .off, dell: .virtual(scaled), lg: .native])
    let current: [DisplayKey: DisplayTarget] = [builtin: .native, dell: .off, lg: .virtual(scaled)]
    #expect(profile.steps(from: current) == [
        .turnOn(dell),
        .setVirtual(dell, scaled),
        .setNative(lg),
        .turnOff(builtin),
    ])
}

@Test func turningOnToNativeNeedsNoSeparateNativeStep() {
    let profile = Profile(name: "Laptop", targets: [builtin: .native])
    #expect(profile.steps(from: [builtin: .off]) == [.turnOn(builtin)])
}

@Test func applyingAProfileThatAlreadyMatchesDoesNothing() {
    let targets: [DisplayKey: DisplayTarget] = [builtin: .off, dell: .virtual(scaled)]
    #expect(Profile(name: "Desk", targets: targets).steps(from: targets).isEmpty)
}

@Test func displaysThatAreNotConnectedGetNoSteps() {
    let profile = Profile(name: "Desk", targets: [builtin: .off, dell: .virtual(scaled), lg: .virtual(scaled)])
    #expect(profile.steps(from: [builtin: .native, dell: .native]) == [.setVirtual(dell, scaled), .turnOff(builtin)])
}

@Test func profileIsActiveOnlyWhenEveryTargetMatchesAndItCoversTheConnectedSet() {
    let list = ProfileList([Profile(name: "Desk", targets: [builtin: .off, dell: .virtual(scaled)])])
    #expect(list.active(current: [builtin: .off, dell: .virtual(scaled)])?.name == "Desk")
    #expect(list.active(current: [builtin: .off, dell: .native]) == nil)
    #expect(list.active(current: [builtin: .off, dell: .virtual(scaled), lg: .native]) == nil)
    #expect(list.active(current: [dell: .virtual(scaled)]) == nil)
}

@Test func matchingPicksTheMostRecentlyAppliedProfileForTheConnectedSet() {
    var list = ProfileList()
    list.save(Profile(name: "Desk", targets: [builtin: .off, dell: .native]))
    list.save(Profile(name: "Presenting", targets: [builtin: .native, dell: .native]))
    list.save(Profile(name: "Travel", targets: [builtin: .native]))
    #expect(list.matching(connected: [builtin, dell])?.name == "Presenting")
    list.markApplied("Desk")
    #expect(list.matching(connected: [builtin, dell])?.name == "Desk")
    #expect(list.matching(connected: [builtin])?.name == "Travel")
    #expect(list.matching(connected: [dell]) == nil)
}

@Test func savingUnderAnExistingNameReplacesThatProfile() {
    var list = ProfileList()
    list.save(Profile(name: "Desk", targets: [dell: .native]))
    list.save(Profile(name: "Desk", targets: [dell: .virtual(scaled)]))
    #expect(list.profiles == [Profile(name: "Desk", targets: [dell: .virtual(scaled)])])
}

@Test func profilesSurviveAJSONRoundTrip() throws {
    let profiles = [Profile(name: "Desk", targets: [builtin: .off, dell: .virtual(scaled), lg: .native])]
    let decoded = try JSONDecoder().decode([Profile].self, from: JSONEncoder().encode(profiles))
    #expect(decoded == profiles)
}
