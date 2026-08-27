import Darwin
import XCTest
@testable import AIQuotaMonitor

final class BoundaryTests: XCTestCase {
    func testCredentialValidatorRejectsOpenPermissionsAndSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let credential = directory.appending(path: "credential.json")
        try Data("{}".utf8).write(to: credential)
        XCTAssertEqual(chmod(credential.path, 0o600), 0)
        let validator = CredentialFileValidator(allowedRoots: [directory])
        XCTAssertNoThrow(try validator.validate(credential))

        XCTAssertEqual(chmod(credential.path, 0o644), 0)
        XCTAssertThrowsError(try validator.validate(credential)) {
            XCTAssertEqual($0 as? CredentialFileError, .permissionsTooOpen)
        }

        XCTAssertEqual(chmod(credential.path, 0o600), 0)
        let link = directory.appending(path: "linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: credential)
        XCTAssertThrowsError(try validator.validate(link)) {
            XCTAssertEqual($0 as? CredentialFileError, .symbolicLink)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func testProcessRunnerSeparatesStreamsAndTimesOut() async throws {
        let runner = ProcessRunner()
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf out; printf err >&2"],
            timeout: .seconds(2)
        )
        XCTAssertEqual(String(decoding: output.standardOutput, as: UTF8.self), "out")
        XCTAssertEqual(String(decoding: output.standardError, as: UTF8.self), "err")
        XCTAssertEqual(output.exitCode, 0)

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 2"],
                timeout: .milliseconds(100)
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .timeout)
        }
    }

    func testProcessRunnerCancellationStopsChild() async throws {
        let runner = ProcessRunner()
        let task = Task {
            try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 5"],
                timeout: .seconds(10)
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .cancelled)
        }
    }

    func testProcessRunnerUsesRequestedDirectoryAndCapsOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ProcessRunner()
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/pwd"),
            arguments: [],
            timeout: .seconds(2),
            currentDirectory: directory
        )
        let reportedDirectory = String(decoding: output.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // macOS may canonicalize the public /var alias to /private/var in pwd.
        XCTAssertTrue(
            reportedDirectory == directory.path || reportedDirectory == "/private\(directory.path)",
            "unexpected working directory: \(reportedDirectory)"
        )

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '0123456789'"],
                timeout: .seconds(2),
                maximumOutputBytes: 5
            )
            XCTFail("Expected output cap failure")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .outputTooLarge)
        }

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '1234'; printf '5678' >&2"],
                timeout: .seconds(2),
                maximumOutputBytes: 6
            )
            XCTFail("Expected combined output cap failure")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .outputTooLarge)
        }
    }

    func testRefreshPolicyBackoffAndRedaction() {
        let policy = RefreshPolicy.standard
        XCTAssertEqual(policy.interval(popoverVisible: true, idle: false, consecutiveFailures: 0), .seconds(60))
        XCTAssertEqual(
            policy.interval(popoverVisible: false, idle: false, consecutiveFailures: 0, configuredMinutes: 1),
            .seconds(60)
        )
        XCTAssertEqual(
            policy.interval(popoverVisible: false, idle: false, consecutiveFailures: 0, configuredMinutes: 15),
            .seconds(900)
        )
        XCTAssertEqual(policy.interval(popoverVisible: false, idle: false, consecutiveFailures: 1), .seconds(900))
        XCTAssertEqual(policy.interval(popoverVisible: false, idle: false, consecutiveFailures: 3), .seconds(3_600))

        let redacted = Redactor.redact("Bearer abcdefghijklmnop user@example.com /Users/alice/work")
        XCTAssertFalse(redacted.contains("abcdefghijklmnop"))
        XCTAssertFalse(redacted.contains("example.com"))
        XCTAssertFalse(redacted.contains("alice"))
    }
}
