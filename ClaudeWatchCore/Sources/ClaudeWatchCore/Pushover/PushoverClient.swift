import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraction over the HTTP stack so the Pushover API can be tested without real requests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PushoverError.invalidResponse }
        return (data, http)
    }
}

public struct PushoverCredentials: Sendable, Equatable {
    public let userKey: String
    public let appToken: String

    public init(userKey: String, appToken: String) {
        self.userKey = userKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pushover user/group keys and application tokens are 30 alphanumeric characters.
    public static func isWellFormed(_ value: String) -> Bool {
        value.count == 30 && value.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    public func validate() throws {
        if userKey.isEmpty || appToken.isEmpty { throw PushoverError.missingCredentials }
        if !Self.isWellFormed(userKey) { throw PushoverError.malformedCredentials(field: "User Key") }
        if !Self.isWellFormed(appToken) { throw PushoverError.malformedCredentials(field: "Application Token") }
    }
}

public struct PushoverMessage: Sendable, Equatable {
    public static let allowedPriorities = -2...1

    public var title: String
    public var message: String
    public var priority: Int
    /// `false` sends the silent `none` sound; `true` uses the user's default sound.
    public var playSound: Bool
    public var url: URL?
    public var urlTitle: String?

    public init(title: String, message: String, priority: Int = 0, playSound: Bool = true, url: URL? = nil, urlTitle: String? = nil) {
        self.title = title
        self.message = message
        self.priority = min(max(priority, Self.allowedPriorities.lowerBound), Self.allowedPriorities.upperBound)
        self.playSound = playSound
        self.url = url
        self.urlTitle = urlTitle
    }
}

/// Errors are phrased for display in Settings and never contain credentials.
public enum PushoverError: Error, Equatable, LocalizedError {
    case missingCredentials
    case malformedCredentials(field: String)
    case network(String)
    case http(status: Int, messages: [String])
    case api(messages: [String])
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Pushover is not configured. Enter your User Key and Application Token."
        case .malformedCredentials(let field):
            return "The Pushover \(field) looks malformed. It should be 30 letters and digits."
        case .network(let description):
            return "Could not reach Pushover: \(description)"
        case .http(let status, let messages):
            let detail = messages.isEmpty ? "" : " — " + messages.joined(separator: "; ")
            return "Pushover returned HTTP \(status)\(detail)"
        case .api(let messages):
            return "Pushover rejected the message: " + (messages.isEmpty ? "unknown error" : messages.joined(separator: "; "))
        case .invalidResponse:
            return "Pushover returned an unexpected response."
        }
    }
}

/// Minimal client for `POST /1/messages.json`.
public struct PushoverClient: Sendable {
    public static let defaultEndpoint = URL(string: "https://api.pushover.net/1/messages.json")!

    private let transport: HTTPTransport
    private let endpoint: URL

    public init(transport: HTTPTransport = URLSessionTransport(), endpoint: URL = PushoverClient.defaultEndpoint) {
        self.transport = transport
        self.endpoint = endpoint
    }

    /// Sends `message` and returns Pushover's request identifier.
    @discardableResult
    public func send(_ message: PushoverMessage, credentials: PushoverCredentials) async throws -> String {
        try credentials.validate()
        let request = makeRequest(message, credentials: credentials)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as PushoverError {
            throw error
        } catch let error as URLError {
            throw PushoverError.network(Self.describe(error))
        } catch {
            throw PushoverError.network("The request failed.")
        }

        let body = try? JSONDecoder().decode(ResponseBody.self, from: data)
        let messages = Self.sanitize(body?.errors ?? [], credentials: credentials)
        guard (200..<300).contains(response.statusCode) else {
            throw PushoverError.http(status: response.statusCode, messages: messages)
        }
        guard let body else { throw PushoverError.invalidResponse }
        guard body.status == 1 else { throw PushoverError.api(messages: messages) }
        return body.request ?? ""
    }

    public func makeRequest(_ message: PushoverMessage, credentials: PushoverCredentials) -> URLRequest {
        var fields: [(String, String)] = [
            ("token", credentials.appToken),
            ("user", credentials.userKey),
            ("title", message.title),
            ("message", message.message.isEmpty ? " " : message.message),
            ("priority", String(message.priority)),
        ]
        if !message.playSound { fields.append(("sound", "none")) }
        if let url = message.url {
            fields.append(("url", url.absoluteString))
            fields.append(("url_title", message.urlTitle ?? "Open session"))
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return request
    }

    static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        return fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }

    /// Defensive: strip anything resembling the credentials from server-provided messages.
    static func sanitize(_ messages: [String], credentials: PushoverCredentials) -> [String] {
        messages.map { message in
            var result = message
            for secret in [credentials.userKey, credentials.appToken] where !secret.isEmpty {
                result = result.replacingOccurrences(of: secret, with: "•••")
            }
            return TextSanitizer.truncate(result, to: 200)
        }
    }

    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "You appear to be offline."
        case .timedOut: return "The request timed out."
        case .cannotFindHost, .dnsLookupFailed: return "The server could not be found."
        case .cannotConnectToHost: return "Could not connect to the server."
        case .secureConnectionFailed, .serverCertificateUntrusted: return "A secure connection could not be established."
        default: return "Network error (\(error.code.rawValue))."
        }
    }

    private struct ResponseBody: Decodable {
        let status: Int
        let request: String?
        let errors: [String]?
    }
}
