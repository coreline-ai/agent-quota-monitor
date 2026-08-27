import SwiftUI

private enum MenuProviderScope: String, CaseIterable, Identifiable {
    case all
    case connected
    case attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "모든 Provider"
        case .connected: "연결됨"
        case .attention: "주의 필요"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .connected: "link"
        case .attention: "exclamationmark.triangle"
        }
    }
}

private enum MenuBarLayout {
    static let providerIconSize: CGFloat = 30
    static let claudeOpticalIconSize: CGFloat = 28
}

struct MenuBarPlaceholderView: View {
    @ObservedObject var model: QuotaMonitorModel
    let onShowAllProviders: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(QuotaPreferenceKey.density) private var density = QuotaDensity.balanced
    @AppStorage(QuotaPreferenceKey.metricMode) private var metricMode = QuotaMetricMode.remaining
    @AppStorage(QuotaPreferenceKey.resetStyle) private var resetStyle = QuotaResetStyle.relative
    @AppStorage(QuotaPreferenceKey.theme) private var theme = QuotaVisualTheme.system
    @AppStorage(QuotaPreferenceKey.inspectorMode) private var inspectorMode = QuotaInspectorMode.expanded
    @AppStorage(QuotaPreferenceKey.providerOrder) private var providerOrderStorage = ProviderDisplayOrder.defaultStorageValue
    @AppStorage(QuotaPreferenceKey.providerVisible(.claude)) private var showClaude = true
    @AppStorage(QuotaPreferenceKey.providerVisible(.codex)) private var showCodex = true
    @AppStorage(QuotaPreferenceKey.providerVisible(.grok)) private var showGrok = true
    @AppStorage(QuotaPreferenceKey.providerVisible(.gemini)) private var showGemini = true
    @AppStorage(QuotaPreferenceKey.providerVisible(.zai)) private var showZAI = true
    @State private var scope = MenuProviderScope.all
    @State private var selection: ProviderID?
    @State private var diskUsage: DiskUsageInfo?
    @State private var externalDiskUsage: DiskUsageInfo?
    @State private var didLoadDiskUsage = false
    let diskUsageProvider: any DiskUsageProviding

