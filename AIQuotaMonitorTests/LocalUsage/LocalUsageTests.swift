import XCTest
@testable import AIQuotaMonitor

final class LocalUsageTests: XCTestCase {
    func testJSONLParserSkipsCorruptionAndDeduplicates() {
        let data = Data("""
        {"event_id":"a","provider":"codex","timestamp":"2026-08-16T00:00:00Z","model":"gpt-5.2","project_label":"/Users/alice/private","input_tokens":100,"output_tokens":20,"cache_read_tokens":30,"cache_write_tokens":0}
        not-json
        {"event_id":"a","provider":"codex","timestamp":"2026-08-16T00:00:00Z","model":"gpt-5.2","project_label":null,"input_tokens":999,"output_tokens":0,"cache_read_tokens":0,"cache_write_tokens":0}
        {"event_id":"b","provider":"claude","timestamp":"2026-08-16T00:00:00Z","model":"claude-sonnet-5","project_label":null,"input_tokens":1,"output_tokens":1,"cache_read_tokens":0,"cache_write_tokens":0}
        """.utf8)
        let values = JSONLUsageParser().parse(data, expectedProvider: .codex)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].tokens, TokenBreakdown(input: 100, output: 20, cacheRead: 30, cacheWrite: 0))
        XCTAssertFalse(values[0].projectLabel?.contains("alice") ?? true)
    }

    func testPricingEstimateAndUnknownModel() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AIQuotaMonitor/Resources/PricingCatalog.json")
        let catalog = try JSONDecoder().decode(PricingCatalog.self, from: Data(contentsOf: catalogURL))
        let sample = LocalUsageSample(
            id: "one",
            provider: .codex,
            occurredAt: Date(),
            model: "gpt-5.2",
            projectLabel: nil,
            tokens: TokenBreakdown(input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        )
        XCTAssertEqual(catalog.estimate(for: sample)?.amount, Decimal(string: "15.75"))
        let unknown = LocalUsageSample(
            id: "two", provider: .codex, occurredAt: Date(), model: "unknown",
            projectLabel: nil, tokens: .zero
        )
        XCTAssertNil(catalog.estimate(for: unknown))
    }

    func testDailyAggregationSeparatesProviderAndProject() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-16T10:00:00Z"))
        let samples = [
            LocalUsageSample(
                id: "1", provider: .codex, occurredAt: date, model: "gpt-5.2", projectLabel: "A",
                tokens: TokenBreakdown(input: 10, output: 2, cacheRead: 1, cacheWrite: 0)
            ),
            LocalUsageSample(
                id: "2", provider: .codex, occurredAt: date.addingTimeInterval(60), model: "gpt-5.2", projectLabel: "A",
                tokens: TokenBreakdown(input: 5, output: 3, cacheRead: 0, cacheWrite: 1)
            ),
            LocalUsageSample(
                id: "3", provider: .claude, occurredAt: date, model: "claude-sonnet-5", projectLabel: "A",
                tokens: TokenBreakdown(input: 7, output: 1, cacheRead: 0, cacheWrite: 0)
            )
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let buckets = LocalUsageAggregator.daily(samples, calendar: calendar)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets.first { $0.provider == .codex }?.tokens.total, 22)
        XCTAssertEqual(buckets.first { $0.provider == .claude }?.tokens.total, 8)
    }
}
