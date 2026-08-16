import SwiftUI

struct LimitsView: View {
    let snapshots: [ProviderSnapshot]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("한도 원장").font(.largeTitle.bold()).accessibilityIdentifier("dashboard.limits.title")
                Text("모든 값은 계약 등급, 출처, 관측 시각과 함께 표시됩니다.")
                    .foregroundStyle(.secondary)
                ForEach(snapshots) { snapshot in
                    SignalPanel(title: snapshot.provider.displayName) {
                        HStack { ProviderStateBadge(state: snapshot.state); Spacer() }
                        if snapshot.windows.isEmpty {
                            ContentUnavailableView(
                                "확정된 quota 없음",
                                systemImage: "gauge.with.dots.needle.0percent",
                                description: Text("연결되지 않았거나 안전한 machine contract가 없습니다.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 110)
                        } else {
                            ForEach(snapshot.windows) { window in
                                LimitLedgerRow(window: window)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .accessibilityIdentifier("dashboard.limits")
    }
}

private struct LimitLedgerRow: View {
    let window: QuotaWindow

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text(window.kind.label).font(.headline)
                Text("남음 \(window.remainingRatio, format: .percent.precision(.fractionLength(0)))")
                    .font(.headline.monospacedDigit())
                Text(window.provenance.freshness.label).foregroundStyle(window.provenance.freshness == .stale ? AppTheme.warning : .secondary)
            }
            GridRow {
                Text(window.provenance.contract.rawValue).font(.caption)
                Text(window.provenance.source.rawValue).font(.caption)
                Text(window.resetsAt?.formatted() ?? "리셋 미확인").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
