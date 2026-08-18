import SwiftUI

struct OverviewProviderCard: View {
    let snapshot: ProviderSnapshot
    let metricMode: QuotaMetricMode
    let resetStyle: QuotaResetStyle
    let palette: BeaconPalette

    var body: some View {
        BeaconSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    ProviderMark(provider: snapshot.provider, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.provider.beaconShortName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(snapshot.provider.displayName)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    ProviderStateBadge(state: snapshot.state)
                }

                if snapshot.windows.isEmpty {
                    Label("quota window 없음", systemImage: "minus.circle")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("overview.provider.\(snapshot.provider.rawValue).empty")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { index, window in
                            OverviewQuotaLine(
                                window: window,
                                metricMode: metricMode,
                                resetStyle: resetStyle,
                                palette: palette
                            )
                            .accessibilityIdentifier(
                                "overview.provider.\(snapshot.provider.rawValue).window.\(index)"
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("overview.provider.\(snapshot.provider.rawValue)")
    }
}

private struct OverviewQuotaLine: View {
    let window: QuotaWindow
    let metricMode: QuotaMetricMode
    let resetStyle: QuotaResetStyle
    let palette: BeaconPalette

    private var displayRatio: Double {
        QuotaPresentation.ratio(for: window, mode: metricMode)
    }

    private var urgency: QuotaUrgency {
        QuotaPresentation.urgency(forRemaining: window.remainingRatio)
    }

    private var urgencyColor: Color {
        switch urgency {
        case .healthy: AppTheme.cyan
        case .warning: AppTheme.warning
        case .critical: AppTheme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(window.kind.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(metricMode.shortLabel) \(QuotaPresentation.percentText(displayRatio))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(urgencyColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.secondaryText.opacity(0.18))
                    Capsule()
                        .fill(urgencyColor)
                        .frame(width: max(0, proxy.size.width * displayRatio))
                }
            }
            .frame(height: 3)

            HStack(spacing: 4) {
                Text(window.provenance.freshness.label)
                    .foregroundStyle(window.provenance.freshness == .live ? palette.accent : palette.secondaryText)
                Spacer(minLength: 4)
                Text(QuotaPresentation.resetText(for: window.resetsAt, style: resetStyle))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(window.kind.label), \(metricMode.label) \(QuotaPresentation.percentText(displayRatio)), " +
                "\(window.provenance.freshness.label), " +
                "\(QuotaPresentation.resetText(for: window.resetsAt, style: resetStyle))"
        )
    }
}
