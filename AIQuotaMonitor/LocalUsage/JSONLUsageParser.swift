import Foundation

struct JSONLUsageParser: Sendable {
    func parse(_ data: Data, expectedProvider: ProviderID) -> [LocalUsageSample] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let payload = try? decoder.decode(Line.self, from: Data(line.utf8)),
                  payload.provider == expectedProvider.rawValue,
                  payload.inputTokens >= 0,
                  payload.outputTokens >= 0,
                  payload.cacheReadTokens >= 0,
                  payload.cacheWriteTokens >= 0,
                  seen.insert(payload.eventID).inserted else { return nil }
            return LocalUsageSample(
                id: payload.eventID,
                provider: expectedProvider,
                occurredAt: payload.timestamp,
                model: payload.model,
                projectLabel: payload.projectLabel.map(Redactor.redact),
                tokens: TokenBreakdown(
                    input: payload.inputTokens,
                    output: payload.outputTokens,
                    cacheRead: payload.cacheReadTokens,
                    cacheWrite: payload.cacheWriteTokens
                )
            )
        }
    }

    private struct Line: Decodable {
        let eventID: String
        let provider: String
        let timestamp: Date
        let model: String
        let projectLabel: String?
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
            case provider
            case timestamp
            case model
            case projectLabel = "project_label"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadTokens = "cache_read_tokens"
            case cacheWriteTokens = "cache_write_tokens"
        }
    }
}

struct JSONLLocalUsageSource: LocalUsageSource {
    let provider: ProviderID
    let fileURLs: [URL]
    private let parser = JSONLUsageParser()

    func loadUsage(in interval: DateInterval) async throws -> [LocalUsageSample] {
        var values: [String: LocalUsageSample] = [:]
        for url in fileURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            for sample in parser.parse(data, expectedProvider: provider)
            where interval.contains(sample.occurredAt) {
                values[sample.id] = sample
            }
        }
        return values.values.sorted { $0.occurredAt < $1.occurredAt }
    }
}

struct UnsupportedLocalUsageSource: LocalUsageSource {
    let provider: ProviderID
    func loadUsage(in interval: DateInterval) async throws -> [LocalUsageSample] {
        throw ProviderErrorCode.unsupported
    }
}
