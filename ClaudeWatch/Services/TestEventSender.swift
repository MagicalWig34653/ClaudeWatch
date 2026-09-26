import Foundation

/// Sends a Claude-Code-shaped hook payload to the local listener over HTTP, so the test
/// travels through the complete pipeline: listener → decoder → normalizer → processor → notifications.
enum TestEventSender {
    static let sessionID = "claudewatch-test-session"

    enum Failure: LocalizedError {
        case listenerNotRunning
        case rejected(Int)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .listenerNotRunning: return "The local listener is not running."
            case .rejected(let status): return "The listener rejected the test event (HTTP \(status))."
            case .network(let message): return "Could not reach the listener: \(message)"
            }
        }
    }

    static func payload() -> [String: Any] {
        [
            "hook_event_name": "PreToolUse",
            "session_id": sessionID,
            "cwd": NSHomeDirectory() + "/ClaudeWatch Test",
            "prompt_id": UUID().uuidString,
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [[
                    "question": "This is a ClaudeWatch test event. Did the notification arrive?",
                    "header": "Test",
                    "multiSelect": false,
                    "options": [["label": "Yes", "description": ""], ["label": "No", "description": ""]],
                ]],
            ],
        ]
    }

    static func send(port: UInt16) async throws {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/events") else { throw Failure.listenerNotRunning }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload())
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw Failure.rejected(status) }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.network(error.localizedDescription)
        }
    }
}
