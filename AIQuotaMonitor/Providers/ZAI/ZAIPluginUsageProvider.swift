import Foundation

protocol ZAIUsageExecuting: Sendable {
    func query(runtime: ZAIPluginRuntime, profile: ZAIClaudeProfile) async throws -> Data
}

struct ZAIPluginUsageExecutor: ZAIUsageExecuting {
    let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    func query(runtime: ZAIPluginRuntime, profile: ZAIClaudeProfile) async throws -> Data {
        let output: ProcessOutput
        do {
            output = try await runner.run(
                executable: runtime.nodeURL,
                arguments: [runtime.scriptURL.path],
                environment: [
                    "ANTHROPIC_BASE_URL": profile.baseURL,
                    "ANTHROPIC_AUTH_TOKEN": profile.authToken,
                    "LANG": "en_US.UTF-8",
                ],
                timeout: .seconds(25)
            )
        } catch ProcessRunnerError.timeout {
            throw ProviderErrorCode.timeout
        } catch ProcessRunnerError.cancelled {
            throw ProviderErrorCode.cancelled
        } catch {
            throw ProviderErrorCode.io
        }

        guard output.exitCode == 0 else {
            let errorText = String(decoding: output.standardError + output.standardOutput, as: UTF8.self)
                .lowercased()
            if errorText.contains("http 401") { throw ProviderErrorCode.invalidCredential }
            if errorText.contains("http 403") { throw ProviderErrorCode.forbidden }
            if errorText.contains("http 429") { throw ProviderErrorCode.rateLimited }
            if errorText.contains("http 5") { throw ProviderErrorCode.server }
            throw ProviderErrorCode.io
        }
        return try ZAIPluginOutputExtractor.extractQuota(from: output.standardOutput)
    }
}

enum ZAIPluginOutputExtractor {
    private static let maximumOutputBytes = 2 * 1_024 * 1_024

    static func extractQuota(from data: Data) throws -> Data {
        guard data.count <= maximumOutputBytes else { throw ProviderErrorCode.malformedPayload }
        let output = String(decoding: data, as: UTF8.self)
        guard output.contains("Platform: ZAI") else { throw ProviderErrorCode.unsupported }
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline)
        guard let marker = lines.firstIndex(where: {
            $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "Quota limit data:"
        }) else {
            throw ProviderErrorCode.malformedPayload
        }
        for line in lines[lines.index(after: marker)...] {
            let candidate = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            let quota = Data(candidate.utf8)
            guard (try? JSONSerialization.jsonObject(with: quota)) is [String: Any] else {
                throw ProviderErrorCode.malformedPayload
            }
            return quota
        }
        throw ProviderErrorCode.malformedPayload
    }
}

actor ZAIPluginUsageProvider: QuotaProvider {
    nonisolated let id = ProviderID.zai
    let profileReader: any ZAIProfileReading
    let pluginLocator: any ZAIPluginLocating
    let executor: any ZAIUsageExecuting

    private var cachedSuccess: ProviderFetchResult?
    private var lastRequestAt: Date?
    private static let minimumRequestInterval: TimeInterval = 5 * 60

    init(
        profileReader: any ZAIProfileReading = ZAIClaudeProfileReader(),
        pluginLocator: any ZAIPluginLocating = ZAIPluginLocator(),
        executor: any ZAIUsageExecuting = ZAIPluginUsageExecutor()
    ) {
        self.profileReader = profileReader
        self.pluginLocator = pluginLocator
        self.executor = executor
    }

    func availability() async -> ProviderAvailability {
        do {
            _ = try profileReader.read()
            _ = try pluginLocator.locate()
            return .available
        } catch {
            return .notConfigured
        }
    }

    func fetchQuota() async -> ProviderFetchResult {
        let startedAt = Date()
        if let lastRequestAt,
           startedAt.timeIntervalSince(lastRequestAt) < Self.minimumRequestInterval,
           let cachedSuccess {
            return cachedSuccess
        }
        do {
            let profile = try profileReader.read()
            let runtime = try pluginLocator.locate()
            lastRequestAt = startedAt
            let quotaData = try await executor.query(runtime: runtime, profile: profile)
            var snapshot = try ZAIQuotaParser().parse(quotaData, observedAt: Date())
            snapshot.lastAttempt = CollectionAttempt(
                startedAt: startedAt,
                finishedAt: Date(),
                succeeded: true,
                diagnostic: nil
            )
            snapshot.lastSuccessAt = Date()
            let result = ProviderFetchResult(snapshot: snapshot)
            cachedSuccess = result
            return result
        } catch let code as ProviderErrorCode {
            return failure(startedAt: startedAt, code: code)
        } catch is ZAIProfileError {
            return failure(startedAt: startedAt, code: .missingCredential)
        } catch is ZAIPluginLocatorError {
            return failure(startedAt: startedAt, code: .unsupported)
        } catch {
            return failure(startedAt: startedAt, code: .malformedPayload)
        }
    }

    private func failure(startedAt: Date, code: ProviderErrorCode) -> ProviderFetchResult {
        let state: ProviderState = switch code {
        case .missingCredential, .notFound: .notConfigured
        case .invalidCredential: .authenticationRequired
        case .forbidden: .unsupportedAccount
        case .rateLimited: .rateLimited
        case .unsupported: .unsupportedContract
        case .server, .timeout, .cancelled, .malformedPayload, .io: .failed
        }
        var snapshot = ProviderSnapshot.unavailable(id, state: state)
        snapshot.lastAttempt = CollectionAttempt(
            startedAt: startedAt,
            finishedAt: Date(),
            succeeded: false,
            diagnostic: RedactedDiagnostic(
                summary: "GLM official usage plugin collection failed.",
                code: code
            )
        )
        return ProviderFetchResult(snapshot: snapshot)
    }
}
