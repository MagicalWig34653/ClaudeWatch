import Foundation

public enum HookPayloadDecodingError: Error, Equatable, CustomStringConvertible {
    case malformedJSON
    case missingRequiredField(String)
    case invalidSessionID

    public var description: String {
        switch self {
        case .malformedJSON: return "Request body is not a JSON object."
        case .missingRequiredField(let name): return "Missing required field '\(name)'."
        case .invalidSessionID: return "Invalid session_id."
        }
    }
}

/// Decodes raw hook JSON into a `HookPayload`. Knows nothing about ClaudeWatch semantics.
public struct HookPayloadDecoder: Sendable {
    public static let maxSessionIDLength = 256

    public init() {}

    public func decode(_ data: Data) throws -> HookPayload {
        guard let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else {
            throw HookPayloadDecodingError.malformedJSON
        }
        for field in ["hook_event_name", "session_id"] where !(dictionary[field] is String) {
            throw HookPayloadDecodingError.missingRequiredField(field)
        }
        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: data)
        } catch {
            throw HookPayloadDecodingError.malformedJSON
        }
        guard Self.isValidSessionID(payload.sessionID) else {
            throw HookPayloadDecodingError.invalidSessionID
        }
        return payload
    }

    /// Session IDs are used as persistent identifiers and in `claudewatch://` URLs,
    /// so only a conservative character set is accepted.
    public static func isValidSessionID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= maxSessionIDLength else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))) || "-_.:".unicodeScalars.contains(scalar)
        }
    }
}
