import Darwin
import XCTest
@testable import AIQuotaMonitor

final class ProviderParserTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_786_860_000)

    func testClaudeNormalAndPartialWindows() throws {
        let normal = try ClaudeQuotaParser().parse(fixture("Claude", "normal"), observedAt: observedAt)
        XCTAssertEqual(normal.state, .available)
        XCTAssertEqual(normal.windows.count, 2)
        XCTAssertEqual(normal.windows[0].usedRatio.value, 0.37, accuracy: 0.0001)

        let partial = try ClaudeQuotaParser().parse(fixture("Claude", "partial"), observedAt: observedAt)
        XCTAssertEqual(partial.state, .partial)
        XCTAssertEqual(partial.windows.count, 1)
    }

    func testCodexNormalPreservesCreditsAndMissingReset() throws {
        let normal = try CodexQuotaParser().parse(fixture("Codex", "normal"), observedAt: observedAt)
        XCTAssertEqual(normal.state, .available)
        XCTAssertEqual(normal.windows.count, 2)
        XCTAssertEqual(normal.credits?.amount, Decimal(string: "15.0"))

        let partial = try CodexQuotaParser().parse(fixture("Codex", "partial"), observedAt: observedAt)
        XCTAssertEqual(partial.state, .partial)
        XCTAssertNil(partial.windows.first?.resetsAt)
    }

    func testGrokAndZAIOfficialObservedParsers() throws {
        let grok = try GrokQuotaParser().parse(fixture("Grok", "normal"), observedAt: observedAt)
        XCTAssertEqual(grok.state, .available)
        XCTAssertEqual(grok.windows.first?.kind, .sharedWeekly)
        XCTAssertEqual(grok.windows.first?.usedRatio.value ?? -1, 0.41, accuracy: 0.0001)
        XCTAssertEqual(grok.credits?.amount, Decimal(string: "12.00"))
        XCTAssertEqual(grok.windows.first?.provenance.contract, .observed)

        let grokPartial = try GrokQuotaParser().parse(fixture("Grok", "partial"), observedAt: observedAt)
        XCTAssertEqual(grokPartial.state, .partial)
        XCTAssertNil(grokPartial.windows.first?.resetsAt)

        let zai = try ZAIQuotaParser().parse(fixture("ZAI", "normal"), observedAt: observedAt)
        XCTAssertEqual(zai.state, .available)
        XCTAssertEqual(zai.windows.count, 2)
        XCTAssertEqual(zai.windows.first { $0.kind == .fiveHour }?.usedRatio.value ?? -1, 0.28, accuracy: 0.0001)
        XCTAssertEqual(zai.windows.first { $0.kind == .custom("MCP 월간") }?.usedRatio.value ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertTrue(zai.windows.allSatisfy { $0.resetsAt == nil })
        XCTAssertTrue(zai.windows.allSatisfy { $0.provenance.source == .officialCLI })
        XCTAssertTrue(zai.windows.allSatisfy { $0.provenance.contract == .observed })

        let zaiPartial = try ZAIQuotaParser().parse(fixture("ZAI", "partial"), observedAt: observedAt)
        XCTAssertEqual(zaiPartial.state, .partial)
        XCTAssertEqual(zaiPartial.windows.first?.usedRatio.value, 0)
    }

    func testGrokLegacyBillingFallbackAndInvalidPercent() throws {
        let legacy = Data(#"{"config":{"monthlyLimit":{"val":10000},"used":{"val":2500},"billingPeriodEnd":"2026-09-01T00:00:00Z"}}"#.utf8)
        let snapshot = try GrokQuotaParser().parse(legacy, observedAt: observedAt)
        XCTAssertEqual(snapshot.state, .available)
        XCTAssertEqual(snapshot.windows.first?.usedRatio.value ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows.first?.kind, .custom("공용 크레딧"))

        let invalid = Data(#"{"config":{"creditUsagePercent":101}}"#.utf8)
        XCTAssertThrowsError(try GrokQuotaParser().parse(invalid, observedAt: observedAt)) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }

        let missingBalanceValue = Data(#"{"config":{"creditUsagePercent":0,"prepaidBalance":{}}}"#.utf8)
        let zeroUsage = try GrokQuotaParser().parse(missingBalanceValue, observedAt: observedAt)
        XCTAssertEqual(zeroUsage.windows.first?.usedRatio.value, 0)
        XCTAssertNil(zeroUsage.credits)

        let negativeBalance = Data(#"{"config":{"creditUsagePercent":100,"prepaidBalance":{"val":-1}}}"#.utf8)
        XCTAssertThrowsError(try GrokQuotaParser().parse(negativeBalance, observedAt: observedAt)) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }

        let fullyUsed = Data(#"{"config":{"creditUsagePercent":100,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-01T00:00:00Z"}}}"#.utf8)
        let fullyUsedSnapshot = try GrokQuotaParser().parse(fullyUsed, observedAt: observedAt)
        XCTAssertEqual(fullyUsedSnapshot.windows.first?.usedRatio.value, 1)
        XCTAssertEqual(fullyUsedSnapshot.windows.first?.remainingRatio, 0)

        let fiveHourLike = Data(#"{"config":{"creditUsagePercent":10,"currentPeriod":{"type":"FIVE_HOUR","end":"2026-09-01T00:00:00Z"}}}"#.utf8)
        let unknownPeriod = try GrokQuotaParser().parse(fiveHourLike, observedAt: observedAt)
        XCTAssertEqual(unknownPeriod.windows.first?.kind, .custom("공용 크레딧"))
        XCTAssertNotEqual(unknownPeriod.windows.first?.kind, .fiveHour)
    }

    func testMalformedFixturesFailTyped() {
        XCTAssertThrowsError(try ClaudeQuotaParser().parse(fixture("Claude", "malformed"), observedAt: observedAt)) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }
        XCTAssertThrowsError(try CodexQuotaParser().parse(fixture("Codex", "malformed"), observedAt: observedAt))
        XCTAssertThrowsError(try GrokQuotaParser().parse(fixture("Grok", "malformed"), observedAt: observedAt))
        XCTAssertThrowsError(try ZAIQuotaParser().parse(fixture("ZAI", "malformed"), observedAt: observedAt))
    }

    func testClaudeSnapshotProviderDoesNotModifyReadOnlyInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshotURL = directory.appending(path: "claude.json")
        let original = try fixture("Claude", "normal")
        try original.write(to: snapshotURL)
        XCTAssertEqual(chmod(snapshotURL.path, 0o600), 0)
        let before = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        let provider = ClaudeStatusSnapshotProvider(
            snapshotURL: snapshotURL,
            validator: CredentialFileValidator(allowedRoots: [directory])
        )
        let result = await provider.fetchQuota()
        let after = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        XCTAssertEqual(result.snapshot.state, .available)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), original)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        try? FileManager.default.removeItem(at: directory)
    }

    func testClaudeSnapshotProviderWaitsForFirstBridgeEvent() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appending(path: "pending.json")
        let provider = ClaudeStatusSnapshotProvider(
            snapshotURL: snapshotURL,
            validator: CredentialFileValidator(allowedRoots: [directory])
        )

        let result = await provider.fetchQuota()
        XCTAssertEqual(result.snapshot.state, .notConfigured)
        XCTAssertNil(result.snapshot.lastAttempt)
    }

    func testCodexAdapterSendsOnlyReadOnlyMethods() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputURL = directory.appending(path: "requests.txt")
        let scriptURL = directory.appending(path: "fake-codex")
        let script = """
        #!/bin/sh
        IFS= read -r first
        IFS= read -r second
        printf '%s\\n%s\\n' "$first" "$second" > '\(inputURL.path)'
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"resetsAt":1786878000,"windowDurationMins":300}}}}'
        sleep 30
        """
        try Data(script.utf8).write(to: scriptURL)
        XCTAssertEqual(chmod(scriptURL.path, 0o700), 0)
        let result = await CodexAppServerProvider(executableURL: scriptURL).fetchQuota()
        let requests = try String(contentsOf: inputURL, encoding: .utf8)
        let methods = requests.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return nil
            }
            return object["method"] as? String
        }
        XCTAssertEqual(result.snapshot.state, .partial)
        XCTAssertEqual(methods, ["initialize", "account/rateLimits/read"])
        try? FileManager.default.removeItem(at: directory)
    }

    func testCodexAdapterFindsSiblingRuntimeWhenGUIPathOmitsIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appending(path: "codex")
        let runtimeURL = directory.appending(path: "quotabeacon-test-runtime")

        try Data("#!/usr/bin/env quotabeacon-test-runtime\n".utf8).write(to: executableURL)
        try Data("""
        #!/bin/sh
        IFS= read -r first
        IFS= read -r second
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"resetsAt":1786878000,"windowDurationMins":300}}}}'
        sleep 30
        """.utf8).write(to: runtimeURL)
        XCTAssertEqual(chmod(executableURL.path, 0o700), 0)
        XCTAssertEqual(chmod(runtimeURL.path, 0o700), 0)

        let result = await CodexAppServerProvider(executableURL: executableURL).fetchQuota()

        XCTAssertEqual(result.snapshot.state, .partial)
        XCTAssertEqual(result.snapshot.windows.first?.usedRatio.value ?? -1, 0.12, accuracy: 0.0001)
        try? FileManager.default.removeItem(at: directory)
    }

    func testCodexAutoProviderFallsBackToNextResolvedRuntime() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appending(path: "first-codex")
        try Data("""
        #!/bin/sh
        IFS= read -r first
        IFS= read -r second
        printf '%s\\n' '{"id":2,"error":{"code":401,"message":"expired"}}'
        sleep 30
        """.utf8).write(to: first)
        XCTAssertEqual(chmod(first.path, 0o700), 0)

        let second = directory.appending(path: "second-codex")
        try Data("""
        #!/bin/sh
        IFS= read -r first
        IFS= read -r second
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":18,"resetsAt":1786878000,"windowDurationMins":300}}}}'
        sleep 30
        """.utf8).write(to: second)
        XCTAssertEqual(chmod(second.path, 0o700), 0)

        let provider = CodexAutoProvider(runtimes: [
            CodexRuntime(executableURL: first, runtimeURL: nil, source: .explicit),
            CodexRuntime(executableURL: second, runtimeURL: nil, source: .applicationBundle)
        ])

        let result = await provider.fetchQuota()

        XCTAssertEqual(result.snapshot.state, .partial)
        XCTAssertEqual(result.snapshot.windows.first?.usedRatio.value ?? -1, 0.18, accuracy: 0.0001)
    }

    private func fixture(_ provider: String, _ name: String) throws -> Data {
        let resource = "\(provider.lowercased())-\(name)"
        guard let url = Bundle(for: Self.self).url(forResource: resource, withExtension: "json") else {
            throw ProviderErrorCode.notFound
        }
        return try Data(contentsOf: url)
    }
}
