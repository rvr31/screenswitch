import Foundation
import Testing
@testable import ScreenSwitchCore

private func release(tag: String = "v0.1.10", assets: [String] = [
    "ScreenSwitch-0.1.10.zip", "screenswitch-cli-0.1.10-macos-universal.tar.gz", "SHA256SUMS",
]) throws -> Release {
    let base = "https://github.com/rvr31/screenswitch/releases/download/\(tag)"
    let assetJSON = assets.enumerated().map { index, name in
        """
        {"id": \(100 + index), "name": "\(name)", "content_type": "application/octet-stream",
         "size": 1234, "browser_download_url": "\(base)/\(name)"}
        """
    }
    let json = """
        {"id": 1, "tag_name": "\(tag)", "name": "ScreenSwitch \(tag)", "draft": false, "prerelease": false,
         "html_url": "https://github.com/rvr31/screenswitch/releases/tag/\(tag)",
         "published_at": "2026-10-01T12:00:00Z", "assets": [\(assetJSON.joined(separator: ","))]}
        """
    return try JSONDecoder().decode(Release.self, from: Data(json.utf8))
}

private func version(_ string: String) throws -> Version { try #require(Version(string)) }

@Test func versionsParseWithOrWithoutPrefixAndMissingParts() throws {
    let full = try version("1.2.3")
    #expect((full.major, full.minor, full.patch) == (1, 2, 3))
    #expect(try version("v1.2.3") == full)
    #expect(try version("1.0") == version("1.0.0"))
    #expect(try version("1.0").description == "1.0.0")
}

@Test(arguments: ["", "v", "1.", ".1", "1..2", "1.2.3.4", "a.b.c", "1.2.x", "+1.2", "1.-2", " 1.2", "1.2 ", "V1.2"])
func junkIsNotAVersion(_ string: String) {
    #expect(Version(string) == nil)
}

@Test func versionsOrderNumerically() throws {
    #expect(try version("0.1.10") > version("0.1.9"))
    #expect(try version("0.2.0") > version("0.1.99"))
    #expect(try version("1.0") > version("0.9.9"))
    #expect(try !(version("1.0") < version("1.0.0")))
}

@Test func newerReleaseOffersTheZipAndChecksums() throws {
    let update = try #require(UpdateCheck.update(from: release(), current: version("0.1.9")))
    let base = "https://github.com/rvr31/screenswitch/releases/download/v0.1.10"
    #expect(update.version == (try version("0.1.10")))
    #expect(update.archive.absoluteString == "\(base)/ScreenSwitch-0.1.10.zip")
    #expect(update.checksums.absoluteString == "\(base)/SHA256SUMS")
    #expect(update.page.absoluteString == "https://github.com/rvr31/screenswitch/releases/tag/v0.1.10")
}

@Test func sameOrOlderReleaseIsNoUpdate() throws {
    #expect(UpdateCheck.update(from: try release(), current: try version("0.1.10")) == nil)
    #expect(UpdateCheck.update(from: try release(), current: try version("1.0")) == nil)
}

@Test func releaseWithoutTheAppZipOrChecksumsIsNoUpdate() throws {
    let current = try version("0.1.9")
    #expect(UpdateCheck.update(from: try release(assets: ["SHA256SUMS"]), current: current) == nil)
    #expect(UpdateCheck.update(from: try release(assets: ["ScreenSwitch-0.1.10.zip"]), current: current) == nil)
    #expect(UpdateCheck.update(from: try release(tag: "nightly"), current: current) == nil)
}

@Test func checksumPicksTheLineForTheFile() {
    let sums = """
        1111111111111111111111111111111111111111111111111111111111111111  ScreenSwitch-0.1.10.zip
        2222222222222222222222222222222222222222222222222222222222222222  screenswitch-cli-0.1.10-macos-universal.tar.gz
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA *binary.zip

        """
    #expect(UpdateCheck.checksum(for: "ScreenSwitch-0.1.10.zip", in: sums) == String(repeating: "1", count: 64))
    #expect(UpdateCheck.checksum(for: "screenswitch-cli-0.1.10-macos-universal.tar.gz", in: sums) == String(repeating: "2", count: 64))
    #expect(UpdateCheck.checksum(for: "binary.zip", in: sums) == String(repeating: "a", count: 64))
    #expect(UpdateCheck.checksum(for: "ScreenSwitch-0.1.1.zip", in: sums) == nil)
}
