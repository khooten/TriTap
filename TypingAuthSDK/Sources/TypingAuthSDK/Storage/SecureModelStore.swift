import Foundation
import Security

public final class SecureModelStore {
    private let serviceName: String
    private let appGroupID: String?

    public init(serviceName: String = "com.typingauth.sdk", appGroupID: String? = nil) {
        self.serviceName = serviceName
        self.appGroupID = appGroupID
    }

    // MARK: - Model Storage

    public func saveModel(_ data: Data) throws {
        let url = modelFileURL()
        try data.write(to: url, options: .completeFileProtectionUnlessOpen)

        // Store a hash in Keychain for integrity verification
        let hash = data.hashValue
        try saveToKeychain(key: "model_hash", data: withUnsafeBytes(of: hash) { Data($0) })
    }

    public func loadModel() -> Data? {
        let url = modelFileURL()
        return try? Data(contentsOf: url)
    }

    public func deleteModel() {
        let url = modelFileURL()
        try? FileManager.default.removeItem(at: url)
        deleteFromKeychain(key: "model_hash")
    }

    // MARK: - Passcode Hash Storage

    public func savePasscodeHash(_ hash: Data) throws {
        try saveToKeychain(key: "passcode_hash", data: hash)
    }

    public func loadPasscodeHash() -> Data? {
        loadFromKeychain(key: "passcode_hash")
    }

    public func deletePasscodeHash() {
        deleteFromKeychain(key: "passcode_hash")
    }

    // MARK: - Private

    private func modelFileURL() -> URL {
        let container: URL
        if let appGroupID, let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            container = groupURL
        } else {
            container = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }

        let dir = container.appendingPathComponent("TypingAuthSDK", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("UserModel.mlmodelc")
    }

    private func saveToKeychain(key: String, data: Data) throws {
        deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TypingAuthError.keychainError(status)
        }
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
