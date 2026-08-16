import Darwin
import Foundation

struct ProcessOutput: Sendable, Equatable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

enum ProcessRunnerError: Error, Equatable {
    case launchFailed
    case timeout
    case cancelled
}

private final class ProcessBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class ManagedProcess: @unchecked Sendable {
    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let output = ProcessBuffer()
    let error = ProcessBuffer()

    func configure(executable: URL, arguments: [String], environment: [String: String]?, input: Data?) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if input != nil { process.standardInput = inputPipe }
        outputPipe.fileHandleForReading.readabilityHandler = { [output] handle in
            let data = handle.availableData
            if !data.isEmpty { output.append(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [error] handle in
            let data = handle.availableData
            if !data.isEmpty { error.append(data) }
        }
    }

    func send(_ input: Data?) throws {
        guard let input else { return }
        try inputPipe.fileHandleForWriting.write(contentsOf: input)
        try inputPipe.fileHandleForWriting.close()
    }

    func finishReading() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        error.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
    }

    func forceStop() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }
}

actor ProcessRunner {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        timeout: Duration = .seconds(12)
    ) async throws -> ProcessOutput {
        let managed = ManagedProcess()
        managed.configure(executable: executable, arguments: arguments, environment: environment, input: standardInput)
        do {
            try managed.process.run()
            try managed.send(standardInput)
        } catch {
            managed.stop()
            managed.forceStop()
            throw ProcessRunnerError.launchFailed
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while managed.process.isRunning {
            if Task.isCancelled {
                managed.stop()
                try? await Task.sleep(for: .milliseconds(200))
                managed.forceStop()
                await waitForExit(managed)
                throw ProcessRunnerError.cancelled
            }
            if clock.now >= deadline {
                managed.stop()
                try? await Task.sleep(for: .milliseconds(200))
                managed.forceStop()
                await waitForExit(managed)
                throw ProcessRunnerError.timeout
            }
            try await Task.sleep(for: .milliseconds(40))
        }

        managed.finishReading()
        return ProcessOutput(
            exitCode: managed.process.terminationStatus,
            standardOutput: managed.output.value(),
            standardError: managed.error.value()
        )
    }

    private func waitForExit(_ managed: ManagedProcess) async {
        for _ in 0 ..< 10 where managed.process.isRunning {
            try? await Task.sleep(for: .milliseconds(20))
        }
        managed.finishReading()
    }
}
