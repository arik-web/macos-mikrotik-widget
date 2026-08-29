import Foundation

/// The hand-off point between the app and the widget extension.
///
/// A sandboxed widget cannot see the app's Application Support directory, so
/// the App Group container is preferred. When the build is unsigned (no group
/// container exists) both processes fall back to the same path under the user
/// home, which works for a locally built, non-sandboxed app.
public enum SharedStore {
    public static let appGroupIdentifier = "group.io.github.macosmikrotikwidget"
    static let snapshotFileName = "snapshot.json"

    public static var directory: URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return container
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MikroTikDashboard", isDirectory: true)
    }

    static var snapshotURL: URL {
        directory.appendingPathComponent(snapshotFileName)
    }

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func writeSnapshot(_ snapshot: DashboardSnapshot) throws {
        try prepareDirectory()
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic])
    }

    public static func readSnapshot() -> DashboardSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? decoder.decode(DashboardSnapshot.self, from: data)
    }
}
