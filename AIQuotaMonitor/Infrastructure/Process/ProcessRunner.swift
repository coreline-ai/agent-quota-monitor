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
    case outputTooLarge
}

private final class ProcessBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var data = Data()
    private var exceededLimit = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !chunk.isEmpty else { return }
        let remaining = maximumBytes - data.count
        guard remaining > 0 else {
            exceededLimit = true
            return
        }
        if chunk.count > remaining {
            data.append(contentsOf: chunk.prefix(remaining))
            exceededLimit = true
        } else {
            data.append(chunk)
        }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func didExceedLimit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return exceededLimit
    }

    func byteCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return data.count
    }
}

private final class ManagedProcess: @unchecked Sendable {
    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let output: ProcessBuffer
    let error: ProcessBuffer

    init(maximumOutputBytes: Int) {
        output = ProcessBuffer(maximumBytes: maximumOutputBytes)
        error = ProcessBuffer(maximumBytes: maximumOutputBytes)
    }

    func configure(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: URL?,
        input: Data?
    ) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
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

    func send(_ input: Data?, closesInput: Bool) throws {
        guard let input else { return }
        try inputPipe.fileHandleForWriting.write(contentsOf: input)
        if closesInput { try inputPipe.fileHandleForWriting.close() }
    }

    func closeInput() {
        try? inputPipe.fileHandleForWriting.close()
    }

    func finishReading() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        error.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
    }

    func stopReading() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
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
        timeout: Duration = .seconds(12),
        closesStandardInput: Bool = true,
        currentDirectory: URL? = nil,
        maximumOutputBytes: Int = 2 * 1_024 * 1_024,
        outputCompletion: (@Sendable (Data) -> Bool)? = nil
    ) async throws -> ProcessOutput {
        guard maximumOutputBytes > 0 else { throw ProcessRunnerError.outputTooLarge }
        let managed = ManagedProcess(maximumOutputBytes: maximumOutputBytes)
        managed.configure(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            input: standardInput
        )
        do {
            try managed.process.run()
            try managed.send(standardInput, closesInput: closesStandardInput)
        } catch {
            managed.stop()
            managed.forceStop()
            throw ProcessRunnerError.launchFailed
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while managed.process.isRunning {
            if exceededOutputLimit(managed, maximumOutputBytes: maximumOutputBytes) {
                await terminate(managed)
                throw ProcessRunnerError.outputTooLarge
            }
            if outputCompletion?(managed.output.value()) == true {
                managed.closeInput()
                managed.stop()
                for _ in 0 ..< 10 where managed.process.isRunning {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                managed.forceStop()
                managed.stopReading()
                return ProcessOutput(
                    exitCode: managed.process.isRunning ? -1 : managed.process.terminationStatus,
                    standardOutput: managed.output.value(),
                    standardError: managed.error.value()
                )
            }
            if Task.isCancelled {
                await terminate(managed)
                throw ProcessRunnerError.cancelled
            }
            if clock.now >= deadline {
                await terminate(managed)
                throw ProcessRunnerError.timeout
            }
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch is CancellationError {
                await terminate(managed)
                throw ProcessRunnerError.cancelled
            }
        }

        managed.finishReading()
        if exceededOutputLimit(managed, maximumOutputBytes: maximumOutputBytes) {
            throw ProcessRunnerError.outputTooLarge
        }
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

    private func terminate(_ managed: ManagedProcess) async {
        managed.closeInput()
        managed.stop()
        try? await Task.sleep(for: .milliseconds(200))
        managed.forceStop()
        await waitForExit(managed)
    }

    private func exceededOutputLimit(_ managed: ManagedProcess, maximumOutputBytes: Int) -> Bool {
        managed.output.didExceedLimit()
            || managed.error.didExceedLimit()
            || managed.output.byteCount() + managed.error.byteCount() > maximumOutputBytes
    }
}
