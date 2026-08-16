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

    func testExperimentalParsersPreserveUnknownWithoutClaimingAvailability() throws {
        let grok = try GrokQuotaParser().parse(fixture("Grok", "normal"), observedAt: observedAt)
        XCTAssertEqual(grok.state, .unsupportedContract)
        XCTAssertEqual(grok.windows.first?.kind, .sharedWeekly)

        let zai = try ZAIQuotaParser().parse(fixture("ZAI", "normal"), observedAt: observedAt)
        XCTAssertEqual(zai.state, .unsupportedContract)
        XCTAssertTrue(zai.windows.contains { $0.kind == .custom("future_window") })
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

    func testCodexAdapterSendsOnlyReadOnlyMethods() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputURL = directory.appending(path: "requests.txt")
        let scriptURL = directory.appending(path: "fake-codex")
        let script = """
        #!/bin/sh
        cat > '\(inputURL.path)'
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"resetsAt":1786878000,"windowDurationMins":300}}}}'
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

    private func fixture(_ provider: String, _ name: String) throws -> Data {
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = testsRoot.appending(path: "Fixtures/\(provider)/\(provider.lowercased())-\(name).json")
        return try Data(contentsOf: url)
    }
}
