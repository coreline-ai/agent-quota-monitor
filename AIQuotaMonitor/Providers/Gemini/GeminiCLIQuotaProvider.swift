import Foundation

protocol GeminiQuotaExecuting: Sendable {
    func query(runtime: GeminiCLIRuntime) async throws -> Data
}

enum GeminiCLIExecutionError: Error, Equatable {
    case trustRequired
    case authenticationRequired
    case unsupportedOutput
    case failed
}

struct GeminiCLIQuotaExecutor: GeminiQuotaExecuting {
    let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    func query(runtime: GeminiCLIRuntime) async throws -> Data {
        let output: ProcessOutput
        do {
            output = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/expect"),
                arguments: ["-c", Self.expectScript],
                environment: Self.environment(for: runtime),
                timeout: .seconds(45),
                currentDirectory: runtime.workspaceURL,
                maximumOutputBytes: 512 * 1_024
            )
        } catch ProcessRunnerError.timeout {
            throw ProviderErrorCode.timeout
        } catch ProcessRunnerError.cancelled {
            throw ProviderErrorCode.cancelled
        } catch ProcessRunnerError.outputTooLarge {
            throw ProviderErrorCode.malformedPayload
        } catch {
            throw ProviderErrorCode.io
        }

        let combined = output.standardOutput + output.standardError
        let text = GeminiQuotaParser.sanitized(String(decoding: combined, as: UTF8.self))
        if output.exitCode == 44 { throw GeminiCLIExecutionError.trustRequired }
        if output.exitCode == 45 || output.exitCode == 47 { throw ProviderErrorCode.timeout }
        if Self.looksLikeAuthenticationFailure(text) {
            throw GeminiCLIExecutionError.authenticationRequired
        }
        guard output.exitCode == 0 else { throw GeminiCLIExecutionError.failed }
        guard let geminiOnlyText = GeminiQuotaParser.geminiOnlyText(from: text),
              geminiOnlyText.range(of: "Five Hour Limit Remaining", options: .caseInsensitive) != nil else {
            throw GeminiCLIExecutionError.unsupportedOutput
        }
        return Data(geminiOnlyText.utf8)
    }

    private static func environment(for runtime: GeminiCLIRuntime) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        return [
            "HOME": runtime.homeURL.path,
            "USER": inherited["USER"] ?? "user",
            "LOGNAME": inherited["LOGNAME"] ?? inherited["USER"] ?? "user",
            "SHELL": inherited["SHELL"] ?? "/bin/zsh",
            "TMPDIR": inherited["TMPDIR"] ?? NSTemporaryDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
            "AGY_CLI_DISABLE_AUTO_UPDATE": "1",
            "AGY_CLI_HIDE_ACCOUNT_INFO": "1",
            "QUOTABEACON_AGY_EXECUTABLE": runtime.executableURL.path,
        ]
    }

    private static func looksLikeAuthenticationFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("sign in to continue")
            || lower.contains("authentication required")
            || lower.contains("not authenticated")
    }

    static let expectScript = #"""
        set timeout 22
        log_user 1
        set env(TERM) "xterm-256color"
        set env(NO_COLOR) "1"
        proc stop_child {} {
          catch {send "\003"}
          after 150
          catch {send "\003"}
          after 150
          catch {exec /bin/kill -TERM [exp_pid]}
          after 250
          catch {exec /bin/kill -KILL [exp_pid]}
          catch {close}
          catch {wait}
        }
        spawn -noecho $env(QUOTABEACON_AGY_EXECUTABLE)
        stty rows 48 columns 120 < $spawn_out(slave,name)
        expect {
          -re {\x1b\[\?2026\$p} { send -- "\033\[?2026;2\$y"; exp_continue -continue_timer }
          -re {\x1b\[\?2027\$p} { send -- "\033\[?2027;2\$y"; exp_continue -continue_timer }
          -re {\x1b\[\?u} { send -- "\033\[?0u"; exp_continue -continue_timer }
          -re {Antigravity CLI [0-9]+[.][0-9]+[.][0-9]+} {}
          -re {Do you trust the contents} { stop_child; exit 44 }
          timeout { stop_child; exit 45 }
          eof { exit 46 }
        }
        send -- "/usage\r"
        set timeout 12
        expect {
          -re {\x1b\[\?2026\$p} { send -- "\033\[?2026;2\$y"; exp_continue -continue_timer }
          -re {\x1b\[\?2027\$p} { send -- "\033\[?2027;2\$y"; exp_continue -continue_timer }
          -re {\x1b\[\?u} { send -- "\033\[?0u"; exp_continue -continue_timer }
          -re {Five Hour Limit Remaining} { after 1300 }
          -re {Do you trust the contents} { stop_child; exit 44 }
          timeout {}
          eof { exit 46 }
        }
        stop_child
        exit 0
        """#
}

actor GeminiCLIQuotaProvider: QuotaProvider {
    nonisolated let id = ProviderID.gemini
    let locator: any GeminiCLIRuntimeLocating
    let executor: any GeminiQuotaExecuting

    private var cachedSuccess: ProviderFetchResult?
    private var lastRequestAt: Date?
    private static let minimumRequestInterval: TimeInterval = 5 * 60

    init(
        locator: any GeminiCLIRuntimeLocating = GeminiCLIRuntimeLocator(),
        executor: any GeminiQuotaExecuting = GeminiCLIQuotaExecutor()
    ) {
        self.locator = locator
        self.executor = executor
    }

    func availability() async -> ProviderAvailability {
        do {
            _ = try locator.locate()
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
            let runtime = try locator.locate()
            lastRequestAt = startedAt
            let output = try await executor.query(runtime: runtime)
            var snapshot = try GeminiQuotaParser().parse(output, observedAt: Date())
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
        } catch GeminiCLIRuntimeError.executableMissing,
                GeminiCLIRuntimeError.invalidExecutable,
                GeminiCLIRuntimeError.settingsMissing,
                GeminiCLIRuntimeError.trustedWorkspaceMissing,
                GeminiCLIExecutionError.trustRequired {
            return failure(startedAt: startedAt, code: .notFound)
        } catch GeminiCLIExecutionError.authenticationRequired {
            return failure(startedAt: startedAt, code: .invalidCredential)
        } catch GeminiCLIExecutionError.unsupportedOutput {
            return failure(startedAt: startedAt, code: .unsupported)
        } catch {
            return failure(startedAt: startedAt, code: .io)
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
                summary: "Gemini official Antigravity usage collection failed safely.",
                code: code
            )
        )
        return ProviderFetchResult(snapshot: snapshot)
    }
}
