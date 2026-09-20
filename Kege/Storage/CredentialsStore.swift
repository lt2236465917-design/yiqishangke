import Foundation
import Security

struct SchoolCredentials: Equatable, Sendable {
    var username: String
    var password: String

    var isComplete: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var debugDescription: String {
        "SchoolCredentials(username: \(Redaction.username(username)), password: <redacted>)"
    }
}

struct AIVisionConfiguration: Equatable, Sendable {
    var apiKey: String
    var baseURL: String
    var model: String

    static let deepseekBaseURL = "https://api.deepseek.com"
    static let deepseekModel = "deepseek-flash"

    var isUsable: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum CredentialsStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "钥匙串操作失败（\(status)）"
        case .invalidPayload:
            "钥匙串数据损坏"
        }
    }
}

/// School credentials and optional developer vision key — Keychain only, this device, not iCloud.
final class CredentialsStore: @unchecked Sendable {
    static let shared = CredentialsStore()

    private let service = "cn.yiqishangke.Kege"
    private let schoolAccount = "school-portal"
    private let aiAccount = "developer-ai-vision"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: School credentials CRUD

    func loadSchoolCredentials() throws -> SchoolCredentials? {
        guard let data = try read(account: schoolAccount) else { return nil }
        let payload = try decoder.decode(SchoolPayload.self, from: data)
        return SchoolCredentials(username: payload.username, password: payload.password)
    }

    func saveSchoolCredentials(_ credentials: SchoolCredentials) throws {
        let payload = SchoolPayload(username: credentials.username, password: credentials.password)
        try write(account: schoolAccount, data: encoder.encode(payload))
        SafeLog.info("School credentials saved for \(Redaction.username(credentials.username))")
    }

    func deleteSchoolCredentials() throws {
        try delete(account: schoolAccount)
        SafeLog.info("School credentials deleted")
    }

    func hasSchoolCredentials() -> Bool {
        (try? loadSchoolCredentials()?.isComplete) ?? false
    }

    // MARK: Developer AI key (never committed; never sent with school credentials)

    func loadAIConfiguration() throws -> AIVisionConfiguration? {
        guard let data = try read(account: aiAccount) else { return nil }
        let payload = try decoder.decode(AIPayload.self, from: data)
        return AIVisionConfiguration(apiKey: payload.apiKey, baseURL: payload.baseURL, model: payload.model)
    }

    func saveAIConfiguration(_ configuration: AIVisionConfiguration) throws {
        let payload = AIPayload(
            apiKey: configuration.apiKey,
            baseURL: configuration.baseURL,
            model: configuration.model
        )
        try write(account: aiAccount, data: encoder.encode(payload))
        SafeLog.info("Developer AI vision key saved (redacted)")
    }

    func deleteAIConfiguration() throws {
        try delete(account: aiAccount)
        SafeLog.info("Developer AI vision key deleted")
    }

    /// Optional Xcode scheme / Secrets.local.plist inject. File is gitignored.
    func ingestLocalSecretsFileIfPresent() {
        let candidates = [
            Bundle.main.url(forResource: "Secrets.local", withExtension: "plist"),
            Bundle.main.url(forResource: "Secrets", withExtension: "plist")
        ].compactMap { $0 }
        for url in candidates {
            guard let plist = NSDictionary(contentsOf: url) else { continue }
            let key = (plist["AI_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else { continue }
            let base = (plist["AI_BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (plist["AI_MODEL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let config = AIVisionConfiguration(
                apiKey: key,
                baseURL: (base?.isEmpty == false ? base! : AIVisionConfiguration.deepseekBaseURL),
                model: (model?.isEmpty == false ? model! : AIVisionConfiguration.deepseekModel)
            )
            try? saveAIConfiguration(config)
            SafeLog.info("Ingested developer AI key from local plist (not logged)")
            return
        }
    }

    // MARK: Keychain primitives

    private func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialsStoreError.unexpectedStatus(status) }
        guard let data = item as? Data else { throw CredentialsStoreError.invalidPayload }
        return data
    }

    private func write(account: String, data: Data) throws {
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialsStoreError.unexpectedStatus(status) }
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialsStoreError.unexpectedStatus(status)
        }
    }
}

private struct SchoolPayload: Codable {
    var username: String
    var password: String
}

private struct AIPayload: Codable {
    var apiKey: String
    var baseURL: String
    var model: String
}
