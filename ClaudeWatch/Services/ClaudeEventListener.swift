import Foundation
import Network
import Observation
import ClaudeWatchCore

/// Minimal HTTP endpoint for Claude Code hooks, bound to 127.0.0.1 only.
///
/// Validation (size limits, content type, JSON shape) happens before responding; persistence
/// and notifications happen after the response is sent, so hooks never wait on them.
@MainActor
@Observable
final class ClaudeEventListener {
    enum State: Equatable {
        case stopped
        case starting(port: UInt16)
        case running(port: UInt16)
        case failed(port: UInt16, message: String)
    }

    private(set) var state: State = .stopped
    private(set) var acceptedCount = 0
    private(set) var rejectedCount = 0
    private(set) var lastEventAt: Date?

    /// Receives validated payloads on the main actor.
    @ObservationIgnored var onPayload: ((HookPayload) -> Void)?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let queue = DispatchQueue(label: "ClaudeWatch.listener")

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port), port > 0 else {
            state = .failed(port: port, message: "Invalid port \(port).")
            return
        }
        state = .starting(port: port)

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            state = .failed(port: port, message: Self.describe(error, port: port))
            Log.listener.error("Could not create listener: \(error.localizedDescription, privacy: .public)")
            return
        }

        listener.stateUpdateHandler = { [weak self] newState in
            guard let owner = self else { return }
            Task { @MainActor in owner.handle(newState, listener: listener, port: port) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let owner = self else {
                connection.cancel()
                return
            }
            let handler = HookConnection(connection: connection, queue: DispatchQueue(label: "ClaudeWatch.connection")) { accepted, payload in
                Task { @MainActor in owner.record(accepted: accepted, payload: payload) }
            }
            handler.start()
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    private func handle(_ newState: NWListener.State, listener: NWListener, port: UInt16) {
        guard listener === self.listener else { return }
        switch newState {
        case .ready:
            state = .running(port: port)
            Log.listener.info("Listening on 127.0.0.1:\(port, privacy: .public)")
        case .failed(let error), .waiting(let error):
            state = .failed(port: port, message: Self.describe(error, port: port))
            Log.listener.error("Listener failed on port \(port, privacy: .public): \(error.localizedDescription, privacy: .public)")
            listener.cancel()
            self.listener = nil
        case .cancelled:
            if case .running = state { state = .stopped }
        default:
            break
        }
    }

    private func record(accepted: Bool, payload: HookPayload?) {
        if accepted {
            acceptedCount += 1
            lastEventAt = Date()
        } else {
            rejectedCount += 1
        }
        if let payload { onPayload?(payload) }
    }

    private static func describe(_ error: Error, port: UInt16) -> String {
        if let nwError = error as? NWError, case .posix(let code) = nwError {
            if code == .EADDRINUSE {
                return "Port \(port) is already in use. Choose another port or quit the app using it."
            }
            if code == .EACCES {
                return "Not allowed to listen on port \(port)."
            }
        }
        return "Could not listen on port \(port): \(error.localizedDescription)"
    }
}

/// One HTTP exchange. Confined to its own serial queue.
private final class HookConnection: @unchecked Sendable {
    private static let parser = HTTPRequestParser()
    private static let router = HookRequestRouter()
    private static let timeout: TimeInterval = 10

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let completion: @Sendable (_ accepted: Bool, _ payload: HookPayload?) -> Void
    private var buffer = Data()
    private var responded = false
    private var finished = false

    init(connection: NWConnection, queue: DispatchQueue, completion: @escaping @Sendable (Bool, HookPayload?) -> Void) {
        self.connection = connection
        self.queue = queue
        self.completion = completion
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .failed, .cancelled:
                self.finish(accepted: false, payload: nil, notify: false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.timeout) { [self] in
            guard !self.finished else { return }
            self.respond(.error(408, "Request timed out"), payload: nil)
        }
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            guard !self.finished, !self.responded else { return }
            if let data { self.buffer.append(data) }
            switch Self.parser.parse(self.buffer) {
            case .complete(let request):
                guard case .respond(let response, let payload) = Self.router.route(request) else { return }
                self.respond(response, payload: payload)
            case .failure(let response):
                self.respond(response, payload: nil)
            case .incomplete:
                if error != nil || isComplete {
                    self.finish(accepted: false, payload: nil, notify: true)
                } else {
                    self.receive()
                }
            }
        }
    }

    private func respond(_ response: HTTPResponse, payload: HookPayload?) {
        guard !finished, !responded else { return }
        responded = true
        connection.send(content: response.serialized(), completion: .contentProcessed { [self] _ in
            self.finish(accepted: payload != nil, payload: payload, notify: true)
        })
    }

    private func finish(accepted: Bool, payload: HookPayload?, notify: Bool) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        if notify { completion(accepted, payload) }
    }
}
