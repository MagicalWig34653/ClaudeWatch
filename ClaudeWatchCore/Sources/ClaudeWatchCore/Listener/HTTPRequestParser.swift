import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    /// Header names are lowercased.
    public let headers: [String: String]
    public let body: Data
}

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, json: String) {
        self.status = status
        self.body = Data(json.utf8)
    }

    public var reasonPhrase: String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 431: return "Request Header Fields Too Large"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }

    /// Serialized HTTP/1.1 response. The connection is always closed afterwards.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reasonPhrase)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return HTTPResponse(status: status, json: "{\"error\":\"\(escaped)\"}")
    }
}

/// Incremental parser for the small HTTP/1.1 subset the hook listener needs.
/// Requires `Content-Length`; chunked bodies are rejected.
public struct HTTPRequestParser: Sendable {
    public enum Result: Sendable, Equatable {
        case incomplete
        case complete(HTTPRequest)
        case failure(HTTPResponse)
    }

    public let maxHeaderBytes: Int
    public let maxBodyBytes: Int

    public init(maxHeaderBytes: Int = 16 * 1024, maxBodyBytes: Int = 2 * 1024 * 1024) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
    }

    public func parse(_ buffer: Data) -> Result {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            return buffer.count > maxHeaderBytes ? .failure(.error(431, "Headers too large")) : .incomplete
        }
        guard headerEnd.lowerBound - buffer.startIndex <= maxHeaderBytes else {
            return .failure(.error(431, "Headers too large"))
        }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .failure(.error(400, "Malformed request"))
        }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .failure(.error(400, "Malformed request line"))
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .failure(.error(400, "Malformed header")) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil {
            return .failure(.error(411, "Chunked bodies are not supported; send Content-Length"))
        }
        let contentLength: Int
        if let raw = headers["content-length"] {
            guard let value = Int(raw), value >= 0 else { return .failure(.error(400, "Invalid Content-Length")) }
            contentLength = value
        } else {
            contentLength = 0
        }
        guard contentLength <= maxBodyBytes else {
            return .failure(.error(413, "Request body exceeds \(maxBodyBytes) bytes"))
        }
        let bodyStart = headerEnd.upperBound
        let available = buffer.endIndex - bodyStart
        guard available >= contentLength else { return .incomplete }
        let body = buffer[bodyStart..<(bodyStart + contentLength)]
        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(body)
        ))
    }
}

/// Validates listener requests and turns accepted ones into hook payloads.
public struct HookRequestRouter: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Reply with `response`; if `payload` is set, process it after replying.
        case respond(HTTPResponse, payload: HookPayload?)
    }

    public static let eventsPath = "/v1/events"
    public static let healthPath = "/v1/health"

    private let decoder = HookPayloadDecoder()

    public init() {}

    public func route(_ request: HTTPRequest) -> Outcome {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        // Browsers always send Origin on cross-site POSTs; hooks never do.
        if request.headers["origin"] != nil {
            return .respond(.error(403, "Browser requests are not accepted"), payload: nil)
        }
        switch path {
        case Self.healthPath:
            guard request.method == "GET" else { return .respond(.error(405, "Use GET"), payload: nil) }
            return .respond(HTTPResponse(status: 200, json: "{\"status\":\"ok\"}"), payload: nil)
        case Self.eventsPath:
            guard request.method == "POST" else { return .respond(.error(405, "Use POST"), payload: nil) }
            let contentType = request.headers["content-type"]?.lowercased() ?? ""
            guard contentType.hasPrefix("application/json") else {
                return .respond(.error(415, "Content-Type must be application/json"), payload: nil)
            }
            do {
                let payload = try decoder.decode(request.body)
                // `{}` is a no-op for Claude Code hooks that interpret the response body.
                return .respond(HTTPResponse(status: 200, json: "{}"), payload: payload)
            } catch let error as HookPayloadDecodingError {
                return .respond(.error(400, error.description), payload: nil)
            } catch {
                return .respond(.error(400, "Invalid payload"), payload: nil)
            }
        default:
            return .respond(.error(404, "Not found"), payload: nil)
        }
    }
}
