import Foundation

public enum RouterError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case httpStatus(Int, String?)
    case transport(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The router address is not a valid URL."
        case .unauthorized:
            return "Login rejected by the router (check username and password)."
        case .httpStatus(let code, let message):
            return message.map { "Router returned HTTP \(code): \($0)" } ?? "Router returned HTTP \(code)."
        case .transport(let message):
            return message
        case .decoding(let message):
            return "Unexpected response from the router: \(message)"
        }
    }

    /// True when retrying the same request is unlikely to help.
    public var isFatal: Bool {
        switch self {
        case .invalidURL, .unauthorized: return true
        default: return false
        }
    }
}

/// Minimal RouterOS 7 REST client built on URLSession, no dependencies.
public actor RouterClient {
    private let config: RouterConfig
    private let credentials: RouterCredentials
    private let session: URLSession

    public init(config: RouterConfig, credentials: RouterCredentials, session: URLSession? = nil) {
        self.config = config
        self.credentials = credentials
        self.session = session ?? RouterClient.makeSession(timeout: max(config.pollInterval * 2, 5))
    }

    public static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }

    // MARK: - Endpoints

    public func interfaces() async throws -> [RouterInterface] {
        try await get("interface").compactMap(RouterInterface.init(record:))
    }

    public func addresses() async throws -> [RouterAddress] {
        try await get("ip/address").compactMap(RouterAddress.init(record:))
    }

    public func routes() async throws -> [RouterRoute] {
        try await get("ip/route").compactMap(RouterRoute.init(record:))
    }

    /// Pings `address`, optionally forcing the packets out of `interfaceName`.
    public func ping(
        address: String,
        viaInterface interfaceName: String? = nil,
        count: Int = 3
    ) async throws -> PingOutcome {
        var body = ["address": address, "count": String(count)]
        if let interfaceName {
            body["interface"] = interfaceName
        }
        // Each echo request costs about a second, plus router-side overhead.
        let records = try await post("tool/ping", body: body, timeout: Double(count) + 5)
        return PingOutcome.aggregate(records: records)
    }

    /// Enables or disables one interface.
    ///
    /// `identifier` is the RouterOS item id from `.id` (e.g. `*1`) or the
    /// interface default name (e.g. `ether1`); both address the same row.
    public func setInterfaceDisabled(_ disabled: Bool, interface identifier: String) async throws {
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? identifier
        _ = try await send(
            "PATCH",
            path: "interface/\(encoded)",
            body: ["disabled": disabled ? "true" : "false"],
            timeout: 10
        )
    }

    /// Fetches the three collections a dashboard refresh needs in parallel.
    public func fetchState() async throws -> RouterState {
        async let interfaces = interfaces()
        async let addresses = addresses()
        async let routes = routes()
        return try await RouterState(
            interfaces: interfaces,
            addresses: addresses,
            routes: routes
        )
    }

    // MARK: - Transport

    private func url(for path: String) throws -> URL {
        guard let baseURL = config.baseURL else { throw RouterError.invalidURL }
        return baseURL.appendingPathComponent(path)
    }

    private func authorizedRequest(for url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Sent up front instead of waiting for a 401 challenge, which halves
        // the round trips on a 2-second poll loop.
        let token = Data("\(credentials.username):\(credentials.password)".utf8)
            .base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get(_ path: String, timeout: TimeInterval = 8) async throws -> [RouterRecord] {
        let request = authorizedRequest(for: try url(for: path), timeout: timeout)
        return try await perform(request)
    }

    private func post(
        _ path: String,
        body: [String: String],
        timeout: TimeInterval = 15
    ) async throws -> [RouterRecord] {
        try await send("POST", path: path, body: body, timeout: timeout)
    }

    private func send(
        _ method: String,
        path: String,
        body: [String: String],
        timeout: TimeInterval
    ) async throws -> [RouterRecord] {
        var request = authorizedRequest(for: try url(for: path), timeout: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> [RouterRecord] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw RouterError.transport(Self.describe(error))
        } catch {
            throw RouterError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw RouterError.unauthorized
            }
            throw RouterError.httpStatus(http.statusCode, Self.errorMessage(in: data))
        }

        // A command with no results answers with an empty body.
        guard !data.isEmpty else { return [] }

        let decoder = JSONDecoder()
        if let records = try? decoder.decode([RouterRecord].self, from: data) {
            return records
        }
        if let single = try? decoder.decode(RouterRecord.self, from: data) {
            if let message = single.string("message") ?? single.string("detail") {
                throw RouterError.httpStatus(single.int("error") ?? 0, message)
            }
            return [single]
        }
        let preview = String(decoding: data.prefix(120), as: UTF8.self)
        throw RouterError.decoding(preview)
    }

    private static func errorMessage(in data: Data) -> String? {
        guard
            let record = try? JSONDecoder().decode(RouterRecord.self, from: data)
        else { return nil }
        return record.string("message") ?? record.string("detail")
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "Router did not respond in time."
        case .cannotConnectToHost, .cannotFindHost:
            return "Cannot reach the router. Is it on the same network?"
        case .notConnectedToInternet, .networkConnectionLost:
            return "Network connection lost."
        case .appTransportSecurityRequiresSecureConnection:
            return "Blocked by App Transport Security; allow insecure HTTP for this host."
        default:
            return error.localizedDescription
        }
    }
}

/// The raw collections one refresh pulls from the router.
public struct RouterState: Equatable {
    public let interfaces: [RouterInterface]
    public let addresses: [RouterAddress]
    public let routes: [RouterRoute]

    public init(interfaces: [RouterInterface], addresses: [RouterAddress], routes: [RouterRoute]) {
        self.interfaces = interfaces
        self.addresses = addresses
        self.routes = routes
    }
}
