import Foundation

/// Parses `KEY=value, KEY2=value2` settings text, dropping malformed entries
/// rather than failing the whole save.
public enum SettingsPairParser {
    public static func parse(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let halves = pair.split(separator: "=", maxSplits: 1)
            guard halves.count == 2 else { continue }
            let key = halves[0].trimmingCharacters(in: .whitespaces)
            let value = halves[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}
