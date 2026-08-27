import XCTest
@testable import AIQuotaMonitor

final class ZAIPluginUsageProviderTests: XCTestCase {
    func testClaudeGLMAliasParserSelectsOnlyRequiredEnvironment() throws {
        let contents = """
        export UNRELATED=ignored
        alias claude-glm='ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" ANTHROPIC_AUTH_TOKEN="test-token" API_TIMEOUT_MS=300000 OTHER_SECRET=ignored claude --dangerously-skip-permissions'
        """
        let profile = try ZAIClaudeProfileReader.parse(contents)
        XCTAssertEqual(profile.baseURL, "https://api.z.ai/api/anthropic")
        XCTAssertEqual(profile.authToken, "test-token")

        XCTAssertThrowsError(try ZAIClaudeProfileReader.parse(
            "alias claude-glm='ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic claude'"
        )) {
            XCTAssertEqual($0 as? ZAIProfileError, .malformedProfile)
        }
        XCTAssertThrowsError(try ZAIClaudeProfileReader.parse(
            "alias claude-glm='ANTHROPIC_BASE_URL=https://example.com ANTHROPIC_AUTH_TOKEN=value claude'"
        )) {
            XCTAssertEqual($0 as? ZAIProfileError, .unsupportedBaseURL)
        }
        XCTAssertThrowsError(try ZAIClaudeProfileReader.parse(
            "alias claude-glm='ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic ANTHROPIC_AUTH_TOKEN=value curl'"
        )) {
            XCTAssertEqual($0 as? ZAIProfileError, .malformedProfile)
        }
    }

    func testOutputExtractorReturnsOnlyQuotaSection() throws {
        let console = Data("""
        Platform: ZAI

        Model usage data:

        {"models":[{"name":"synthetic-model","usage":10}]}

        Tool usage data:

        {"tools":[{"name":"synthetic-tool","usage":3}]}

        Quota limit data:

        {"limits":[{"type":"Token usage(5 Hour)","percentage":1},{"type":"MCP usage(1 Month)","percentage":0}]}

        """.utf8)
        let quota = try ZAIPluginOutputExtractor.extractQuota(from: console)
        let text = String(decoding: quota, as: UTF8.self)
        XCTAssertTrue(text.contains("Token usage(5 Hour)"))
        XCTAssertFalse(text.contains("synthetic-model"))
        XCTAssertFalse(text.contains("synthetic-tool"))

        XCTAssertThrowsError(try ZAIPluginOutputExtractor.extractQuota(from: Data("Platform: ZHIPU".utf8))) {
            XCTAssertEqual($0 as? ProviderErrorCode, .unsupported)
        }
    }

    func testProviderQueriesExactlyOnceAndCachesSuccess() async {
        let executor = ZAIRecordingExecutor(data: quotaData)
        let provider = ZAIPluginUsageProvider(
            profileReader: ZAIFixtureProfileReader(),
            pluginLocator: ZAIFixturePluginLocator(),
            executor: executor
        )

        let first = await provider.fetchQuota()
        let second = await provider.fetchQuota()
        XCTAssertEqual(first.snapshot.state, .available)
        XCTAssertEqual(first.snapshot.windows.count, 2)
        XCTAssertEqual(second.snapshot.state, .available)
        XCTAssertTrue(first.snapshot.windows.allSatisfy { $0.provenance.freshness == .live })
        XCTAssertTrue(second.snapshot.windows.allSatisfy { $0.provenance.freshness == .recent })
        let count = await executor.queryCount()
        XCTAssertEqual(count, 1)
    }

    func testProviderMapsMissingProfileAndPluginFailure() async {
        let missing = await ZAIPluginUsageProvider(
            profileReader: ZAIFailingProfileReader(),
            pluginLocator: ZAIFixturePluginLocator(),
            executor: ZAIRecordingExecutor(data: quotaData)
        ).fetchQuota()
        XCTAssertEqual(missing.snapshot.state, .notConfigured)
        XCTAssertEqual(missing.snapshot.lastAttempt?.diagnostic?.code, .missingCredential)

        let pluginMissing = await ZAIPluginUsageProvider(
            profileReader: ZAIFixtureProfileReader(),
            pluginLocator: ZAIFailingPluginLocator(),
            executor: ZAIRecordingExecutor(data: quotaData)
        ).fetchQuota()
        XCTAssertEqual(pluginMissing.snapshot.state, .unsupportedContract)
        XCTAssertEqual(pluginMissing.snapshot.lastAttempt?.diagnostic?.code, .unsupported)
    }

    private var quotaData: Data {
        Data(#"{"limits":[{"type":"Token usage(5 Hour)","percentage":1},{"type":"MCP usage(1 Month)","percentage":0}]}"#.utf8)
    }
}

private struct ZAIFixtureProfileReader: ZAIProfileReading {
    func read() throws -> ZAIClaudeProfile {
        ZAIClaudeProfile(baseURL: "https://api.z.ai/api/anthropic", authToken: "test-token")
    }
}

private struct ZAIFailingProfileReader: ZAIProfileReading {
    func read() throws -> ZAIClaudeProfile { throw ZAIProfileError.profileMissing }
}

private struct ZAIFixturePluginLocator: ZAIPluginLocating {
    func locate() throws -> ZAIPluginRuntime {
        ZAIPluginRuntime(
            nodeURL: URL(fileURLWithPath: "/usr/bin/false"),
            scriptURL: URL(fileURLWithPath: "/tmp/query-usage.mjs"),
            version: "0.0.1"
        )
    }
}

private struct ZAIFailingPluginLocator: ZAIPluginLocating {
    func locate() throws -> ZAIPluginRuntime { throw ZAIPluginLocatorError.pluginMissing }
}

private actor ZAIRecordingExecutor: ZAIUsageExecuting {
    let data: Data
    private var count = 0

    init(data: Data) { self.data = data }

    func query(runtime: ZAIPluginRuntime, profile: ZAIClaudeProfile) async throws -> Data {
        count += 1
        return data
    }

    func queryCount() -> Int { count }
}
