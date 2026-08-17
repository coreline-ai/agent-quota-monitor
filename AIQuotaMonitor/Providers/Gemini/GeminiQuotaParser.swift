import Foundation

struct GeminiQuotaParser: Sendable {
    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot {
        let clean = Self.sanitized(String(decoding: data, as: UTF8.self))
        guard let group = Self.geminiGroup(in: clean) else {
            throw ProviderErrorCode.unsupported
        }

        let bucketDefinitions: [(label: String, kind: QuotaWindowKind)] = [
            ("Weekly Limit Remaining", .sharedWeekly),
            ("Five Hour Limit Remaining", .fiveHour),
        ]
        let parsed = bucketDefinitions.compactMap { definition in
            parseBucket(
                label: definition.label,
                kind: definition.kind,
                group: group,
                observedAt: observedAt
            )
        }
        guard !parsed.isEmpty else { throw ProviderErrorCode.malformedPayload }

        let windows = parsed.map(\.window)
        let state: ProviderState = parsed.count == bucketDefinitions.count
            && parsed.allSatisfy(\.hasCompleteResetEvidence)
            ? .available
            : .partial
        return ProviderSnapshot(
            provider: .gemini,
            state: state,
            windows: windows,
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: observedAt
        )
    }

    static func geminiOnlyText(from text: String) -> String? {
        let clean = sanitized(text)
        guard let group = geminiGroup(in: clean) else { return nil }
        return "GEMINI MODELS\n\(group)"
    }

    private func parseBucket(
        label: String,
        kind: QuotaWindowKind,
        group: String,
        observedAt: Date
    ) -> ParsedBucket? {
        guard let labelRange = group.range(of: label, options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        let suffix = group[labelRange.upperBound...]
        let nextLabels = ["Weekly Limit Remaining", "Five Hour Limit Remaining"]
            .compactMap { suffix.range(of: $0, options: .caseInsensitive)?.lowerBound }
        let end = nextLabels.min() ?? suffix.endIndex
        let section = String(suffix[..<end])

        guard let remainingPercent = Self.firstNumber(
            matching: #"(?<![0-9.+-])([0-9]{1,3}(?:[.][0-9]+)?)\s*%"#,
            in: section
        ), remainingPercent.isFinite, (0 ... 100).contains(remainingPercent),
              let usedRatio = try? QuotaRatio(1 - (remainingPercent / 100)) else {
            return nil
        }

        let resetInterval = Self.durationAfterRefresh(in: section)
        let quotaAvailable = section.range(of: "Quota available", options: .caseInsensitive) != nil
        let provenance = ValueProvenance(
            source: .officialCLI,
            contract: .observed,
            observedAt: observedAt,
            freshness: .live
        )
        return ParsedBucket(
            window: QuotaWindow(
                kind: kind,
                usedRatio: usedRatio,
                resetsAt: resetInterval.map { observedAt.addingTimeInterval($0) },
                provenance: provenance
            ),
            hasCompleteResetEvidence: resetInterval != nil || quotaAvailable
        )
    }

    private struct ParsedBucket {
        let window: QuotaWindow
        let hasCompleteResetEvidence: Bool
    }

    private static func geminiGroup(in text: String) -> String? {
        guard let start = text.range(of: "GEMINI MODELS", options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        let suffix = text[start.upperBound...]
        let end = suffix.range(of: "CLAUDE AND GPT MODELS", options: .caseInsensitive)?.lowerBound
            ?? suffix.endIndex
        return String(suffix[..<end])
    }

    private static func durationAfterRefresh(in section: String) -> TimeInterval? {
        guard let range = section.range(
            of: #"Refreshes\s+in\s+((?:[0-9]+\s*[dhm]\s*)+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        let matched = String(section[range])
        let expression = try? NSRegularExpression(pattern: #"([0-9]+)\s*([dhm])"#, options: .caseInsensitive)
        let nsRange = NSRange(matched.startIndex..., in: matched)
        var seconds: TimeInterval = 0
        expression?.enumerateMatches(in: matched, range: nsRange) { result, _, _ in
            guard let result,
                  let valueRange = Range(result.range(at: 1), in: matched),
                  let unitRange = Range(result.range(at: 2), in: matched),
                  let value = TimeInterval(matched[valueRange]) else { return }
            switch matched[unitRange].lowercased() {
            case "d": seconds += value * 86_400
            case "h": seconds += value * 3_600
            case "m": seconds += value * 60
            default: break
            }
        }
        return seconds > 0 ? seconds : nil
    }

    private static func firstNumber(matching pattern: String, in text: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    static func sanitized(_ text: String) -> String {
        let patterns = [
            "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)",
            "\u{001B}P.*?\u{001B}\\\\",
            "\u{001B}\\[[0-?]*[ -/]*[@-~]",
        ]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return String(result.unicodeScalars.filter { scalar in
            scalar.value == 0x0A || scalar.value == 0x09 || scalar.value >= 0x20
        })
    }
}
