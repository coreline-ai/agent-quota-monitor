import SwiftUI

struct ProviderMark: View {
    let provider: ProviderID
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(provider.beaconTint.opacity(0.16))
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(provider.beaconTint.opacity(0.30))
            Image(systemName: provider.beaconSymbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(provider.beaconTint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BeaconSurface<Content: View>: View {
    let selected: Bool
    let palette: BeaconPalette
    @ViewBuilder let content: Content

    init(
        selected: Bool = false,
        palette: BeaconPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.selected = selected
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? palette.selectedSurface : palette.surface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? palette.accent.opacity(0.34) : palette.border)
            }
    }
}

struct BeaconQuotaBar: View {
    let window: QuotaWindow
    let metricMode: QuotaMetricMode
    let resetStyle: QuotaResetStyle
    let palette: BeaconPalette
    var compact = false
    var showProvenance = false

    private var displayRatio: Double {
        QuotaPresentation.ratio(for: window, mode: metricMode)
    }

    private var urgency: QuotaUrgency {
        QuotaPresentation.urgency(forRemaining: window.remainingRatio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            HStack(spacing: 8) {
                Text(window.kind.label)
                    .font(compact ? .caption : .subheadline.weight(.medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(metricMode.shortLabel) \(QuotaPresentation.percentText(displayRatio))")
                    .font((compact ? Font.caption2 : Font.caption).monospacedDigit().weight(.semibold))
                    .foregroundStyle(urgencyColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.secondaryText.opacity(0.20))
                    Capsule()
                        .fill(urgencyColor)
                        .frame(width: max(0, proxy.size.width * displayRatio))
                }
            }
            .frame(height: compact ? 5 : 7)

            if !compact {
                HStack(spacing: 6) {
                    Label(urgency.label, systemImage: urgency.symbol)
                        .foregroundStyle(urgencyColor)
                    Spacer(minLength: 6)
                    Label(
                        QuotaPresentation.resetText(for: window.resetsAt, style: resetStyle),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(palette.secondaryText)
                }
                .font(.caption2)
            }

            if showProvenance {
                HStack(spacing: 8) {
                    Text("\(window.provenance.contract.rawValue) · \(window.provenance.source.rawValue)")
                    Spacer(minLength: 4)
                    Text("\(window.provenance.freshness.label) · \(window.provenance.observedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(window.kind.label), \(metricMode.label) \(QuotaPresentation.percentText(displayRatio)), \(urgency.label), \(QuotaPresentation.resetText(for: window.resetsAt, style: resetStyle))"
        )
    }

    private var urgencyColor: Color {
        switch urgency {
        case .healthy: AppTheme.cyan
        case .warning: AppTheme.warning
        case .critical: AppTheme.danger
        }
    }
}

struct BeaconLegend: View {
    let palette: BeaconPalette

    var body: some View {
        HStack(spacing: 14) {
            legendItem("여유", color: AppTheme.cyan)
            legendItem("주의", color: AppTheme.warning)
            legendItem("위험", color: AppTheme.danger)
        }
        .font(.caption)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 18, height: 5)
            Text(title).foregroundStyle(palette.secondaryText)
        }
    }
}
