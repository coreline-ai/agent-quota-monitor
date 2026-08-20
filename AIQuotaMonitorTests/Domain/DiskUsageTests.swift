import XCTest
@testable import AIQuotaMonitor

final class DiskUsageTests: XCTestCase {
    private struct StubDiskUsageProvider: DiskUsageProviding {
        let root: DiskUsageInfo?
        let external: DiskUsageInfo?

        func fetchDiskUsage(for target: DiskUsageTarget) async -> DiskUsageInfo? {
            switch target {
            case .root:
                root
            case .external:
                external
            }
        }
    }

    func testDiskUsageInfoCalculationAndFormatting() {
        let total: Int64 = 500_000_000_000 // 500 GB
        let free: Int64 = 125_000_000_000  // 125 GB free
        let info = DiskUsageInfo(path: "/", totalBytes: total, freeBytes: free)

        XCTAssertEqual(info.usedBytes, 375_000_000_000)
        XCTAssertEqual(info.usedRatio, 0.75, accuracy: 0.001)
        XCTAssertEqual(info.freeRatio, 0.25, accuracy: 0.001)
        XCTAssertEqual(info.formattedUsedPercent, "75%")
        XCTAssertFalse(info.formattedFree.isEmpty)
        XCTAssertFalse(info.formattedTotal.isEmpty)
        XCTAssertTrue(info.compactLabel.contains("75%"))
    }

    func testDiskUsageInfoClampsInvalidBytes() {
        let info = DiskUsageInfo(path: "/", totalBytes: -100, freeBytes: 500)
        XCTAssertEqual(info.totalBytes, 0)
        XCTAssertEqual(info.freeBytes, 0)
        XCTAssertEqual(info.usedRatio, 0)
        XCTAssertEqual(info.formattedUsedPercent, "0%")
    }

    func testDiskUsageInfoClampsFreeBytesToNormalizedTotal() {
        let overFree = DiskUsageInfo(path: "/", totalBytes: 100, freeBytes: 150)
        XCTAssertEqual(overFree.totalBytes, 100)
        XCTAssertEqual(overFree.freeBytes, 100)
        XCTAssertEqual(overFree.usedBytes, 0)

        let negativeFree = DiskUsageInfo(path: "/", totalBytes: 100, freeBytes: -1)
        XCTAssertEqual(negativeFree.freeBytes, 0)
        XCTAssertEqual(negativeFree.usedBytes, 100)
    }

    func testExternalVolumeSelectorRejectsNonLocalInternalHiddenAndRootCandidates() {
        let candidates = [
            DiskVolumeMetadata(path: "/", volumeName: "root", totalBytes: 1, freeBytes: 1, isLocal: true, isInternal: false),
            DiskVolumeMetadata(path: "/Volumes/Internal", volumeName: "internal", totalBytes: 1, freeBytes: 1, isLocal: true, isInternal: true),
            DiskVolumeMetadata(path: "/Volumes/Network", volumeName: "network", totalBytes: 1, freeBytes: 1, isLocal: false, isInternal: false),
            DiskVolumeMetadata(path: "/Volumes/.hidden", volumeName: "hidden", totalBytes: 1, freeBytes: 1, isLocal: true, isInternal: false, isHidden: true)
        ]

        XCTAssertNil(DiskVolumeSelector.externalCandidate(from: candidates))
    }

    func testExternalVolumeSelectorUsesStablePathOrderAndKeepsFixedExternalMedia() {
        let candidates = [
            DiskVolumeMetadata(path: "/Volumes/Zeta", volumeName: "Zeta", totalBytes: 1, freeBytes: 1, isLocal: true, isInternal: false),
            DiskVolumeMetadata(path: "/Volumes/Alpha", volumeName: "Alpha", totalBytes: 1, freeBytes: 1, isLocal: true, isInternal: false, isRemovable: false, isEjectable: false)
        ]

        XCTAssertEqual(DiskVolumeSelector.externalCandidate(from: candidates)?.path, "/Volumes/Alpha")
    }

    func testDiskUsageProvidingContractSupportsMissingOptionalExternalResult() async {
        let provider = StubDiskUsageProvider(
            root: DiskUsageInfo(totalBytes: 100, freeBytes: 25),
            external: nil
        )

        let root = await provider.fetchDiskUsage(for: .root)
        let external = await provider.fetchDiskUsage(for: .external)

        XCTAssertEqual(root?.formattedUsedPercent, "75%")
        XCTAssertNil(external)
    }

    func testDiskUsageServiceFetchesSystemRoot() async {
        let service = DiskUsageService()
        let usage = await service.fetchDiskUsage(for: .root)

        XCTAssertNotNil(usage)
        if let usage {
            XCTAssertGreaterThan(usage.totalBytes, 0)
            XCTAssertGreaterThanOrEqual(usage.freeBytes, 0)
            XCTAssertLessThanOrEqual(usage.freeBytes, usage.totalBytes)
            XCTAssertFalse(usage.isExternal)
        }
    }

    func testDiskUsageServiceFetchesExternalDiskIfAvailable() async {
        let service = DiskUsageService()
        let usage = await service.fetchDiskUsage(for: .external)

        if let usage {
            XCTAssertGreaterThan(usage.totalBytes, 0)
            XCTAssertGreaterThanOrEqual(usage.freeBytes, 0)
            XCTAssertTrue(usage.isExternal)
            XCTAssertFalse(usage.volumeName.isEmpty)
        }
    }
}
