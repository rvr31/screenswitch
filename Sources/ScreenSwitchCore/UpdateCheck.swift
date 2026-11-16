import Foundation

/// The version of the running build, from the app bundle's Info.plist.
public enum AppVersion {
    /// "dev" outside an app bundle, as with `swift run`.
    public static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// A release version such as `0.1.9`, with or without the tag's leading `v`.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    private let parts: [Int]

    public init?(_ text: String) {
        let digits = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        let pad = { (v: ReleaseVersion) in v.parts + Array(repeating: 0, count: count - v.parts.count) }
        return pad(a).lexicographicallyPrecedes(pad(b))
    }

    public static func == (a: ReleaseVersion, b: ReleaseVersion) -> Bool { !(a < b) && !(b < a) }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// The page of this release on GitHub. Built from the parsed version, not
    /// from a URL in the API response.
    public var releasePage: URL {
        URL(string: "https://github.com/rvr31/screenswitch/releases/tag/v\(self)")!
    }
}

public enum UpdateError: Error, CustomStringConvertible {
    case unreachable(String)
    case unexpectedResponse

    public var description: String {
        switch self {
        case .unreachable(let reason): "GitHub could not be reached: \(reason)"
        case .unexpectedResponse: "GitHub sent a response ScreenSwitch does not understand"
        }
    }
}

public enum UpdateCheck {
    private struct Release: Decodable {
        let tag_name: String
    }

    /// The newest published release of ScreenSwitch.
    public static func latest() async throws(UpdateError) -> ReleaseVersion {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/rvr31/screenswitch/releases/latest")!)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ScreenSwitch", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw .unreachable(error.localizedDescription)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              let version = ReleaseVersion(release.tag_name)
        else { throw .unexpectedResponse }
        return version
    }
}