    private var palette: BeaconPalette {
        BeaconPalette.resolve(theme: theme, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryStrip
            densityControl

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if filteredSnapshots.isEmpty {
                            emptyFilterState
                        } else {
                            ForEach(filteredSnapshots) { snapshot in
                                ProviderLedgerRow(
                                    snapshot: snapshot,
                                    isSelected: selection == snapshot.provider,
                                    density: density,
                                    metricMode: metricMode,
                                    resetStyle: resetStyle,
                                    showsInspector: inspectorMode == .expanded,
                                    palette: palette,
                                    onSelect: {
                                        select(snapshot.provider)
                                        scrollToProvider(snapshot.provider, using: proxy)
                                    }
                                )
                                .id(snapshot.provider)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 430, height: 560, alignment: .topLeading)
        .background(palette.canvas)
        .foregroundStyle(palette.primaryText)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear { repairSelection() }
        .onChange(of: filteredSnapshots.map(\.provider)) { _, _ in repairSelection() }
        .task(id: model.lastRefreshAt) { await refreshDiskUsage() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(AppTheme.headerAssetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: palette.accent.opacity(0.18), radius: 4, y: 1)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaBeacon")
                    .font(.headline)
                Text(lastRefreshText)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(MenuProviderScope.allCases) { item in
                    Button {
                        scope = item
                    } label: {
                        Label(item.label, systemImage: item.symbol)
                    }
                }
            } label: {
                Label(scope.label, systemImage: scope.symbol)
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("menu.scope")

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(model.isRefreshing && !reduceMotion ? 360 : 0))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.55),
                        value: model.isRefreshing
                    )
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .help("모든 Provider 새로고침")
            .accessibilityLabel("새로고침")
            .accessibilityIdentifier("menu.refresh")
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryMetric(
                title: "연결",
                value: "\(connectedVisibleCount)",
                symbol: "link"
            )
            Divider().frame(height: 28)
            summaryMetric(
                title: "가까운 리셋",
                value: nearestResetText,
                symbol: "clock.arrow.circlepath"
            )
        }
        .padding(.vertical, 8)
        .background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.border)
        }
    }

    private var densityControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("표시 밀도", selection: $density) {
                ForEach(QuotaDensity.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("표시 밀도")
            .accessibilityIdentifier("menu.density")

            HStack(spacing: 6) {
                if let diskUsage {
                    diskBadge(diskUsage, icon: "internaldrive", label: "내부")
                } else {
                    diskPlaceholder(icon: "internaldrive", label: "내부")
                }
                if let externalDiskUsage {
                    diskBadge(externalDiskUsage, icon: "externaldrive", label: "외장")
                } else {
                    diskPlaceholder(icon: "externaldrive", label: "외장")
                }
            }
        }
    }

    private func diskBadge(_ info: DiskUsageInfo, icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(palette.accent)
            Text("\(label) \(info.compactLabel)")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette.border)
        }
        .help("\(label) · \(info.volumeName) (\(info.path)) 전체 \(info.formattedTotal) 중 여유 공간 \(info.formattedFree)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(info.volumeName) 사용량 \(info.compactLabel)")
        .accessibilityIdentifier(info.isExternal ? "menu.externalDiskUsage" : "menu.diskUsage")
    }

    private func diskPlaceholder(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
            Text("\(label) \(didLoadDiskUsage ? "연결 없음" : "확인 중")")
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette.border)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(didLoadDiskUsage ? "연결 없음" : "확인 중")")
        .accessibilityIdentifier(label == "외장" ? "menu.externalDiskUsage.placeholder" : "menu.diskUsage.placeholder")
    }

    private func refreshDiskUsage() async {
        async let root = diskUsageProvider.fetchDiskUsage(for: .root)
        async let external = diskUsageProvider.fetchDiskUsage(for: .external)
        let (rootUsage, externalUsage) = await (root, external)
        guard !Task.isCancelled else { return }
        diskUsage = rootUsage
        externalDiskUsage = externalUsage
        didLoadDiskUsage = true
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(metricMode.label) 표시 · 위험은 잔여 기준", systemImage: "circle.lefthalf.filled")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .layoutPriority(1)
            Button(action: onShowAllProviders) {
                Label(String(localized: "menu.openAllProviders"), systemImage: "rectangle.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .frame(maxWidth: .infinity)
                .controlSize(.large)
                .help(String(localized: "menu.openAllProviders"))
                .accessibilityIdentifier("menu.openDashboard")
        }
        .padding(.top, 2)
    }

    private var emptyFilterState: some View {
        VStack(spacing: 8) {
            Image(systemName: scope == .all ? "eye.slash" : "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(palette.secondaryText)
            Text(scope == .all ? "표시할 Provider가 없습니다." : "이 필터에 해당하는 Provider가 없습니다.")
                .font(.subheadline.weight(.medium))
            Text(scope == .all ? "대시보드 설정에서 Provider 표시를 켜세요." : "다른 범위를 선택해 보세요.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .accessibilityElement(children: .combine)
    }

    private func summaryMetric(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(palette.secondaryText)
                Text(value).font(.caption.monospacedDigit().weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
    }

    private var lastRefreshText: String {
        guard let lastRefreshAt = model.lastRefreshAt else { return "로컬 전용 · 연결 상태 확인 중" }
        return "업데이트 \(lastRefreshAt.formatted(date: .omitted, time: .shortened))"
    }

    private var connectedVisibleCount: Int {
        visibleSnapshots.filter { [.available, .partial, .stale].contains($0.state) }.count
    }

    private var nearestResetText: String {
        let date = visibleSnapshots
            .flatMap(\.windows)
            .compactMap(\.resetsAt)
            .filter { $0 > Date() }
            .min()
        return QuotaPresentation.resetText(for: date, style: resetStyle)
    }

    private var visibleSnapshots: [ProviderSnapshot] {
        ProviderDisplayOrder(storageValue: providerOrderStorage)
            .ordered(model.snapshots)
            .filter { isVisible($0.provider) }
    }

    private var filteredSnapshots: [ProviderSnapshot] {
        visibleSnapshots.filter { snapshot in
            switch scope {
            case .all:
                true
            case .connected:
                [.available, .partial, .stale].contains(snapshot.state)
            case .attention:
                snapshot.state != .available
                    || snapshot.windows.contains { $0.remainingRatio <= 0.25 }
            }
        }
    }

    private func isVisible(_ provider: ProviderID) -> Bool {
        switch provider {
        case .claude: showClaude
        case .codex: showCodex
        case .grok: showGrok
        case .gemini: showGemini
        case .zai: showZAI
        }
    }

    private func repairSelection() {
        let available = filteredSnapshots.map(\.provider)
        guard let selection else { return }
        guard available.contains(selection) else {
            self.selection = nil
            return
        }
    }

    private func select(_ provider: ProviderID) {
        let nextSelection = selection == provider ? nil : provider
        if reduceMotion {
            selection = nextSelection
        } else {
            withAnimation(.easeOut(duration: 0.16)) { selection = nextSelection }
        }
    }

    private func scrollToProvider(_ provider: ProviderID, using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if reduceMotion {
                proxy.scrollTo(provider, anchor: .top)
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(provider, anchor: .top)
                }
            }
        }
    }
}

private struct ProviderLedgerRow: View {
    let snapshot: ProviderSnapshot
    let isSelected: Bool
    let density: QuotaDensity
    let metricMode: QuotaMetricMode
    let resetStyle: QuotaResetStyle
    let showsInspector: Bool
    let palette: BeaconPalette
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            BeaconSurface(selected: isSelected, palette: palette) {
                HStack(alignment: .top, spacing: 10) {
                    beaconRail
                    ProviderMark(provider: snapshot.provider, size: providerIconContentSize)
                        .frame(
                            width: MenuBarLayout.providerIconSize,
                            height: MenuBarLayout.providerIconSize,
                            alignment: .center
                        )
                    VStack(alignment: .leading, spacing: density == .compact ? 6 : 9) {
                        providerHeader
                        quotaSummary
                        if isSelected, showsInspector, !snapshot.windows.isEmpty {
                            Divider().overlay(palette.border)
                            providerInspector
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(snapshot.provider.displayName), \(snapshot.state.label)")
        .accessibilityIdentifier("menu.provider.\(snapshot.provider.rawValue)")
    }

    private var providerIconContentSize: CGFloat {
        snapshot.provider == .claude
            ? MenuBarLayout.claudeOpticalIconSize
            : MenuBarLayout.providerIconSize
    }

    private var beaconRail: some View {
        Capsule()
            .fill(snapshot.provider.beaconTint.opacity(isSelected ? 1 : 0.32))
            .frame(width: 3, height: isSelected ? 30 : 16)
            .padding(.top, isSelected ? 0 : 7)
            .shadow(color: isSelected ? snapshot.provider.beaconTint.opacity(0.42) : .clear, radius: 4)
            .accessibilityHidden(true)
    }

    private var providerHeader: some View {
        HStack(spacing: 7) {
            Text(snapshot.provider.beaconShortName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            ProviderStateBadge(state: snapshot.state)
            Spacer(minLength: 4)
            Text(resetSummary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(palette.secondaryText)
        }
    }

    @ViewBuilder
    private var quotaSummary: some View {
        if snapshot.windows.isEmpty {
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if density == .compact, let window = QuotaPresentation.summaryWindow(for: snapshot) {
            BeaconQuotaBar(
                window: window,
                metricMode: metricMode,
                resetStyle: resetStyle,
                palette: palette,
                compact: true
            )
        } else {
            VStack(spacing: 6) {
                ForEach(snapshot.windows.prefix(3)) { window in
                    compactMeter(window)
                }
            }
        }
    }

    private var providerInspector: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Quota 상세").font(.caption.weight(.bold)).foregroundStyle(palette.secondaryText)
                Spacer()
                Text("\(snapshot.windows.count)개 window")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(snapshot.windows) { window in
                BeaconQuotaBar(
                    window: window,
                    metricMode: metricMode,
                    resetStyle: resetStyle,
                    palette: palette,
                    showProvenance: true
                )
            }
        }
        .padding(.top, 1)
    }

    private func compactMeter(_ window: QuotaWindow) -> some View {
        let ratio = QuotaPresentation.ratio(for: window, mode: metricMode)
        let urgency = QuotaPresentation.urgency(forRemaining: window.remainingRatio)
        return HStack(spacing: 7) {
            Text(window.kind.label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .frame(width: 54, alignment: .leading)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.secondaryText.opacity(0.18))
                    Capsule().fill(color(for: urgency)).frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 5)
            Text(QuotaPresentation.metricText(for: window, mode: metricMode))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(color(for: urgency))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(minWidth: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.kind.label), \(QuotaPresentation.metricText(for: window, mode: metricMode))")
    }

    private var resetSummary: String {
        let reset = snapshot.windows.compactMap(\.resetsAt).filter { $0 > Date() }.min()
        return QuotaPresentation.resetText(for: reset, style: resetStyle)
    }

    private var emptyMessage: String {
        switch snapshot.state {
        case .notConfigured: "연결 후 quota를 확인할 수 있습니다."
        case .unsupportedContract: "안전한 조회 계약을 확인 중입니다."
        default: "현재 표시할 quota 값이 없습니다."
        }
    }

    private func color(for urgency: QuotaUrgency) -> Color {
        switch urgency {
        case .healthy: AppTheme.cyan
        case .warning: AppTheme.warning
        case .critical: AppTheme.danger
        }
    }
}
