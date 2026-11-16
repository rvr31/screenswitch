import Testing
@testable import ScreenSwitchCore

@Test func versionsCompareNumericallyNotAsText() throws {
    let nine = try #require(ReleaseVersion("0.1.9"))
    let ten = try #require(ReleaseVersion("v0.1.10"))
    #expect(nine < ten)
    #expect(try #require(ReleaseVersion("1.0")) > ten)
}

@Test func missingTrailingPartsCountAsZero() throws {
    #expect(try #require(ReleaseVersion("1.0")) == #require(ReleaseVersion("v1.0.0")))
}

@Test func textThatIsNotAVersionIsRejected() {
    #expect(ReleaseVersion("dev") == nil)
    #expect(ReleaseVersion("v1.2.x") == nil)
    #expect(ReleaseVersion("") == nil)
}

@Test func releasePageIsBuiltFromTheParsedVersion() throws {
    let version = try #require(ReleaseVersion("v0.1.9"))
    #expect(version.releasePage.absoluteString == "https://github.com/rvr31/screenswitch/releases/tag/v0.1.9")
}
