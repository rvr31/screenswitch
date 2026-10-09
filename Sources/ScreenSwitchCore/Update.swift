import Foundation

public struct Version: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Accepts "v1.2.3", "1.2.3" and "1.0"; missing parts are 0.
    public init?(_ string: String) {
        let parts = (string.hasPrefix("v") ? string.dropFirst() : Substring(string))
            .split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard part.allSatisfy({ ("0"..."9").contains($0) }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        numbers += Array(repeating: 0, count: 3 - numbers.count)
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The fields ScreenSwitch reads from GitHub's `releases/latest` response.
public struct Release: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let url: URL

        enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
        }
    }

    public let tag: String
    public let page: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case page = "html_url"
        case assets
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: Version
    public let archive: URL
    public let checksums: URL
    /// The release on GitHub, for a manual download.
    public let page: URL
}

public enum UpdateCheck {
    /// Nil unless the release is newer and has both the app zip and SHA256SUMS.
    public static func update(from release: Release, current: Version) -> AvailableUpdate? {
        guard let version = Version(release.tag), version > current,
              let archive = release.assets.first(where: { $0.name == "ScreenSwitch-\(version).zip" }),
              let checksums = release.assets.first(where: { $0.name == "SHA256SUMS" })
        else { return nil }
        return AvailableUpdate(version: version, archive: archive.url, checksums: checksums.url, page: release.page)
    }

    /// The lowercase hex digest for `fileName` in `shasum -a 256` output.
    public static func checksum(for fileName: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 1)
            guard fields.count == 2 else { continue }
            var name = fields[1].drop { $0 == " " }
            // shasum marks binary mode with a `*` before the name.
            if name.hasPrefix("*") { name = name.dropFirst() }
            if name == fileName { return fields[0].lowercased() }
        }
        return nil
    }
}

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case available(AvailableUpdate)
    case installing(Version)
}
