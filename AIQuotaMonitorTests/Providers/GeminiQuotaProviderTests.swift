import Darwin
import Foundation
import XCTest
@testable import AIQuotaMonitor

final class GeminiQuotaProviderTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_786_860_000)

    func testParserReadsOnlyGeminiWeeklyAndFiveHourBuckets() throws {
        let snapshot = try GeminiQuotaParser().parse(fixture("normal"), observedAt: observedAt)
        XCTAssertEqual(snapshot.provider, .gemini)
        XCTAssertEqual(snapshot.state, .available)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(
            snapshot.windows.first { $0.kind == .sharedWeekly }?.usedRatio.value ?? -1,
            0.36,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            snapshot.windows.first { $0.kind == .fiveHour }?.usedRatio.value ?? -1,
            0.10,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            snapshot.windows.first { $0.kind == .sharedWeekly }?.resetsAt,
            observedAt.addingTimeInterval(2 * 86_400 + 3 * 3_600)
        )
        XCTAssertEqual(
            snapshot.windows.first { $0.kind == .fiveHour }?.resetsAt,
            observedAt.addingTimeInterval(4 * 3_600 + 59 * 60)
        )
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.provenance.source == .officialCLI })
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.provenance.contract == .observed })
    }

    func testParserHandlesANSIQuotaAvailableAndPartialGroup() throws {
        let account = "private" + "@" + "example.invalid"
        let raw = "\u{001B}[31mAccount: \(account)\u{001B}[0m\n"
            + String(decoding: try fixture("partial"), as: UTF8.self)
        let snapshot = try GeminiQuotaParser().parse(Data(raw.utf8), observedAt: observedAt)
        XCTAssertEqual(snapshot.state, .partial)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.kind, .sharedWeekly)
        XCTAssertEqual(snapshot.windows.first?.usedRatio.value, 0)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
        XCTAssertNil(snapshot.lastAttempt?.diagnostic)
    }

    func testSafePayloadDropsAccountAndNonGeminiModelGroups() throws {
        let account = "private" + "@" + "example.invalid"
        let raw = "Account: \(account)\n"
            + String(decoding: try fixture("normal"), as: UTF8.self)
            + "\nSession: private-session-identifier"
        let safe = try XCTUnwrap(GeminiQuotaParser.geminiOnlyText(from: raw))

        XCTAssertTrue(safe.hasPrefix("GEMINI MODELS"))
        XCTAssertTrue(safe.contains("Five Hour Limit Remaining"))
        XCTAssertFalse(safe.contains(account))
        XCTAssertFalse(safe.contains("CLAUDE AND GPT MODELS"))
        XCTAssertFalse(safe.contains("private-session-identifier"))
    }

    func testParserRejectsMalformedOrMissingGeminiContract() throws {
        XCTAssertThrowsError(try GeminiQuotaParser().parse(fixture("malformed"), observedAt: observedAt)) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }
        let negative = Data("GEMINI MODELS\nWeekly Limit Remaining\n-1%\n".utf8)
        XCTAssertThrowsError(try GeminiQuotaParser().parse(negative, observedAt: observedAt)) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }
        XCTAssertThrowsError(
            try GeminiQuotaParser().parse(Data("CLAUDE AND GPT MODELS\n50%".utf8), observedAt: observedAt)
        ) {
            XCTAssertEqual($0 as? ProviderErrorCode, .unsupported)
        }
    }

    func testParserConvertsRemainingBoundaryValuesWithoutInventingReset() throws {
        let data = Data("""
        GEMINI MODELS
        Weekly Limit Remaining
        0%
        Quota available
        Five Hour Limit Remaining
        100%
        Quota available
        """.utf8)
        let snapshot = try GeminiQuotaParser().parse(data, observedAt: observedAt)

        XCTAssertEqual(snapshot.windows.first { $0.kind == .sharedWeekly }?.usedRatio.value, 1)
        XCTAssertEqual(snapshot.windows.first { $0.kind == .fiveHour }?.usedRatio.value, 0)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.resetsAt == nil })
    }

    func testExpectTerminalResponsesDoNotResetBoundedTimeout() {
        let script = GeminiCLIQuotaExecutor.expectScript
        XCTAssertEqual(script.components(separatedBy: "exp_continue -continue_timer").count - 1, 6)
        XCTAssertFalse(script.contains("; exp_continue }"))
        XCTAssertTrue(script.contains("kill -KILL"))
    }

    func testLocatorRequiresSafeExecutableSettingsAndExistingTrustedWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let home = root.appending(path: "home")
        let executable = home.appending(path: ".local/bin/agy")
        let settings = home.appending(path: ".gemini/antigravity-cli/settings.json")
        let workspace = root.appending(path: "workspace")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)
        try JSONSerialization.data(withJSONObject: ["trustedWorkspaces": [workspace.path]]).write(to: settings)
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = try GeminiCLIRuntimeLocator(homeURL: home).locate()
        XCTAssertEqual(runtime.executableURL, executable.standardizedFileURL)
        XCTAssertEqual(runtime.workspaceURL, workspace.standardizedFileURL)

        let link = home.appending(path: ".local/bin/agy-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        XCTAssertThrowsError(
            try GeminiCLIRuntimeLocator(homeURL: home, executableURL: link).locate()
        ) {
            XCTAssertEqual($0 as? GeminiCLIRuntimeError, .invalidExecutable)
        }
    }

    func testProviderCachesSuccessAndMapsFailuresWithoutRawOutput() async throws {
        let runtime = GeminiCLIRuntime(
            executableURL: URL(fileURLWithPath: "/tmp/agy"),
            workspaceURL: URL(fileURLWithPath: "/tmp"),
            homeURL: URL(fileURLWithPath: "/tmp")
        )
        let executor = RecordingGeminiExecutor(output: try fixture("normal"))
        let provider = GeminiCLIQuotaProvider(
            locator: FixedGeminiLocator(result: .success(runtime)),
            executor: executor
        )
        let first = await provider.fetchQuota()
        let second = await provider.fetchQuota()
        XCTAssertEqual(first.snapshot.state, .available)
        XCTAssertEqual(second.snapshot.state, .available)
        XCTAssertTrue(first.snapshot.windows.allSatisfy { $0.provenance.freshness == .live })
        XCTAssertTrue(second.snapshot.windows.allSatisfy { $0.provenance.freshness == .recent })
        let queryCount = await executor.queryCount()
        XCTAssertEqual(queryCount, 1)

        let missing = GeminiCLIQuotaProvider(
            locator: FixedGeminiLocator(result: .failure(.trustedWorkspaceMissing)),
            executor: executor
        )
        let missingResult = await missing.fetchQuota()
        XCTAssertEqual(missingResult.snapshot.state, .notConfigured)
        XCTAssertEqual(missingResult.snapshot.lastAttempt?.diagnostic?.code, .notFound)

        let unsupported = GeminiCLIQuotaProvider(
            locator: FixedGeminiLocator(result: .success(runtime)),
            executor: FailingGeminiExecutor(error: .unsupportedOutput)
        )
        let unsupportedResult = await unsupported.fetchQuota()
        XCTAssertEqual(unsupportedResult.snapshot.state, .unsupportedContract)
        XCTAssertFalse(unsupportedResult.snapshot.lastAttempt?.diagnostic?.summary.contains("/tmp") ?? true)

        let authRequired = GeminiCLIQuotaProvider(
            locator: FixedGeminiLocator(result: .success(runtime)),
            executor: FailingGeminiExecutor(error: .authenticationRequired)
        )
        let authRequiredResult = await authRequired.fetchQuota()
        XCTAssertEqual(authRequiredResult.snapshot.state, .authenticationRequired)

        let failed = GeminiCLIQuotaProvider(
            locator: FixedGeminiLocator(result: .success(runtime)),
            executor: FailingGeminiExecutor(error: .failed)
        )
        let failedResult = await failed.fetchQuota()
        XCTAssertEqual(failedResult.snapshot.state, .failed)
    }

    private func fixture(_ name: String) throws -> Data {
        guard let url = Bundle(for: Self.self).url(
            forResource: "gemini-\(name)",
            withExtension: "txt"
        ) else {
            throw ProviderErrorCode.notFound
        }
        return try Data(contentsOf: url)
    }
}

private struct FixedGeminiLocator: GeminiCLIRuntimeLocating {
    let result: Result<GeminiCLIRuntime, GeminiCLIRuntimeError>
    func locate() throws -> GeminiCLIRuntime { try result.get() }
}

private actor RecordingGeminiExecutor: GeminiQuotaExecuting {
    let output: Data
    private var count = 0

    init(output: Data) { self.output = output }

    func query(runtime: GeminiCLIRuntime) async throws -> Data {
        count += 1
        return output
    }

    func queryCount() -> Int { count }
}

private struct FailingGeminiExecutor: GeminiQuotaExecuting {
    let error: GeminiCLIExecutionError
    func query(runtime: GeminiCLIRuntime) async throws -> Data { throw error }
}
