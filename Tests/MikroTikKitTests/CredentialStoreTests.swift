import Foundation
import MikroTikKit

/// These touch the real login Keychain, so every test restores the state it
/// found rather than assuming it started empty.
func runCredentialStoreTests() {
    suite("Credential store") {
        let saved = CredentialStore.load()
        defer {
            CredentialStore.clear()
            if !saved.isEmpty { try? CredentialStore.save(saved) }
        }

        test("round-trips through the Keychain") {
            CredentialStore.clear()
            let secret = "probe-\(UUID().uuidString)"
            try CredentialStore.save(RouterCredentials(username: "probe", password: secret))

            let loaded = CredentialStore.load()
            assertEqual(loaded.username, "probe")
            assertEqual(loaded.password, secret)
        }

        test("reports empty when nothing is stored") {
            CredentialStore.clear()
            let loaded = CredentialStore.load()
            assertTrue(loaded.isEmpty, "no password should be invented")
            assertEqual(loaded.username, "admin", "RouterOS default account name")
        }

        test("overwrites rather than duplicating an existing item") {
            CredentialStore.clear()
            try CredentialStore.save(RouterCredentials(username: "first", password: "one"))
            try CredentialStore.save(RouterCredentials(username: "second", password: "two"))

            let loaded = CredentialStore.load()
            assertEqual(loaded.username, "second")
            assertEqual(loaded.password, "two")
        }

        test("imports a legacy plaintext file and deletes it") {
            CredentialStore.clear()
            let url = CredentialStore.legacyFileURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let json = #"{"username":"legacy","password":"legacy-pass"}"#
            try Data(json.utf8).write(to: url)

            let loaded = CredentialStore.load()
            assertEqual(loaded.username, "legacy")
            assertEqual(loaded.password, "legacy-pass")
            assertFalse(
                FileManager.default.fileExists(atPath: url.path),
                "the cleartext file must not survive the import"
            )
        }

        test("a legacy file never overwrites a Keychain entry") {
            CredentialStore.clear()
            try CredentialStore.save(RouterCredentials(username: "current", password: "keep-me"))

            let url = CredentialStore.legacyFileURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(#"{"username":"stale","password":"stale-pass"}"#.utf8).write(to: url)

            let loaded = CredentialStore.load()
            assertEqual(loaded.password, "keep-me")
            assertFalse(FileManager.default.fileExists(atPath: url.path))
        }

        test("the environment wins over the Keychain") {
            // Documents the documented precedence without mutating the
            // process environment, which cannot be undone reliably.
            assertEqual(CredentialStore.usernameEnvironmentKey, "MIKROTIK_USERNAME")
            assertEqual(CredentialStore.passwordEnvironmentKey, "MIKROTIK_PASSWORD")
        }
    }
}
