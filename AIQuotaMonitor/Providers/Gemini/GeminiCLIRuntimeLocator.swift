import Darwin
import Foundation

struct GeminiCLIRuntime: Equatable, Sendable {
    let executableURL: URL
    let workspaceURL: URL
    let homeURL: URL
}

protocol GeminiCLIRuntimeLocating: Sendable {
    func locate() throws -> GeminiCLIRuntime
}

enum GeminiCLIRuntimeError: Error, Equatable {
    case executableMissing
    case invalidExecutable
    case settingsMissing
    case trustedWorkspaceMissing
}

struct GeminiCLIRuntimeLocator: GeminiCLIRuntimeLocating {
    let homeURL: URL
    let executableURL: URL?
    let settingsURL: URL

    init(
        homeURL: URL? = nil,
        executableURL: URL? = nil,
        settingsURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let home = homeURL ?? fileManager.homeDirectoryForCurrentUser
        self.homeURL = home.standardizedFileURL
        self.executableURL = executableURL?.standardizedFileURL
        self.settingsURL = settingsURL?.standardizedFileURL
            ?? home.appending(path: ".gemini/antigravity-cli/settings.json").standardizedFileURL
    }

    func locate() throws -> GeminiCLIRuntime {
        let executable = try locateExecutable()
        let workspace = try locateTrustedWorkspace()
        return GeminiCLIRuntime(
            executableURL: executable,
            workspaceURL: workspace,
            homeURL: homeURL
        )
    }

    private func locateExecutable() throws -> URL {
        let candidates: [URL]
        if let executableURL {
            candidates = [executableURL]
        } else {
            candidates = [
                homeURL.appending(path: ".local/bin/agy"),
                URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
                URL(fileURLWithPath: "/usr/local/bin/agy"),
            ]
        }
        guard let existing = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw GeminiCLIRuntimeError.executableMissing
        }
        guard isSafeExecutable(existing) else {
            throw GeminiCLIRuntimeError.invalidExecutable
        }
        return existing.standardizedFileURL
    }

    private func locateTrustedWorkspace() throws -> URL {
        guard isSafeRegularFile(settingsURL, maximumBytes: 1_048_576),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            throw GeminiCLIRuntimeError.settingsMissing
        }
        for rawPath in settings.trustedWorkspaces ?? [] {
            guard rawPath.hasPrefix("/") else { continue }
            let candidate = URL(fileURLWithPath: rawPath).standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
        }
        throw GeminiCLIRuntimeError.trustedWorkspaceMissing
    }

    private func isSafeExecutable(_ url: URL) -> Bool {
        guard isSafeRegularFile(url, maximumBytes: 512 * 1_024 * 1_024),
              FileManager.default.isExecutableFile(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value else {
            return false
        }
        return owner == getuid() || owner == 0
    }

    private func isSafeRegularFile(_ url: URL, maximumBytes: Int) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]) else {
            return false
        }
        return values.isRegularFile == true
            && values.isSymbolicLink != true
            && (values.fileSize ?? maximumBytes + 1) <= maximumBytes
    }

    private struct Settings: Decodable {
        let trustedWorkspaces: [String]?
    }
}

struct GeminiConnectionEvidence: Equatable, Sendable {
    let ready: Bool
    let message: String

    static func inspect(locator: any GeminiCLIRuntimeLocating = GeminiCLIRuntimeLocator()) -> Self {
        do {
            _ = try locator.locate()
            return Self(
                ready: true,
                message: "공식 Antigravity CLI와 신뢰된 workspace를 확인했습니다."
            )
        } catch GeminiCLIRuntimeError.executableMissing {
            return Self(ready: false, message: "공식 Antigravity CLI(agy)를 찾지 못했습니다.")
        } catch GeminiCLIRuntimeError.invalidExecutable {
            return Self(ready: false, message: "Antigravity CLI 실행 파일의 형식·소유권·권한을 확인해 주세요.")
        } catch GeminiCLIRuntimeError.trustedWorkspaceMissing {
            return Self(ready: false, message: "agy에서 quota를 확인할 신뢰된 workspace를 먼저 등록해 주세요.")
        } catch {
            return Self(ready: false, message: "Antigravity CLI 설정을 확인하지 못했습니다.")
        }
    }
}
