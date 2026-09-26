import Foundation

public enum SessionStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case running
    case needsInput = "needs_input"
    case waitingForPermission = "waiting_for_permission"
    case waitingForPlanApproval = "waiting_for_plan_approval"
    case finished
    case failed
    case unknown

    public var displayName: String {
        switch self {
        case .running: return "Running"
        case .needsInput: return "Needs Input"
        case .waitingForPermission: return "Waiting for Permission"
        case .waitingForPlanApproval: return "Waiting for Plan Approval"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        }
    }

    /// Sessions that are not finished or failed. Active sessions must never be deleted.
    public var isActive: Bool {
        switch self {
        case .running, .needsInput, .waitingForPermission, .waitingForPlanApproval: return true
        case .finished, .failed, .unknown: return false
        }
    }
}

public enum SessionSource: String, Codable, CaseIterable, Sendable, Hashable {
    case local
    case cloud
    case relay
    case unknown

    public var displayName: String {
        switch self {
        case .local: return "Local"
        case .cloud: return "Cloud"
        case .relay: return "Relay"
        case .unknown: return "Unknown"
        }
    }
}
