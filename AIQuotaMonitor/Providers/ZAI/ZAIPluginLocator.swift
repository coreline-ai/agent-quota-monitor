import Foundation

struct ZAIPluginRuntime: Equatable, Sendable {
    let nodeURL: URL
    let scriptURL: URL
    let version: String
}

protocol ZAIPluginLocating: Sendable {
    func locate() throws -> ZAIPluginRuntime
}

enum ZAIPluginLocatorError: Error, Equatable {
    case pluginMissing
    case invalidPlugin
    case nodeMissing
}

struct ZAIPluginLocator: ZAIPluginLocating {
    let homeURL: URL

    init(homeURL: URL? = nil, fileManager: FileManager = .default) {
        self.homeURL = homeURL ?? fileManager.homeDirectoryForCurrentUser
    }

    func locate() throws -> ZAIPluginRuntime {
        let fileManager = FileManager.default
        let pluginRoot = homeURL.appending(
            path: ".claude/plugins/cache/zai-coding-plugins/glm-plan-usage"
        ).standardizedFileURL
        let versions = ((try? fileManager.contentsOfDirectory(
            at: pluginRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
        }
        guard !versions.isEmpty else { throw ZAIPluginLocatorError.pluginMissing }
        guard let nodeURL = locateNode() else { throw ZAIPluginLocatorError.nodeMissing }

        for versionURL in versions {
            let manifestURL = versionURL.appending(path: ".claude-plugin/plugin.json")
            let scriptURL = versionURL.appending(
                path: "skills/usage-query-skill/scripts/query-usage.mjs"
            )
            guard isSafeRegularFile(manifestURL), isSafeRegularFile(scriptURL) else { continue }
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  manifest.name == "glm-plan-usage",
                  manifest.version == versionURL.lastPathComponent else { continue }
            return ZAIPluginRuntime(
                nodeURL: nodeURL,
                scriptURL: scriptURL.standardizedFileURL,
                version: manifest.version
            )
        }
        throw ZAIPluginLocatorError.invalidPlugin
    }

    private func locateNode() -> URL? {
        let fileManager = FileManager.default
        let fixed = [
            homeURL.appending(path: ".local/bin/node"),
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node"),
            URL(fileURLWithPath: "/usr/bin/node"),
        ]
        if let match = fixed.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return match.standardizedFileURL
        }

        let versionsRoot = homeURL.appending(path: ".nvm/versions/node")
        let versions = ((try? fileManager.contentsOfDirectory(
            at: versionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
        }
        return versions
            .map { $0.appending(path: "bin/node") }
            .first { fileManager.isExecutableFile(atPath: $0.path) }?
            .standardizedFileURL
    }

    private func isSafeRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private struct Manifest: Decodable {
        let name: String
        let version: String
    }
}

struct ZAIConnectionEvidence: Equatable, Sendable {
    let ready: Bool
    let message: String

    static func inspect(
        profileReader: any ZAIProfileReading = ZAIClaudeProfileReader(),
        pluginLocator: any ZAIPluginLocating = ZAIPluginLocator()
    ) -> Self {
        do {
            _ = try profileReader.read()
        } catch {
            return Self(
                ready: false,
                message: "claude-glm 프로필에서 Z.ai 인증 환경을 찾지 못했습니다."
            )
        }
        do {
            let runtime = try pluginLocator.locate()
            return Self(
                ready: true,
                message: "공식 glm-plan-usage \(runtime.version)과 claude-glm 프로필을 확인했습니다."
            )
        } catch ZAIPluginLocatorError.nodeMissing {
            return Self(ready: false, message: "Node.js 18+ 실행 파일을 찾지 못했습니다.")
        } catch {
            return Self(
                ready: false,
                message: "공식 glm-plan-usage 플러그인을 Claude Code user scope에 설치해 주세요."
            )
        }
    }
}
