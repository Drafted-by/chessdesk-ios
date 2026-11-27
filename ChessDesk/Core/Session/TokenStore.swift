import Foundation
import Security

/// Where the app API token lives: the Keychain, this device only, readable
/// after the first unlock so a background refresh can use it.
nonisolated protocol TokenStoring: Sendable {
    func read() -> String?
    func write(_ token: String?)
}

nonisolated struct KeychainTokenStore: TokenStoring {
    /// One token per server, so switching server in Debug never sends a token
    /// to a host that did not issue it.
    let account: String
    private let service = "app.chessdesk.ios.api-token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let token else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}

/// For previews and tests.
nonisolated final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(_ token: String? = nil) { self.token = token }

    func read() -> String? { lock.withLock { token } }
    func write(_ token: String?) { lock.withLock { self.token = token } }
}
