import SwiftUI

extension ProviderState {
    var label: String {
        switch self {
        case .available: "LIVE"
        case .partial: "부분 데이터"
        case .stale: "캐시"
        case .notConfigured: "연결 필요"
        case .authenticationRequired: "인증 필요"
        case .unsupportedAccount: "계정 미지원"
        case .unsupportedContract: "Beta · 확인 불가"
        case .rateLimited: "요청 제한"
        case .offline: "오프라인"
        case .failed: "수집 실패"
        }
    }

    var tint: Color {
        switch self {
        case .available: AppTheme.cyan
        case .partial, .stale, .rateLimited: AppTheme.warning
        case .failed, .authenticationRequired: AppTheme.danger
        default: .secondary
        }
    }
}

extension DataFreshness {
    var label: String {
        switch self {
        case .live: "LIVE"
        case .recent: "최근"
        case .stale: "캐시"
        case .unknown: "확인 불가"
        }
    }
}

struct ProviderStateBadge: View {
    let state: ProviderState

    var body: some View {
        Text(state.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(state.tint)
            .background(state.tint.opacity(0.12), in: Capsule())
    }
}

struct SignalPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.contentCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.contentCornerRadius)
                .strokeBorder(.primary.opacity(0.07))
        }
    }
}
