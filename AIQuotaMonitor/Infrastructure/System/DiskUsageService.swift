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
                    && (!candidate.isInternal || candidate.isRemovable || candidate.isEjectable)
            }
            .sorted { lhs, rhs in
                let lhsPortable = lhs.isRemovable || lhs.isEjectable
                let rhsPortable = rhs.isRemovable || rhs.isEjectable
                if lhsPortable != rhsPortable { return lhsPortable }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
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
        let resourceKeys: [URLResourceKey] = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedNameKey,
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ]
        let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []

        // mountedVolumeURLs is the authoritative source. The /Volumes fallback
        // covers newly attached media during the short interval before the mount
        // registry has propagated the new volume.
        let directoryURLs = ((try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes", isDirectory: true),
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )) ?? [])
        let uniqueURLs = Dictionary(
            (mountedURLs + directoryURLs).map { ($0.resolvingSymlinksInPath().path, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values

        let candidates = uniqueURLs.compactMap { url -> DiskVolumeMetadata? in
            let resolvedPath = url.resolvingSymlinksInPath().path
            guard resolvedPath != "/", resolvedPath.hasPrefix("/Volumes/") else { return nil }
            return readVolumeMetadata(
                at: url.path,
                fallbackName: url.lastPathComponent,
                isHidden: url.lastPathComponent.hasPrefix(".")
            )
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
        ]) else {
            return nil
        }

        let fileSystemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: path)
        let totalFromAttributes = (fileSystemAttributes?[.systemSize] as? NSNumber)?.int64Value
        let freeFromAttributes = (fileSystemAttributes?[.systemFreeSize] as? NSNumber)?.int64Value
        let total = values.volumeTotalCapacity.map(Int64.init) ?? totalFromAttributes ?? 0
        guard total > 0 else { return nil }

        let availableImportant = values.volumeAvailableCapacityForImportantUsage
        let availableStandard = values.volumeAvailableCapacity.map { Int64($0) }
        let available = availableImportant ?? availableStandard ?? freeFromAttributes ?? 0
        let actualName = values.volumeLocalizedName ?? values.volumeName ?? fallbackName
        return DiskVolumeMetadata(
            path: url.resolvingSymlinksInPath().path,
            volumeName: actualName,
            totalBytes: total,
            freeBytes: available,
            isLocal: values.volumeIsLocal ?? true,
            isInternal: values.volumeIsInternal ?? (path == "/"),
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isHidden: isHidden
        )
    }
}
