import Foundation
import SwiftUI

struct ProviderConnectionsView: View {
    @ObservedObject var model: QuotaMonitorModel

    @State private var codexEnabled = false
    @State private var codexPath = ""
    @State private var claudeEnabled = false
    @State private var grokEnabled = false
    @State private var grokAuthPath = ""
    @State private var geminiEnabled = false
    @State private var geminiPath = ""
    @State private var geminiEvidence = GeminiConnectionEvidence(
        ready: false,
        message: "Gemini 연결 환경을 확인하는 중입니다."
    )
    @State private var zaiEnabled = false
    @State private var zaiEvidence = ZAIConnectionEvidence(
        ready: false,
        message: "GLM 연결 환경을 확인하는 중입니다."
    )
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
                    Text("Provider별 로그인·실행 파일을 확인하고 아래 적용 버튼을 누르면 읽기 전용 수집이 시작됩니다.")
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
                    Toggle("로그인된 Claude quota 자동 읽기", isOn: $claudeEnabled)
                        .accessibilityIdentifier("connections.claude.toggle")
                    connectionEvidence(
                        claudeEnabled
                            ? "Claude Code macOS Keychain 로그인을 자동 탐색합니다."
                            : "연결을 켜면 기존 Claude Code 로그인을 사용합니다.",
                        available: claudeEnabled
                    )
                    Text("별도 경로·statusLine 설정 없이 access token을 메모리에서만 읽어 Anthropic usage GET에 사용합니다. refresh token·모델 호출·credential 변경은 하지 않습니다.")
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

                SignalPanel(title: "Gemini · Antigravity Beta") {
                    Toggle("공식 Antigravity Gemini quota 읽기", isOn: $geminiEnabled)
                        .accessibilityIdentifier("connections.gemini.toggle")
                    HStack {
                        TextField("agy 실행 파일 절대 경로", text: $geminiPath)
                            .disabled(!geminiEnabled)
                            .accessibilityIdentifier("connections.gemini.path")
                        Button("자동 찾기") {
                            geminiPath = ProviderConnectionDefaults.geminiExecutablePath()
                            updateGeminiEvidence()
                        }
                        .disabled(!geminiEnabled)
                    }
                    connectionEvidence(geminiEvidence.message, available: geminiEvidence.ready)
                        .accessibilityIdentifier("connections.gemini.evidence")
                    Text("공식 agy의 /usage만 실행해 GEMINI MODELS 그룹의 주간·5시간 잔여량만 정규화합니다. 화면에 함께 렌더된 계정 정보와 Claude/GPT 그룹은 즉시 폐기하며 OAuth 파일·모델 prompt에는 접근하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SignalPanel(title: "Z.ai GLM · Beta") {
                    Toggle("공식 GLM Usage Query 읽기", isOn: $zaiEnabled)
                        .accessibilityIdentifier("connections.zai.toggle")
                    connectionEvidence(zaiEvidence.message, available: zaiEvidence.ready)
                        .accessibilityIdentifier("connections.zai.evidence")
                    Text("기존 claude-glm 프로필과 Z.ai 공식 glm-plan-usage 플러그인을 자동 탐지합니다. 공식 script를 새로고침당 최대 1회 실행하며 모델 호출·로그인·credential 변경은 하지 않습니다.")
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
                            geminiEnabled = false
                            zaiEnabled = false
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
        .onChange(of: zaiEnabled) { _, enabled in
            zaiEvidence = enabled
                ? ZAIConnectionEvidence.inspect()
                : ZAIConnectionEvidence(
                    ready: false,
                    message: "연결을 켜면 공식 plugin과 claude-glm 프로필을 확인합니다."
                )
        }
        .onChange(of: geminiEnabled) { _, _ in updateGeminiEvidence() }
        .onChange(of: geminiPath) { _, _ in
            if geminiEnabled { updateGeminiEvidence() }
        }
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
        claudeEnabled = defaults.object(forKey: "claude.readOnlyEnabled") != nil
            ? defaults.bool(forKey: "claude.readOnlyEnabled")
            : defaults.bool(forKey: "claude.snapshotEnabled")
        grokEnabled = defaults.bool(forKey: "grok.readOnlyEnabled")
        grokAuthPath = defaults.string(forKey: "grok.authPath")
            ?? ProviderConnectionDefaults.grokAuthPath
        geminiEnabled = defaults.bool(forKey: "gemini.readOnlyEnabled")
        geminiPath = defaults.string(forKey: "gemini.executablePath")
            ?? ProviderConnectionDefaults.geminiExecutablePath()
        updateGeminiEvidence()
        zaiEnabled = defaults.bool(forKey: "zai.readOnlyEnabled")
        zaiEvidence = zaiEnabled
            ? ZAIConnectionEvidence.inspect()
            : ZAIConnectionEvidence(
                ready: false,
                message: "연결을 켜면 공식 plugin과 claude-glm 프로필을 확인합니다."
            )
    }

    private func applyConfiguration() async {
        isApplying = true
        applyStatus = ""

        let normalizedCodexPath = expanded(codexPath)
        let normalizedGrokPath = expanded(grokAuthPath)
        let normalizedGeminiPath = expanded(geminiPath)
        codexPath = normalizedCodexPath
        grokAuthPath = normalizedGrokPath
        geminiPath = normalizedGeminiPath

        let defaults = UserDefaults.standard
        defaults.set(codexEnabled, forKey: "codex.readOnlyEnabled")
        defaults.set(normalizedCodexPath, forKey: "codex.executablePath")
        defaults.set(claudeEnabled, forKey: "claude.readOnlyEnabled")
        defaults.set(grokEnabled, forKey: "grok.readOnlyEnabled")
        defaults.set(normalizedGrokPath, forKey: "grok.authPath")
        defaults.set(geminiEnabled, forKey: "gemini.readOnlyEnabled")
        defaults.set(normalizedGeminiPath, forKey: "gemini.executablePath")
        defaults.set(zaiEnabled, forKey: "zai.readOnlyEnabled")

        await model.applyProviderConfiguration(
            codexEnabled: codexEnabled,
            codexExecutablePath: normalizedCodexPath,
            claudeEnabled: claudeEnabled,
            grokEnabled: grokEnabled,
            grokAuthPath: normalizedGrokPath,
            geminiEnabled: geminiEnabled,
            geminiExecutablePath: normalizedGeminiPath,
            zaiEnabled: zaiEnabled
        )

        let requested = model.snapshots.filter { snapshot in
            switch snapshot.provider {
            case .codex: codexEnabled
            case .claude: claudeEnabled
            case .grok: grokEnabled
            case .gemini: geminiEnabled
            case .zai: zaiEnabled
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

    private func updateGeminiEvidence() {
        guard geminiEnabled else {
            geminiEvidence = GeminiConnectionEvidence(
                ready: false,
                message: "연결을 켜면 공식 Antigravity CLI와 신뢰된 workspace를 확인합니다."
            )
            return
        }
        let path = expanded(geminiPath)
        guard !path.isEmpty else {
            geminiEvidence = GeminiConnectionEvidence(
                ready: false,
                message: "Antigravity CLI 실행 파일 경로를 확인해 주세요."
            )
            return
        }
        geminiEvidence = GeminiConnectionEvidence.inspect(
            locator: GeminiCLIRuntimeLocator(executableURL: URL(fileURLWithPath: path))
        )
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

    static func geminiExecutablePath(fileManager: FileManager = .default) -> String {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/agy").path,
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ]
        return candidates.first(where: fileManager.isExecutableFile(atPath:))
            ?? home.appending(path: ".local/bin/agy").path
    }
}
