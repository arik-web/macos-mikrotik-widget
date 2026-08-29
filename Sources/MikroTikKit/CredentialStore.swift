import Foundation
import Security

public struct RouterCredentials: Codable, Equatable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    public var isEmpty: Bool { password.isEmpty }
}

/// Reads and writes the router login, keeping the password in the Keychain.
///
/// Resolution order is environment → Keychain → empty. Nothing is ever written
/// to a plaintext file; a `credentials.json` left by an older build is imported
/// once and then deleted.
///
/// ## Sharing with the widget extension
///
/// The widget polls the router itself when the app is not running and the
/// shared snapshot has gone stale. Reaching the same Keychain item from both
/// processes needs a `keychain-access-groups` entitlement, and that requires a
/// real Apple Developer Team ID — an ad-hoc signed build has none. So:
///
/// - **Signed build with a team:** set `accessGroup` to
///   `<TeamID>.io.github.macosmikrotikwidget` in both entitlements files and
///   here, and the widget authenticates on its own.
/// - **Ad-hoc build (the default here):** `accessGroup` stays nil. The app
///   reaches the item, the widget does not, and the widget falls back to the
///   snapshot the app writes every few seconds. That covers everything except
///   a refresh that lands while the app is closed, which shows the last known
///   values marked unreachable.
public enum CredentialStore {
    public static let usernameEnvironmentKey = "MIKROTIK_USERNAME"
    public static let passwordEnvironmentKey = "MIKROTIK_PASSWORD"

    /// RouterOS ships with `admin` as the account name. There is deliberately
    /// no default password: an empty one sends the operator to Settings rather
    /// than silently trying a guess against their router.
    static let defaultUsername = "admin"

    static let service = "io.github.macosmikrotikwidget.router"
    static let account = "router-credentials"

    /// Set to `<TeamID>.<bundle-id>` in a signed build to share the item with
    /// the widget extension. Must match `keychain-access-groups` in both
    /// entitlements files.
    static let accessGroup: String? = nil

    // MARK: - Public API

    public static func load() -> RouterCredentials {
        let environment = ProcessInfo.processInfo.environment
        if let password = environment[passwordEnvironmentKey], !password.isEmpty {
            return RouterCredentials(
                username: environment[usernameEnvironmentKey] ?? defaultUsername,
                password: password
            )
        }

        importLegacyFileIfPresent()

        if let stored = readFromKeychain(), !stored.password.isEmpty {
            return stored
        }

        return RouterCredentials(username: defaultUsername, password: "")
    }

    public static func save(_ credentials: RouterCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        // SecItemAdd fails on an existing item, so replace rather than branch
        // on a prior lookup: two processes can race between check and write.
        SecItemDelete(baseQuery() as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    /// Removes the stored login. Used when the operator clears the password.
    public static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Keychain

    public enum KeychainError: LocalizedError {
        case unhandled(status: OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                let detail = SecCopyErrorMessageString(status, nil) as String?
                return "Keychain error \(status)" + (detail.map { ": \($0)" } ?? "")
            }
        }
    }

    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    static func readFromKeychain() -> RouterCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(RouterCredentials.self, from: data)
    }

    // MARK: - Migration off the old plaintext file

    public static var legacyFileURL: URL {
        SharedStore.directory.appendingPathComponent("credentials.json")
    }

    /// Imports and removes a `credentials.json` written by an earlier build, so
    /// the password stops living in cleartext on disk.
    static func importLegacyFileIfPresent() {
        let url = legacyFileURL
        guard
            let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode(RouterCredentials.self, from: data)
        else { return }

        if !stored.password.isEmpty, readFromKeychain() == nil {
            try? save(stored)
        }
        try? FileManager.default.removeItem(at: url)
    }
}
