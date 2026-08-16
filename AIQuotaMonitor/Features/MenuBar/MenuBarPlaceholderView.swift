import SwiftUI

struct MenuBarPlaceholderView: View {
    @ObservedObject var model: QuotaMonitorModel
    let onShowDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(model.snapshots) { snapshot in
                        ProviderCompactRow(snapshot: snapshot)
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("menu.refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
                .accessibilityIdentifier("menu.refresh")
                Spacer()
                Button("menu.openDashboard", action: onShowDashboard)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentColor)
                    .accessibilityIdentifier("menu.openDashboard")
            }
        }
        .padding(16)
        .frame(width: 390, height: 520, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.accentColor.gradient)
                Image(systemName: AppTheme.statusItemSymbolName)
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("menu.title").font(.headline)
                Text(model.lastRefreshAt.map { "업데이트 \($0.formatted(date: .omitted, time: .shortened))" } ?? "로컬 전용 · 연결 대기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
        }
    }
}

struct ProviderCompactRow: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.provider.displayName).font(.subheadline.weight(.semibold))
                Spacer()
                ProviderStateBadge(state: snapshot.state)
            }
            if snapshot.windows.isEmpty {
                Text(emptyMessage).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.windows) { window in
                    VStack(spacing: 4) {
                        HStack {
                            Text(window.kind.label).font(.caption)
                            Spacer()
                            Text(window.remainingRatio, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        ProgressView(value: window.remainingRatio)
                            .tint(color(for: window.remainingRatio))
                        HStack {
                            Text(window.provenance.freshness.label)
                            Spacer()
                            Text(window.resetsAt.map { "리셋 \($0.formatted(date: .omitted, time: .shortened))" } ?? "리셋 미확인")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.provider.displayName), \(snapshot.state.label)")
    }

    private var emptyMessage: String {
        switch snapshot.state {
        case .notConfigured: "연결 후 quota를 확인할 수 있습니다."
        case .unsupportedContract: "안전한 조회 계약을 확인 중입니다."
        default: "현재 표시할 quota 값이 없습니다."
        }
    }

    private func color(for remaining: Double) -> Color {
        if remaining <= 0.1 { return AppTheme.danger }
        if remaining <= 0.25 { return AppTheme.warning }
        return AppTheme.cyan
    }
}
