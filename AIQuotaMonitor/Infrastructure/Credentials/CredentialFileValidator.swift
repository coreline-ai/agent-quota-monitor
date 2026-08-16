import Darwin
import Foundation

enum CredentialFileError: Error, Equatable {
    case outsideAllowlist
    case symbolicLink
    case notRegularFile
    case wrongOwner
    case permissionsTooOpen
    case unreadable
}

struct CredentialFileValidator: Sendable {
    let allowedRoots: [URL]

    func validate(_ url: URL) throws {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let original = url.standardizedFileURL
        guard candidate.path == original.path else { throw CredentialFileError.symbolicLink }
        guard allowedRoots.contains(where: { candidate.path.hasPrefix($0.standardizedFileURL.path + "/") }) else {
            throw CredentialFileError.outsideAllowlist
        }

        var info = stat()
        guard lstat(original.path, &info) == 0 else { throw CredentialFileError.unreadable }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw CredentialFileError.notRegularFile }
        guard info.st_uid == getuid() else { throw CredentialFileError.wrongOwner }
        guard (info.st_mode & 0o077) == 0 else { throw CredentialFileError.permissionsTooOpen }
        guard FileManager.default.isReadableFile(atPath: original.path) else {
            throw CredentialFileError.unreadable
        }
    }
}
