import Foundation

/// Remembers whether rows show the public or the local address.
enum AddressModeStore {
    private static let key = "addressMode"

    static func load() -> AddressMode {
        guard
            let raw = UserDefaults.standard.string(forKey: key),
            let mode = AddressMode(rawValue: raw)
        else { return .publicAddress }
        return mode
    }

    static func save(_ mode: AddressMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
    }
}
