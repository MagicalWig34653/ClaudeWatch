import Foundation

/// Centralized session state transitions. Views never compute status themselves.
public enum SessionStateMachine {
    /// Returns the status a session moves to when `event` arrives.
    /// - Parameter current: the current status, or `nil` for a session seen for the first time.
    public static func nextStatus(from current: SessionStatus?, on event: ClaudeEventType) -> SessionStatus {
        switch event {
        case .sessionStarted, .activity:
            // Any new activity — including after finishing or failing — means Claude is working.
            return .running
        case .needsInput:
            return .needsInput
        case .permissionRequired:
            return .waitingForPermission
        case .planApprovalRequired:
            return .waitingForPlanApproval
        case .finished:
            return .finished
        case .failed:
            return .failed
        case .sessionEnded:
            return current == .failed ? .failed : .finished
        case .idle:
            // An idle reminder does not change what Claude is doing; it only
            // tells us the session is waiting for a new prompt.
            return current ?? .finished
        }
    }

    /// Whether a session in `status` requires the user to act.
    public static func requiresAttention(_ status: SessionStatus) -> Bool {
        switch status {
        case .needsInput, .waitingForPermission, .waitingForPlanApproval, .failed:
            return true
        case .running, .finished, .unknown:
            return false
        }
    }
}
