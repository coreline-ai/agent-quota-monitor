import Foundation

struct CodexRuntime: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case explicit
        case path
        case userLocal
        case nodeManager
        case applicationBundle
    }

    let executableURL: URL
    let runtimeURL: URL?
    let source: Source
}

/// Resolves the installed Codex CLI without relying on an interactive shell.
/// GUI-launched macOS apps do not inherit the user's login-shell PATH, so the
/// resolver checks deterministic user-local, package-manager, and app-bundle
/// locations before returning no result.
struct CodexRuntimeLocator {
    let homeURL: URL
    let path: String
    let fileManager: FileManager
    let applicationRoots: [URL]

    init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        fileManager: FileManager = .default,
        applicationRoots: [URL]? = nil
    ) {
        self.homeURL = homeURL.standardizedFileURL
        self.path = path ?? ""
        self.fileManager = fileManager
        self.applicationRoots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            homeURL.appending(path: "Applications/Codex.app"),
            homeURL.appending(path: "Applications/ChatGPT.app")
        ]
    }

    func locate(explicitURL: URL? = nil) -> CodexRuntime? {
        locateAll(explicitURL: explicitURL).first
    }

    func locateAll(explicitURL: URL? = nil) -> [CodexRuntime] {
        var candidates: [(URL, CodexRuntime.Source)] = []
        if let explicitURL {
            candidates.append((explicitURL, .explicit))
        }

        candidates.append(contentsOf: pathCandidates().map { ($0, .path) })
        candidates.append(contentsOf: fixedCandidates().map { ($0, .userLocal) })
        candidates.append(contentsOf: nodeManagerCandidates().map { ($0, .nodeManager) })
        candidates.append(contentsOf: applicationCandidates().map { ($0, .applicationBundle) })

        var seen = Set<String>()
        var runtimes: [CodexRuntime] = []
        for (candidate, source) in candidates {
            let normalized = candidate.standardizedFileURL
            guard seen.insert(normalized.path).inserted else { continue }
            guard fileManager.isExecutableFile(atPath: normalized.path) else { continue }
            runtimes.append(CodexRuntime(
                executableURL: normalized,
                runtimeURL: runtimeURL(for: normalized),
                source: source
            ))
        }
        return runtimes
    }

    private func pathCandidates() -> [URL] {
        path.split(separator: ":", omittingEmptySubsequences: true).map { entry in
            URL(fileURLWithPath: String(entry)).appending(path: "codex")
        }
    }

    private func fixedCandidates() -> [URL] {
        [
            homeURL.appending(path: ".local/bin/codex"),
            homeURL.appending(path: ".codex/bin/codex"),
            homeURL.appending(path: ".bun/bin/codex"),
            homeURL.appending(path: ".bun/install/global/bin/codex"),
            homeURL.appending(path: "Library/pnpm/codex"),
            homeURL.appending(path: ".volta/bin/codex"),
            homeURL.appending(path: ".asdf/shims/codex"),
            homeURL.appending(path: ".local/share/mise/shims/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            URL(fileURLWithPath: "/opt/local/bin/codex")
        ]
    }

    private func nodeManagerCandidates() -> [URL] {
        var candidates: [URL] = []
        candidates.append(contentsOf: versionedBinCandidates(
            root: homeURL.appending(path: ".nvm/versions/node"),
            binName: "codex"
        ))
        candidates.append(contentsOf: versionedBinCandidates(
            root: homeURL.appending(path: ".fnm/node-versions"),
            binName: "codex",
            suffix: "installation/bin"
        ))
        candidates.append(contentsOf: versionedBinCandidates(
            root: homeURL.appending(path: "Library/Application Support/fnm/node-versions"),
            binName: "codex",
            suffix: "installation/bin"
        ))
        candidates.append(contentsOf: versionedBinCandidates(
            root: homeURL.appending(path: ".volta/tools/image/node"),
            binName: "codex",
            suffix: "bin"
        ))
        candidates.append(contentsOf: versionedBinCandidates(
            root: homeURL.appending(path: ".asdf/installs/nodejs"),
            binName: "codex",
            suffix: "bin"
        ))
        candidates.append(contentsOf: versionedBinCandidates(
            root: homeURL.appending(path: ".local/share/mise/installs/node"),
            binName: "codex",
            suffix: "bin"
        ))
        return candidates
    }

    private func versionedBinCandidates(
        root: URL,
        binName: String,
        suffix: String = "bin"
    ) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appending(path: suffix).appending(path: binName) }
    }

    private func applicationCandidates() -> [URL] {
        applicationRoots.flatMap { root in
            [
                root.appending(path: "Contents/Resources/codex"),
                root.appending(path: "Contents/Resources/bin/codex"),
                root.appending(path: "Contents/Helpers/codex")
            ]
        }
    }

    private func runtimeURL(for executable: URL) -> URL? {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1_024),
              let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(whereSeparator: \.isNewline).first,
              firstLine.hasPrefix("#!") else {
            return nil
        }

        let tokens = firstLine.dropFirst(2)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard let interpreter = tokens.first else { return nil }
        if interpreter == "/usr/bin/env", let command = tokens.dropFirst().first {
            return findExecutable(named: command, near: executable.deletingLastPathComponent())
        }
        let interpreterURL = URL(fileURLWithPath: interpreter)
        return fileManager.isExecutableFile(atPath: interpreterURL.path) ? interpreterURL : nil
    }

    private func findExecutable(named name: String, near directory: URL) -> URL? {
        let candidates = [
            directory.appending(path: name),
            URL(fileURLWithPath: "/opt/homebrew/bin").appending(path: name),
            URL(fileURLWithPath: "/usr/local/bin").appending(path: name),
            homeURL.appending(path: ".volta/bin").appending(path: name),
            homeURL.appending(path: ".asdf/shims").appending(path: name),
            homeURL.appending(path: ".local/share/mise/shims").appending(path: name)
        ] + pathCandidates(for: name)
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func pathCandidates(for name: String) -> [URL] {
        path.split(separator: ":", omittingEmptySubsequences: true).map { entry in
            URL(fileURLWithPath: String(entry)).appending(path: name)
        }
    }
}
