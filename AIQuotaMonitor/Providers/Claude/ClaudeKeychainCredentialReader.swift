import Foundation

struct ClaudeOAuthCredential: Sendable, Equatable {
    let accessToken: String
}

protocol ClaudeCredentialReading: Sendable {
    func read() async throws -> ClaudeOAuthCredential
}

struct ClaudeKeychainCredentialReader: ClaudeCredentialReading {
    static let service = "Claude Code-credentials"

    let runner: ProcessRunner
    let account: String

    init(
        runner: ProcessRunner = ProcessRunner(),
        account: String = ProcessInfo.processInfo.environment["USER"]
            ?? ProcessInfo.processInfo.environment["USERNAME"]
            ?? NSUserName()
    ) {
        self.runner = runner
        self.account = account
    }

    func read() async throws -> ClaudeOAuthCredential {
        guard !account.isEmpty else { throw ProviderErrorCode.missingCredential }
        let output: ProcessOutput
        do {
            output = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/security"),
                arguments: [
                    "find-generic-password",
                    "-s", Self.service,
                    "-a", account,
                    "-w",
                ],
                timeout: .seconds(8)
            )
        } catch let error as ProcessRunnerError {
            switch error {
            case .timeout: throw ProviderErrorCode.timeout
            case .cancelled: throw ProviderErrorCode.cancelled
            case .launchFailed: throw ProviderErrorCode.io
            }
        }
        guard output.exitCode == 0 else {
            throw output.exitCode == 44
                ? ProviderErrorCode.missingCredential
                : ProviderErrorCode.forbidden
        }
        return try Self.parseCredential(output.standardOutput)
    }

    static func parseCredential(_ data: Data) throws -> ClaudeOAuthCredential {
        guard data.count <= 1_048_576 else {
            throw ProviderErrorCode.malformedPayload
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderErrorCode.malformedPayload
        }
        guard let root = object as? [String: Any] else {
            throw ProviderErrorCode.malformedPayload
        }
        guard
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderErrorCode.invalidCredential
        }
        return ClaudeOAuthCredential(
            accessToken: token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
