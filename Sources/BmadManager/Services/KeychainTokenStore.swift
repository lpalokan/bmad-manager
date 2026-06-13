import Foundation
import Security

/// Stores the skills-repo GitHub token. Abstracted behind a protocol so the
/// sync flow can be exercised with an in-memory fake instead of touching the
/// real Keychain in tests.
protocol TokenStore {
    /// The stored token, or `nil` when none is set.
    func loadToken() -> String?
    /// Persists `token`. An empty/whitespace value clears any stored token.
    func saveToken(_ token: String) throws
    /// Removes any stored token.
    func clearToken() throws
}

enum TokenStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain error: \(message ?? "OSStatus \(status)")"
        }
    }
}

/// `TokenStore` backed by the macOS Keychain (a generic-password item). The
/// token is never written to `settings.json`; only this Keychain entry under
/// the `bmad-manager` / `skills-repo-token` service/account pair holds it.
struct KeychainTokenStore: TokenStore {
    let service: String
    let account: String

    init(service: String = "bmad-manager", account: String = "skills-repo-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            return nil
        }
        return token
    }

    func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clearToken()
            return
        }
        let data = Data(trimmed.utf8)

        // Update in place if the item already exists, otherwise add it.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw TokenStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TokenStoreError.keychain(addStatus)
        }
    }

    func clearToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychain(status)
        }
    }
}
