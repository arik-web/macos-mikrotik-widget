import Foundation

/// A single JSON scalar as returned by the RouterOS REST API.
///
/// RouterOS 7 encodes almost every field as a JSON string (`"rx-byte": "1234"`),
/// but some firmware builds emit real numbers or booleans for a handful of
/// keys. Decoding through this enum keeps the parsers tolerant of both shapes.
public enum RouterValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported RouterOS scalar"
            )
        }
    }

    /// Normalised string form. Whole numbers lose their fractional part so that
    /// `"1500"` and `1500.0` both render as `"1500"`.
    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int64(value))
                : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return nil
        }
    }
}

/// One record (a dictionary of columns) from a RouterOS REST collection.
public typealias RouterRecord = [String: RouterValue]

extension Dictionary where Key == String, Value == RouterValue {
    /// Non-empty string for `key`, or `nil`.
    public func string(_ key: String) -> String? {
        guard let value = self[key]?.stringValue, !value.isEmpty else { return nil }
        return value
    }

    public func uint64(_ key: String) -> UInt64? {
        guard let raw = string(key) else { return nil }
        if let value = UInt64(raw) { return value }
        // Negative or fractional counters are meaningless; clamp rather than fail.
        if let value = Double(raw), value > 0 { return UInt64(value) }
        return nil
    }

    public func int(_ key: String) -> Int? {
        guard let raw = string(key) else { return nil }
        return Int(raw) ?? Double(raw).map { Int($0) }
    }

    /// RouterOS booleans arrive as `"true"` / `"false"` / `"yes"` / `"no"`.
    public func flag(_ key: String, default fallback: Bool = false) -> Bool {
        guard let raw = string(key)?.lowercased() else { return fallback }
        switch raw {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return fallback
        }
    }
}
