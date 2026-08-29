import Foundation

public struct RouterCredentials: Codable, Equatable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Reads and writes the router login.
///
/// Resolution order is environment → on-disk store → empty. The
/// on-disk copy lives beside the shared snapshot with `0600` permissions so
/// the widget extension can authenticate on its own when the app is not
/// running. Swap this for a Keychain-backed store before distributing a
/// signed build; a file is used here because an unsigned, frequently
/// rebuilt binary triggers a Keychain prompt on every launch.
public enum CredentialStore {
    public static let usernameEnvironmentKey = "MIKROTIK_USERNAME"
    public static let passwordEnvironmentKey = "MIKROTIK_PASSWORD"

    /// RouterOS ships with `admin` as the account name. There is deliberately
    /// no default password: an empty one sends the operator to Settings rather
    /// than silently trying a guess against their router.
    static let defaultUsername = "admin"

    static var fileURL: URL {
        SharedStore.directory.appendingPathComponent("credentials.json")
    }

    public static func load() -> RouterCredentials {
        let environment = ProcessInfo.processInfo.environment
        if let password = environment[passwordEnvironmentKey], !password.isEmpty {
            return RouterCredentials(
                username: environment[usernameEnvironmentKey] ?? defaultUsername,
                password: password
            )
        }

        if
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode(RouterCredentials.self, from: data),
            !stored.password.isEmpty
        {
            return stored
        }

        return RouterCredentials(username: defaultUsername, password: "")
    }

    public static func save(_ credentials: RouterCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let url = fileURL
        try SharedStore.prepareDirectory()
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
