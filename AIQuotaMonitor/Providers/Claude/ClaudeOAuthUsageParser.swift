import Foundation
import CoreFoundation

struct ClaudeOAuthUsageParser: QuotaPayloadParser {
    let provider = ProviderID.claude

    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderErrorCode.malformedPayload
        }
        let provenance = ValueProvenance(
            source: .keychain,
            contract: .observed,
            observedAt: observedAt,
            freshness: .live
        )
        var windows: [QuotaWindow] = []
        if let window = try makeWindow(.fiveHour, value: root["five_hour"], provenance: provenance) {
            windows.append(window)
        }
        if let window = try makeWindow(.sevenDay, value: root["seven_day"], provenance: provenance) {
            windows.append(window)
        }
        if let window = try makeFableWindow(root: root, provenance: provenance) {
            windows.append(window)
        }
        guard !windows.isEmpty else { throw ProviderErrorCode.malformedPayload }

        let baseKinds = Set(windows.map(\.kind)).intersection([.fiveHour, .sevenDay])
        return ProviderSnapshot(
            provider: provider,
            state: baseKinds.count == 2 ? .available : .partial,
            windows: windows,
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: observedAt
        )
    }

    private func makeWindow(
        _ kind: QuotaWindowKind,
        value: Any?,
        provenance: ValueProvenance
    ) throws -> QuotaWindow? {
        guard let raw = value as? [String: Any] else { return nil }
        let percent = number(raw["utilization"]) ?? number(raw["used_percentage"])
        guard let percent else { return nil }
        return try QuotaWindow(
            kind: kind,
            usedRatio: QuotaRatio(percent: percent),
            resetsAt: resetDate(raw["resets_at"]),
            provenance: provenance
        )
    }

    private func makeFableWindow(
        root: [String: Any],
        provenance: ValueProvenance
    ) throws -> QuotaWindow? {
        if let limits = root["limits"] as? [[String: Any]],
           let limit = limits.first(where: isFableWeeklyLimit),
           let percent = number(limit["percent"]) {
            return try QuotaWindow(
                kind: .custom("Fable 주간"),
                usedRatio: QuotaRatio(percent: percent),
                resetsAt: resetDate(limit["resets_at"]),
                provenance: provenance
            )
        }
        for key in ["fable_weekly", "fable_seven_day", "seven_day_fable"] {
            if let value = root[key],
               let window = try makeWindow(.custom("Fable 주간"), value: value, provenance: provenance) {
                return window
            }
        }
        return nil
    }

    private func isFableWeeklyLimit(_ value: [String: Any]) -> Bool {
        guard value["kind"] as? String == "weekly_scoped",
              let scope = value["scope"] as? [String: Any],
              let model = scope["model"] as? [String: Any],
              let name = model["display_name"] as? String else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Fable") == .orderedSame
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            // `JSONSerialization` bridges the numeric JSON values 0 and 1 to
            // `Bool` under Swift's `is Bool` check. CFBoolean has a distinct
            // runtime type ID, so reject only real JSON booleans and preserve
            // valid 0% / 1% quota observations.
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private func resetDate(_ value: Any?) -> Date? {
        if let number = number(value) {
            let seconds = number > 10_000_000_000 ? number / 1_000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String, !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
