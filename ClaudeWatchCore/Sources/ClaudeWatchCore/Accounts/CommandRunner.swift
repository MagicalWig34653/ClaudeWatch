import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum CommandError: Error, Equatable {
    case launchFailed(String)
    case timedOut
}

/// Runs an executable with an explicit argument array. Never goes through a shell
/// unless the caller explicitly runs one with fixed arguments.
public protocol CommandRunner: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) async throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let box = ProcessBox()
                let process = box.process
                process.executableURL = executable
                process.arguments = arguments
                if let environment { process.environment = environment }
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.launchFailed(executable.lastPathComponent))
                    return
                }
                let timer = DispatchWorkItem { box.terminateIfRunning() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

                let errorBuffer = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errorBuffer.set(stderr.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                timer.cancel()

                if box.didTimeOut {
                    continuation.resume(throwing: CommandError.timedOut)
                } else {
                    continuation.resume(returning: CommandResult(
                        exitCode: process.terminationStatus,
                        standardOutput: output,
                        standardError: errorBuffer.get()
                    ))
                }
            }
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var timedOut = false

    var didTimeOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return timedOut
    }

    func terminateIfRunning() {
        lock.lock(); defer { lock.unlock() }
        if process.isRunning {
            timedOut = true
            process.terminate()
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}
