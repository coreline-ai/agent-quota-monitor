import XCTest
@testable import AIQuotaMonitor

final class ProviderDisplayOrderTests: XCTestCase {
    func testDefaultOrderPreservesCurrentMenuPresentation() {
        XCTAssertEqual(
            ProviderDisplayOrder.defaultProviders,
            [.claude, .codex, .gemini, .grok, .zai]
        )
        XCTAssertEqual(
            ProviderDisplayOrder.defaultStorageValue,
            "claude,codex,gemini,grok,zai"
        )
    }

    func testStorageValueRoundTripsCustomOrder() {
        let order = ProviderDisplayOrder([.zai, .gemini, .claude, .codex, .grok])

        XCTAssertEqual(
            ProviderDisplayOrder(storageValue: order.storageValue).providers,
            [.zai, .gemini, .claude, .codex, .grok]
        )
    }

    func testStorageValueRepairsUnknownDuplicateAndMissingProviders() {
        let order = ProviderDisplayOrder(storageValue: "zai,unknown,codex,zai")

        XCTAssertEqual(order.providers, [.zai, .codex, .claude, .gemini, .grok])
    }

    func testBlankStorageValueUsesDefaultOrder() {
        XCTAssertEqual(ProviderDisplayOrder(storageValue: nil).providers, ProviderDisplayOrder.defaultProviders)
        XCTAssertEqual(ProviderDisplayOrder(storageValue: "").providers, ProviderDisplayOrder.defaultProviders)
    }

    func testMovingProviderRespectsEdgesAndDropDestination() {
        let order = ProviderDisplayOrder()

        XCTAssertEqual(order.moving(.claude, by: -1), order)
        XCTAssertEqual(
            order.moving(.zai, by: -1).providers,
            [.claude, .codex, .gemini, .zai, .grok]
        )
        XCTAssertEqual(
            order.moving(.zai, before: .claude).providers,
            [.zai, .claude, .codex, .gemini, .grok]
        )
    }

    func testOrderedSnapshotsUseDisplayOrderWithoutChangingSnapshotValues() {
        let snapshots: [ProviderSnapshot] = [.zai, .grok, .claude, .gemini, .codex].map {
            ProviderSnapshot.unavailable($0, state: .notConfigured)
        }

        let ordered = ProviderDisplayOrder([.zai, .codex]).ordered(snapshots)

        XCTAssertEqual(ordered.map(\.provider), [.zai, .codex, .claude, .gemini, .grok])
        XCTAssertEqual(snapshots.map(\.provider), [.zai, .grok, .claude, .gemini, .codex])
    }

    func testVisibilityAndScopeStyleFiltersPreserveCustomRelativeOrder() {
        let snapshots = [
            ProviderSnapshot.unavailable(.claude, state: .notConfigured),
            ProviderSnapshot.unavailable(.codex, state: .partial),
            ProviderSnapshot.unavailable(.gemini, state: .stale),
            ProviderSnapshot.unavailable(.grok, state: .rateLimited),
            ProviderSnapshot.unavailable(.zai, state: .available)
        ]
        let displayOrder = ProviderDisplayOrder([.zai, .codex, .claude, .gemini, .grok])
        let ordered = displayOrder.ordered(snapshots)

        let visible = ordered.filter { $0.provider != .codex }
        let connected = visible.filter { [.available, .partial, .stale].contains($0.state) }
        let attention = visible.filter { $0.state != .available }

        XCTAssertEqual(visible.map(\.provider), [.zai, .claude, .gemini, .grok])
        XCTAssertEqual(connected.map(\.provider), [.zai, .gemini])
        XCTAssertEqual(attention.map(\.provider), [.claude, .gemini, .grok])
        XCTAssertEqual(ordered.map(\.provider), [.zai, .codex, .claude, .gemini, .grok])
    }
}
