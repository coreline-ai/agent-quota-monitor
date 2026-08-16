import Foundation
import SwiftUI

struct ProviderConnectionsView: View {
    @ObservedObject var model: QuotaMonitorModel

    @State private var codexEnabled = false
    @State private var codexPath = ""
    @State private var claudeEnabled = false
    @State private var claudePath = ""
    @State private var grokEnabled = false
    @State private var grokAuthPath = ""
    @State private var didLoad = false
    @State private var isApplying = false
    @State private var applyStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Provider 연결")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("dashboard.connections.title")
                    Text("토글만으로는 연결되지 않습니다. 경로를 확인하고 아래 적용 버튼을 눌러야 읽기 전용 수집이 시작됩니다.")
                        .foregroundStyle(.secondary)
                }

                SignalPanel(title: "Codex") {
                    Toggle("공식 Codex CLI quota 읽기", isOn: $codexEnabled)
                        .accessibilityIdentifier("connections.codex.toggle")
                    HStack {
                        TextField("codex 실행 파일 절대 경로", text: $codexPath)
                            .disabled(!codexEnabled)
                            .accessibilityIdentifier("connections.codex.path")
                        Button("자동 찾기") { codexPath = ProviderConnectionDefaults.codexExecutablePath() }
                            .disabled(!codexEnabled)
                    }
                    connectionEvidence(
                        executableExists(codexPath) ? "실행 가능한 Codex CLI를 확인했습니다." : "Codex CLI 경로를 확인해 주세요.",
                        available: executableExists(codexPath)
                    )
                    Text("공식 app-server의 rate-limit 읽기 method만 사용하며 모델·thread를 생성하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SignalPanel(title: "Claude Code") {
                    Toggle("0600 status snapshot 읽기", isOn: $claudeEnabled)
                        .accessibilityIdentifier("connections.claude.toggle")
                    TextField("snapshot 파일 절대 경로", text: $claudePath)
                        .disabled(!claudeEnabled)
                        .accessibilityIdentifier("connections.claude.path")
                    connectionEvidence(
                        secureFileExists(claudePath) ? "읽기 전용 snapshot을 확인했습니다." : "Claude snapshot bridge와 0600 파일이 필요합니다.",
                        available: secureFileExists(claudePath)
                    )
                    Text("Claude 설정은 자동으로 변경하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SignalPanel(title: "Grok Build · Beta") {
                    Toggle("Grok CLI billing quota 읽기", isOn: $grokEnabled)
                        .accessibilityIdentifier("connections.grok.toggle")
                    TextField("Grok auth.json 절대 경로", text: $grokAuthPath)
                        .disabled(!grokEnabled)
                        .accessibilityIdentifier("connections.grok.path")
                    connectionEvidence(
                        secureFileExists(grokAuthPath) ? "0600 Grok 로그인 파일을 확인했습니다." : "Grok auth.json 경로 또는 권한을 확인해 주세요.",
                        available: secureFileExists(grokAuthPath)
                    )
                    Text("적용하면 access token과 user ID를 xAI 공식 CLI billing 서버에 전송합니다. refresh token·browser cookie·prompt·모델 호출은 사용하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SignalPanel(title: "명시적 승인") {
                    HStack {
                        Button(isApplying ? "적용 중…" : "읽기 전용 연결 적용") {
                            Task { await applyConfiguration() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accentColor)
                        .disabled(isApplying)
                        .accessibilityIdentifier("connections.apply")

                        Button("모두 연결 해제") {
                            codexEnabled = false
                            claudeEnabled = false
                            grokEnabled = false
                            Task { await applyConfiguration() }
                        }
                        .disabled(isApplying)
                    }
                    if !applyStatus.isEmpty {
                        Text(applyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("connections.status")
                    }
                }
            }
            .padding(28)
        }
        .accessibilityIdentifier("dashboard.connections")
        .onAppear { loadConfigurationIfNeeded() }
    }

    @ViewBuilder
    private func connectionEvidence(_ text: String, available: Bool) -> some View {
        Label(text, systemImage: available ? "checkmark.circle.fill" : "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(available ? AppTheme.cyan : AppTheme.warning)
    }

    private func loadConfigurationIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        let defaults = UserDefaults.standard
        codexEnabled = defaults.bool(forKey: "codex.readOnlyEnabled")
        codexPath = defaults.string(forKey: "codex.executablePath")
            ?? ProviderConnectionDefaults.codexExecutablePath()
        claudeEnabled = defaults.bool(forKey: "claude.snapshotEnabled")
        claudePath = defaults.string(forKey: "claude.snapshotPath") ?? ""
        grokEnabled = defaults.bool(forKey: "grok.readOnlyEnabled")
        grokAuthPath = defaults.string(forKey: "grok.authPath")
            ?? ProviderConnectionDefaults.grokAuthPath
    }

    private func applyConfiguration() async {
        isApplying = true
        applyStatus = ""

        let normalizedCodexPath = expanded(codexPath)
        let normalizedClaudePath = expanded(claudePath)
        let normalizedGrokPath = expanded(grokAuthPath)
        codexPath = normalizedCodexPath
        claudePath = normalizedClaudePath
        grokAuthPath = normalizedGrokPath

        let defaults = UserDefaults.standard
        defaults.set(codexEnabled, forKey: "codex.readOnlyEnabled")
        defaults.set(normalizedCodexPath, forKey: "codex.executablePath")
        defaults.set(claudeEnabled, forKey: "claude.snapshotEnabled")
        defaults.set(normalizedClaudePath, forKey: "claude.snapshotPath")
        defaults.set(grokEnabled, forKey: "grok.readOnlyEnabled")
        defaults.set(normalizedGrokPath, forKey: "grok.authPath")

        await model.applyProviderConfiguration(
            codexEnabled: codexEnabled,
            codexExecutablePath: normalizedCodexPath,
            claudeEnabled: claudeEnabled,
            claudeSnapshotPath: normalizedClaudePath,
            grokEnabled: grokEnabled,
            grokAuthPath: normalizedGrokPath
        )

        let requested = model.snapshots.filter { snapshot in
            switch snapshot.provider {
            case .codex: codexEnabled
            case .claude: claudeEnabled
            case .grok: grokEnabled
            case .zai: false
            }
        }
        applyStatus = requested.isEmpty
            ? "모든 Provider 연결을 해제했습니다."
            : requested.map { "\($0.provider.displayName): \($0.state.label)" }.joined(separator: " · ")
        isApplying = false
    }

    private func executableExists(_ path: String) -> Bool {
        let path = expanded(path)
        return !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
    }

    private func secureFileExists(_ path: String) -> Bool {
        let path = expanded(path)
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        do {
            try CredentialFileValidator(allowedRoots: [url.deletingLastPathComponent()]).validate(url)
            return true
        } catch {
            return false
        }
    }

    private func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

enum ProviderConnectionDefaults {
    static var grokAuthPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".grok/auth.json").path
    }

    static func codexExecutablePath(fileManager: FileManager = .default) -> String {
        let home = fileManager.homeDirectoryForCurrentUser
        let fixedCandidates = [
            home.appending(path: ".local/bin/codex").path,
            home.appending(path: ".codex/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        if let match = fixedCandidates.first(where: fileManager.isExecutableFile(atPath:)) {
            return match
        }

        let versionsRoot = home.appending(path: ".nvm/versions/node")
        let versions = (try? fileManager.contentsOfDirectory(
            at: versionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for version in versions.sorted(by: {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
        }) {
            let candidate = version.appending(path: "bin/codex").path
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/opt/homebrew/bin/codex"
    }
}
