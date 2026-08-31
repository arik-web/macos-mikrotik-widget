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

    /// Resolves the public address the ISP presents for one uplink, by asking
    /// the router to fetch an echo service with that interface's own address as
    /// the source.
    ///
    /// `srcAddress` only fixes the source, not the egress: the router still
    /// routes by destination, so on a policy-routed setup an output-chain
    /// `mark-routing` rule keyed on that source address is what actually sends
    /// the request out of the intended link. Without one, every uplink reports
    /// whichever public address the default route happens to use. See
    /// `docs/public-ip.md`.
    public func publicAddress(
        sourceAddress: String,
        echoURL: String,
        timeout: TimeInterval = 15
    ) async throws -> String? {
        let records = try await post(
            "tool/fetch",
            body: [
                "url": echoURL,
                "mode": echoURL.hasPrefix("https") ? "https" : "http",
                "src-address": sourceAddress,
                "output": "user",
                "as-value": "true",
            ],
            timeout: timeout
        )
        // The call streams progress rows; the finished one carries the body.
        for record in records.reversed() {
            guard let data = record["data"]?.stringValue else { continue }
            let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
            if IPv4.parse(trimmed) != nil { return trimmed }
        }
        return nil
    }

    // MARK: - DHCP leases

    public func leases() async throws -> [DHCPLease] {
        try await get("ip/dhcp-server/lease").compactMap(DHCPLease.init(record:))
    }

    /// Turns a lease the server handed out into a reservation, so the device
    /// keeps this address. RouterOS assigns a new item id, so callers should
    /// re-read the list afterwards rather than reusing `id`.
    public func makeLeaseStatic(id: String) async throws {
        _ = try await post("ip/dhcp-server/lease/make-static", body: [".id": id], timeout: 10)
    }

    /// Deletes a lease. Used to drop a reservation back to dynamic: RouterOS
    /// has no "make-dynamic", and the client is handed a fresh dynamic lease
    /// when it next renews.
    public func removeLease(id: String) async throws {
        _ = try await send("DELETE", path: "ip/dhcp-server/lease/\(id)", body: [:], timeout: 10)
    }

    // MARK: - Address lists and route pinning

    public func addressListEntries() async throws -> [AddressListEntry] {
        try await get("ip/firewall/address-list").compactMap(AddressListEntry.init(record:))
    }

    public func addAddressListEntry(
        list: String,
        address: String,
        comment: String? = nil
    ) async throws {
        var body = ["list": list, "address": address]
        if let comment, !comment.isEmpty { body["comment"] = comment }
        _ = try await send("PUT", path: "ip/firewall/address-list", body: body, timeout: 10)
    }

    public func removeAddressListEntry(id: String) async throws {
        _ = try await send("DELETE", path: "ip/firewall/address-list/\(id)", body: [:], timeout: 10)
    }

    /// Drops tracked connections for one source address.
    ///
    /// Connection marks are assigned once, on the first packet, so an existing
    /// connection keeps riding the old uplink until it dies. Without this a
    /// route change looks like it did nothing for minutes. Returns how many
    /// entries were cleared.
    @discardableResult
    public func flushConnections(sourceAddress: String) async throws -> Int {
        let connections = try await get("ip/firewall/connection", timeout: 20)
        let ids = connections.compactMap { record -> String? in
            guard
                let id = record.string(".id"),
                let source = record.string("src-address"),
                source.split(separator: ":").first.map(String.init) == sourceAddress
            else { return nil }
            return id
        }
        for id in ids {
            // A connection can expire between the read and the delete; that is
            // the desired end state either way, so a failure is not fatal.
            _ = try? await send(
                "DELETE",
                path: "ip/firewall/connection/\(id)",
                body: [:],
                timeout: 10
            )
        }
        return ids.count
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
        // RouterOS stalls on a DELETE that carries a body, so an empty payload
        // must mean no body at all rather than `{}`. Sending one made every
        // delete hang and silently do nothing.
        if Self.carriesBody(body) {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request)
    }

    /// Whether a request should carry a JSON payload at all.
    ///
    /// RouterOS stalls on a DELETE that arrives with a body, so an empty
    /// dictionary has to mean "no body", not `{}`. Sending `{}` made every
    /// delete — address-list entries, lease reservations, connection flushes —
    /// hang and silently do nothing.
    public static func carriesBody(_ body: [String: String]) -> Bool { !body.isEmpty }

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

        if let records = Self.decodeRecords(data) { return records }

        // A DHCP client can register any bytes it likes as its host-name, so a
        // lease list routinely carries sequences that are not valid UTF-8.
        // JSONDecoder rejects the whole payload over one bad byte; re-encoding
        // swaps them for U+FFFD and costs nothing on the common path, because
        // it only runs after a decode has already failed.
        if let repaired = Self.repairingUTF8(data), let records = Self.decodeRecords(repaired) {
            return records
        }

        let decoder = JSONDecoder()
        if let single = try? decoder.decode(RouterRecord.self, from: data) {
            if let message = single.string("message") ?? single.string("detail") {
                throw RouterError.httpStatus(single.int("error") ?? 0, message)
            }
            return [single]
        }
        let preview = String(decoding: data.prefix(120), as: UTF8.self)
        throw RouterError.decoding(preview)
    }

    private static func decodeRecords(_ data: Data) -> [RouterRecord]? {
        try? JSONDecoder().decode([RouterRecord].self, from: data)
    }

    /// Returns `data` with invalid UTF-8 replaced, or nil when it was already
    /// valid and a retry would be pointless.
    public static func repairingUTF8(_ data: Data) -> Data? {
        let repaired = Data(String(decoding: data, as: UTF8.self).utf8)
        return repaired == data ? nil : repaired
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
