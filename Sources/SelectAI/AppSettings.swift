import Foundation
import Security

struct APIConfiguration {
    var baseURL: String
    var model: String
    var apiKey: String
    var outputLanguage: String

    var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard
    private static let service = "com.selectai.mac.apikey"
    private static let account = "default"

    static var isEnabled: Bool {
        get {
            if defaults.object(forKey: "selectionToolEnabled") == nil { return true }
            return defaults.bool(forKey: "selectionToolEnabled")
        }
        set { defaults.set(newValue, forKey: "selectionToolEnabled") }
    }

    static var clipboardHistoryEnabled: Bool {
        get {
            if defaults.object(forKey: "clipboardHistoryEnabled") == nil { return true }
            return defaults.bool(forKey: "clipboardHistoryEnabled")
        }
        set { defaults.set(newValue, forKey: "clipboardHistoryEnabled") }
    }

    static var clipboardHistoryLimit: Int {
        get {
            let stored = defaults.integer(forKey: "clipboardHistoryLimit")
            return clampedClipboardLimit(stored == 0 ? 200 : stored)
        }
        set { defaults.set(clampedClipboardLimit(newValue), forKey: "clipboardHistoryLimit") }
    }

    static var clipboardShortcut: ClipboardShortcut {
        get {
            guard let data = defaults.data(forKey: "clipboardShortcut"),
                  let value = try? JSONDecoder().decode(ClipboardShortcut.self, from: data) else {
                return .defaultValue
            }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: "clipboardShortcut")
        }
    }

    static func clampedClipboardLimit(_ value: Int) -> Int {
        min(max(value, 1), 1_000)
    }

    static var configuration: APIConfiguration {
        get {
            APIConfiguration(
                baseURL: defaults.string(forKey: "apiBaseURL") ?? "https://api.openai.com/v1",
                model: defaults.string(forKey: "apiModel") ?? "gpt-4.1-mini",
                apiKey: KeychainStore.read(service: service, account: account) ?? "",
                outputLanguage: defaults.string(forKey: "outputLanguage") ?? "简体中文（普通话）"
            )
        }
        set {
            defaults.set(newValue.baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "apiBaseURL")
            defaults.set(newValue.model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "apiModel")
            defaults.set(newValue.outputLanguage, forKey: "outputLanguage")
            KeychainStore.save(newValue.apiKey, service: service, account: account)
        }
    }
}

enum KeychainStore {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
