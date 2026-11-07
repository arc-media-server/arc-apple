import ArcKit
import Foundation
import Security

/// The device token, kept in the Keychain (never in UserDefaults or logs). The app and its Top
/// Shelf extension share it: both list the same keychain access group first in their
/// entitlements, so the item lands in that group and both can read it.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.arcmediaserver.apple",
        kSecAttrAccount as String: "device-token",
    ]

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess { ArcLog.shared.warn("saving the sign-in failed: \(status)") }
    }

    /// Saves the token again, so one kept before the Top Shelf existed moves into the shared group.
    static func share() {
        guard let token = read() else { return }
        save(token)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
