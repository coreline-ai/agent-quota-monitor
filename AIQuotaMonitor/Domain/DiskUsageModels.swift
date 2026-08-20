import Foundation

public enum DiskUsageTarget: Equatable, Sendable {
    case root
    case external
}

public protocol DiskUsageProviding: Sendable {
    func fetchDiskUsage(for target: DiskUsageTarget) async -> DiskUsageInfo?
}

public struct DiskUsageInfo: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let volumeName: String
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let isExternal: Bool

    public init(
        path: String = "/",
        volumeName: String = "내부",
        totalBytes: Int64,
        freeBytes: Int64,
        isExternal: Bool = false
    ) {
        let normalizedTotal = max(0, totalBytes)
        self.path = path
        self.volumeName = volumeName
        self.totalBytes = normalizedTotal
        self.freeBytes = max(0, min(freeBytes, normalizedTotal))
        self.isExternal = isExternal
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }

    public var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public var freeRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    public var formattedFree: String {
        Self.formatBytes(freeBytes)
    }

    public var formattedTotal: String {
        Self.formatBytes(totalBytes)
    }

    public var formattedUsedPercent: String {
        let percent = Int(round(usedRatio * 100))
        return "\(percent)%"
    }

    public var compactLabel: String {
        "\(formattedUsedPercent) (\(formattedFree) 여유)"
    }
}
