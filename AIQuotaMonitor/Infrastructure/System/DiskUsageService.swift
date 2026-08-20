import Foundation

struct DiskVolumeMetadata: Equatable, Sendable {
    let path: String
    let volumeName: String
    let totalBytes: Int64
    let freeBytes: Int64
    let isLocal: Bool
    let isInternal: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let isHidden: Bool

    init(
        path: String,
        volumeName: String,
        totalBytes: Int64,
        freeBytes: Int64,
        isLocal: Bool,
        isInternal: Bool,
        isRemovable: Bool = false,
        isEjectable: Bool = false,
        isHidden: Bool = false
    ) {
        self.path = path
        self.volumeName = volumeName
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.isLocal = isLocal
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isHidden = isHidden
    }
}

enum DiskVolumeSelector {
    static func externalCandidate(from candidates: [DiskVolumeMetadata]) -> DiskVolumeMetadata? {
        candidates
            .filter { candidate in
                candidate.path != "/"
                    && !candidate.isHidden
                    && candidate.isLocal
                    && !candidate.isInternal
            }
            .sorted { $0.path < $1.path }
            .first
    }
}

public actor DiskUsageService: DiskUsageProviding {
    public init() {}

    public func fetchDiskUsage(for target: DiskUsageTarget) async -> DiskUsageInfo? {
        switch target {
        case .root:
            fetchRootDiskUsage()
        case .external:
            fetchExternalDiskUsage()
        }
    }

    private func fetchRootDiskUsage() -> DiskUsageInfo? {
        fetchDiskUsage(at: "/", volumeName: "내부", isExternal: false)
    }

    private func fetchDiskUsage(at path: String, volumeName: String, isExternal: Bool) -> DiskUsageInfo? {
        let url = URL(fileURLWithPath: path)
        let resolvedPath = url.resolvingSymlinksInPath().path

        if let metadata = readVolumeMetadata(
            at: path,
            fallbackName: volumeName,
            isHidden: false
        ) {
            return DiskUsageInfo(
                path: resolvedPath,
                volumeName: metadata.volumeName,
                totalBytes: metadata.totalBytes,
                freeBytes: metadata.freeBytes,
                isExternal: isExternal
            )
        }

        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
           let total = (attributes[.systemSize] as? NSNumber)?.int64Value,
           let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value,
           total > 0 {
            return DiskUsageInfo(
                path: resolvedPath,
                volumeName: volumeName,
                totalBytes: total,
                freeBytes: free,
                isExternal: isExternal
            )
        }

        return nil
    }

    private func fetchExternalDiskUsage() -> DiskUsageInfo? {
        let volumesPath = "/Volumes"
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: volumesPath) else {
            return nil
        }

        let candidates = items.compactMap { item -> DiskVolumeMetadata? in
            let isHidden = item.hasPrefix(".")
            let fullPath = "\(volumesPath)/\(item)"
            let url = URL(fileURLWithPath: fullPath)
            let resolved = url.resolvingSymlinksInPath().path

            guard resolved != "/", fullPath != "/" else { return nil }
            return readVolumeMetadata(at: fullPath, fallbackName: item, isHidden: isHidden)
        }

        guard let candidate = DiskVolumeSelector.externalCandidate(from: candidates) else {
            return nil
        }
        return DiskUsageInfo(
            path: candidate.path,
            volumeName: candidate.volumeName,
            totalBytes: candidate.totalBytes,
            freeBytes: candidate.freeBytes,
            isExternal: true
        )
    }

    private func readVolumeMetadata(
        at path: String,
        fallbackName: String,
        isHidden: Bool
    ) -> DiskVolumeMetadata? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedNameKey,
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ]),
        let total = values.volumeTotalCapacity,
        total > 0,
        let isLocal = values.volumeIsLocal,
        let isInternal = values.volumeIsInternal else {
            return nil
        }

        let availableImportant = values.volumeAvailableCapacityForImportantUsage
        let availableStandard = values.volumeAvailableCapacity.map { Int64($0) }
        let available = availableImportant ?? availableStandard ?? 0
        let actualName = values.volumeLocalizedName ?? values.volumeName ?? fallbackName
        return DiskVolumeMetadata(
            path: url.resolvingSymlinksInPath().path,
            volumeName: actualName,
            totalBytes: Int64(total),
            freeBytes: available,
            isLocal: isLocal,
            isInternal: isInternal,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isHidden: isHidden
        )
    }
}
