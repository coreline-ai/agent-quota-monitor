import SwiftUI

enum QuotaDensity: String, CaseIterable, Identifiable {
    case balanced
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: "균형"
        case .compact: "압축"
        }
    }
}

enum QuotaMetricMode: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }

    var label: String {
        switch self {
        case .remaining: "잔여량"
        case .used: "사용량"
        }
    }

    var shortLabel: String {
        switch self {
        case .remaining: "남음"
        case .used: "사용"
        }
    }
}

enum QuotaResetStyle: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relative: "남은 시간"
        case .absolute: "시각"
        }
    }
}

enum QuotaVisualTheme: String, CaseIterable, Identifiable {
    case system
    case midnight
    case graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "시스템"
        case .midnight: "미드나이트"
        case .graphite: "그래파이트"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .midnight, .graphite: .dark
        }
    }
}

enum QuotaInspectorMode: String, CaseIterable, Identifiable {
    case expanded
    case summary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expanded: "상세 펼침"
        case .summary: "요약만"
        }
    }
}

enum QuotaPreferenceKey {
    static let density = "appearance.density"
    static let metricMode = "appearance.metricMode"
    static let resetStyle = "appearance.resetStyle"
    static let theme = "appearance.theme"
    static let inspectorMode = "appearance.inspectorMode"

    static func providerVisible(_ provider: ProviderID) -> String {
        "appearance.provider.\(provider.rawValue).visible"
    }
}

enum QuotaUrgency: Equatable {
    case healthy
    case warning
    case critical

    var label: String {
        switch self {
        case .healthy: "여유"
        case .warning: "주의"
        case .critical: "위험"
        }
    }

    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }
}

enum QuotaPresentation {
    static func ratio(for window: QuotaWindow, mode: QuotaMetricMode) -> Double {
        switch mode {
        case .remaining: window.remainingRatio
        case .used: window.usedRatio.value
        }
    }

    static func urgency(forRemaining remaining: Double) -> QuotaUrgency {
        if remaining <= 0.10 { return .critical }
        if remaining <= 0.25 { return .warning }
        return .healthy
    }

    static func percentText(_ ratio: Double) -> String {
        "\(Int((min(max(ratio, 0), 1) * 100).rounded()))%"
    }

    static func resetText(
        for date: Date?,
        style: QuotaResetStyle,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "리셋 미확인" }

        switch style {
        case .relative:
            let seconds = date.timeIntervalSince(now)
            guard seconds > 0 else { return "리셋 확인 필요" }
            let totalMinutes = max(1, Int(seconds / 60))
            let days = totalMinutes / 1_440
            let hours = (totalMinutes % 1_440) / 60
            let minutes = totalMinutes % 60
            if days > 0 { return hours > 0 ? "\(days)일 \(hours)시간 후" : "\(days)일 후" }
            if hours > 0 { return minutes > 0 ? "\(hours)시간 \(minutes)분 후" : "\(hours)시간 후" }
            return totalMinutes == 1 ? "1분 이내" : "\(totalMinutes)분 후"
        case .absolute:
            let format: Date.FormatStyle = calendar.isDateInToday(date)
                ? .dateTime.hour().minute()
                : .dateTime.month(.abbreviated).day().hour().minute()
            return date.formatted(format)
        }
    }
}

struct BeaconPalette {
    let canvas: Color
    let surface: Color
    let elevatedSurface: Color
    let selectedSurface: Color
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color

    static func resolve(theme: QuotaVisualTheme, colorScheme: ColorScheme) -> BeaconPalette {
        switch theme {
        case .system:
            BeaconPalette(
                canvas: Color(nsColor: .windowBackgroundColor),
                surface: Color(nsColor: .controlBackgroundColor),
                elevatedSurface: Color(nsColor: .underPageBackgroundColor),
                selectedSurface: AppTheme.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.11),
                border: Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.08),
                primaryText: .primary,
                secondaryText: .secondary,
                accent: AppTheme.accentColor
            )
        case .midnight:
            BeaconPalette(
                canvas: Color(red: 0.059, green: 0.067, blue: 0.086),
                surface: Color(red: 0.098, green: 0.110, blue: 0.137),
                elevatedSurface: Color(red: 0.125, green: 0.141, blue: 0.176),
                selectedSurface: Color(red: 0.141, green: 0.165, blue: 0.220),
                border: Color.white.opacity(0.11),
                primaryText: Color(red: 0.955, green: 0.965, blue: 0.990),
                secondaryText: Color(red: 0.659, green: 0.686, blue: 0.745),
                accent: Color(red: 0.392, green: 0.486, blue: 1.000)
            )
        case .graphite:
            BeaconPalette(
                canvas: Color(red: 0.094, green: 0.098, blue: 0.106),
                surface: Color(red: 0.145, green: 0.153, blue: 0.165),
                elevatedSurface: Color(red: 0.180, green: 0.188, blue: 0.204),
                selectedSurface: Color(red: 0.220, green: 0.231, blue: 0.255),
                border: Color.white.opacity(0.12),
                primaryText: Color(red: 0.955, green: 0.955, blue: 0.965),
                secondaryText: Color(red: 0.670, green: 0.680, blue: 0.700),
                accent: Color(red: 0.510, green: 0.620, blue: 0.980)
            )
        }
    }
}

extension ProviderID {
    var beaconSymbol: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal.fill"
        case .grok: "scope"
        case .zai: "waveform.path.ecg"
        }
    }

    var beaconShortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .zai: "GLM"
        }
    }

    var beaconTint: Color {
        switch self {
        case .claude: Color(red: 0.93, green: 0.47, blue: 0.28)
        case .codex: Color(red: 0.35, green: 0.53, blue: 0.96)
        case .grok: Color(red: 0.68, green: 0.58, blue: 0.94)
        case .zai: Color(red: 0.20, green: 0.74, blue: 0.72)
        }
    }
}
