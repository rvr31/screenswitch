import AppKit
import CryptoKit
import ScreenSwitchCore

private let latestRelease = URL(string: "https://api.github.com/repos/rvr31/screenswitch/releases/latest")!

/// Positional arguments: our pid, the installed app, the new app, and where the
/// installed app goes until the new one is in place.
private let swapScript = """
    pid=$1 app=$2 new=$3 old=$4
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    mv "$app" "$old" || { open "$app"; exit 1; }
    if ! mv "$new" "$app"; then mv "$old" "$app"; open "$app"; exit 1; fi
    xattr -dr com.apple.quarantine "$app" 2>/dev/null
    rm -rf "$old"
    open "$app"
    """

private struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Checks GitHub for a newer release and replaces the running app with it.
@MainActor
final class Updater {
    let current: Version
    private(set) var state = UpdateState.idle

    /// Nil without a bundle version, as under `swift run`.
    init?() {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let current = Version(string)
        else { return nil }
        self.current = current
    }

    /// Checks now and once a day. A failed automatic check stays silent.
    func startChecking() {
        Task { _ = try? await check() }
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in _ = try? await self.check() }
        }
    }

    /// The newer release, or nil when this version is the latest.
    func check() async throws -> AvailableUpdate? {
        let previous = state
        switch state {
        case .checking, .installing: return nil
        case .idle, .available: break
        }
        state = .checking
        do {
            var request = URLRequest(url: latestRelease)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let release = try JSONDecoder().decode(Release.self, from: try await fetch(request))
            let update = UpdateCheck.update(from: release, current: current)
            state = update.map(UpdateState.available) ?? .idle
            return update
        } catch {
            state = previous
            throw error
        }
    }

    /// Quits on success; a shell script swaps the bundles once this process is gone.
    func install(_ update: AvailableUpdate) async throws {
        state = .installing(update.version)
        do {
            let app = Bundle.main.bundleURL
            let folder = app.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: folder.path) else {
                throw UpdateError("ScreenSwitch can't replace itself in \(folder.path). Download version \(update.version) from \(update.page.absoluteString) instead.")
            }
            // On the app's volume, so both moves in the script are renames.
            let dir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
            let name = update.archive.lastPathComponent
            let zip = try await fetch(URLRequest(url: update.archive))
            let sums = String(decoding: try await fetch(URLRequest(url: update.checksums)), as: UTF8.self)
            guard let expected = UpdateCheck.checksum(for: name, in: sums) else {
                throw UpdateError("SHA256SUMS has no checksum for \(name).")
            }
            guard SHA256.hash(data: zip).map({ String(format: "%02x", $0) }).joined() == expected else {
                throw UpdateError("\(name) does not match its checksum in SHA256SUMS.")
            }
            let zipFile = dir.appending(path: name)
            try zip.write(to: zipFile)
            let unpacked = dir.appending(path: "unpacked")
            try await run("/usr/bin/ditto", ["-x", "-k", zipFile.path, unpacked.path])
            let newApp = unpacked.appending(path: "ScreenSwitch.app")
            guard let id = Bundle.main.bundleIdentifier, Bundle(url: newApp)?.bundleIdentifier == id else {
                throw UpdateError("\(name) does not contain ScreenSwitch.app.")
            }
            let swap = Process()
            swap.executableURL = URL(filePath: "/bin/sh")
            swap.arguments = [
                "-c", swapScript, "screenswitch-update",
                String(getpid()), app.path, newApp.path, dir.appending(path: "ScreenSwitch-\(current).app").path,
            ]
            try swap.run()
        } catch {
            state = .available(update)
            throw error
        }
        NSApp.terminate(nil)
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw UpdateError("\(request.url?.absoluteString ?? "GitHub") answered HTTP \(status).")
        }
        return data
    }

    private func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let status = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw UpdateError("\(tool) exited with status \(status).") }
    }
}
