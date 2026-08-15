import Foundation
import Security

/// Configuration de l'app : valeurs injectées à la compilation (Info.plist, via
/// les secrets GitHub Actions) avec possibilité de surcharge dans le trousseau
/// (écran de configuration dans l'app).
enum AppConfig {
    private static let service = "com.paj.drive"

    // MARK: - Lecture

    static var token: String {
        keychainGet("token") ?? infoValue("KDriveAPIToken") ?? ""
    }

    static var driveId: Int {
        Int(keychainGet("driveId") ?? "") ?? Int(infoValue("KDriveDriveId") ?? "") ?? 0
    }

    static var accessCode: String {
        keychainGet("accessCode") ?? infoValue("APPAccessCode") ?? ""
    }

    static var rootDirectoryId: Int {
        Int(keychainGet("rootId") ?? "") ?? 1
    }

    static var isConfigured: Bool {
        !token.isEmpty && driveId > 0
    }

    // MARK: - Écriture / réinitialisation

    static func save(token: String, driveId: String, accessCode: String, rootId: String) {
        keychainSet(token, forKey: "token")
        keychainSet(driveId, forKey: "driveId")
        keychainSet(accessCode, forKey: "accessCode")
        keychainSet(rootId, forKey: "rootId")
    }

    static func reset() {
        keychainSet(nil, forKey: "token")
        keychainSet(nil, forKey: "driveId")
        keychainSet(nil, forKey: "accessCode")
        keychainSet(nil, forKey: "rootId")
    }

    // MARK: - Privé

    private static func infoValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func keychainGet(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainSet(_ value: String?, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
