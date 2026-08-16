import Foundation

struct CodexAppServerProvider: QuotaProvider {
    let id = ProviderID.codex
    let executableURL: URL
    let runner: ProcessRunner

    init(executableURL: URL, runner: ProcessRunner = ProcessRunner()) {
        self.executableURL = executableURL
        self.runner = runner
    }

    func availability() async -> ProviderAvailability {
        FileManager.default.isExecutableFile(atPath: executableURL.path) ? .available : .notConfigured
    }

    func fetchQuota() async -> ProviderFetchResult {
        let startedAt = Date()
        do {
            guard case .available = await availability() else { throw ProviderErrorCode.notFound }
            let output = try await runner.run(
                executable: executableURL,
                arguments: ["app-server", "--stdio"],
                environment: environment(),
                standardInput: requestData(),
                timeout: .seconds(12),
                closesStandardInput: false,
                outputCompletion: { hasResponse(requestID: 2, in: $0) }
            )
            guard output.exitCode == 0 || !output.standardOutput.isEmpty,
                  let result = try resultPayload(from: output.standardOutput) else {
                throw ProviderErrorCode.malformedPayload
            }
            var snapshot = try CodexQuotaParser().parse(result, observedAt: Date())
            snapshot.lastAttempt = CollectionAttempt(
                startedAt: startedAt,
                finishedAt: Date(),
                succeeded: true,
                diagnostic: nil
            )
            snapshot.lastSuccessAt = Date()
            return ProviderFetchResult(snapshot: snapshot)
        } catch let code as ProviderErrorCode {
            return failure(startedAt: startedAt, code: code)
        } catch let error as ProcessRunnerError {
            return failure(startedAt: startedAt, code: error == .timeout ? .timeout : .io)
        } catch {
            return failure(startedAt: startedAt, code: .malformedPayload)
        }
    }

    private func requestData() -> Data {
        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"QuotaBeacon","title":"QuotaBeacon read-only quota monitor","version":"0.1.0"},"capabilities":{"experimentalApi":true,"optOutNotificationMethods":["thread/started"]}}}"#
        let read = #"{"id":2,"method":"account/rateLimits/read"}"#
        return Data("\(initialize)\n\(read)\n".utf8)
    }

    private func resultPayload(from output: Data) throws -> Data? {
        for line in output.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["id"] as? Int == 2 else { continue }
            if object["error"] != nil { throw ProviderErrorCode.invalidCredential }
            guard let result = object["result"] else { throw ProviderErrorCode.malformedPayload }
            return try JSONSerialization.data(withJSONObject: result)
        }
        return nil
    }

    private func hasResponse(requestID: Int, in output: Data) -> Bool {
        output.split(separator: 0x0A).contains { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                return false
            }
            return object["id"] as? Int == requestID
        }
    }

    private func environment() -> [String: String] {
        var value = ProcessInfo.processInfo.environment
        value["CODEX_ANALYTICS_ENABLED"] = "false"
        return value
    }

    private func failure(startedAt: Date, code: ProviderErrorCode) -> ProviderFetchResult {
        var snapshot = ProviderSnapshot.unavailable(id, state: code == .invalidCredential ? .authenticationRequired : .failed)
        snapshot.lastAttempt = CollectionAttempt(
            startedAt: startedAt,
            finishedAt: Date(),
            succeeded: false,
            diagnostic: RedactedDiagnostic(summary: "Codex read-only quota collection failed.", code: code)
        )
        return ProviderFetchResult(snapshot: snapshot)
    }
}
