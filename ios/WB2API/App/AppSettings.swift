import Foundation

/// Persisted connection settings. The admin key is a credential: it lives in the
/// Keychain, never in UserDefaults, so a stolen backup does not leak it.
final class AppSettings: ObservableObject {
    private enum Keys {
        static let serverURL = "wb2api.serverURL"
        static let adminKeyAccount = "wb2api.adminKey"
        static let allowInsecure = "wb2api.allowInsecure"
    }

    @Published var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Keys.serverURL) }
    }
    @Published var adminKey: String {
        didSet { Keychain.set(adminKey, account: Keys.adminKeyAccount) }
    }
    @Published var allowInsecureHTTP: Bool {
        didSet { UserDefaults.standard.set(allowInsecureHTTP, forKey: Keys.allowInsecure) }
    }

    init() {
        serverURLString = UserDefaults.standard.string(forKey: Keys.serverURL) ?? ""
        adminKey = Keychain.get(account: Keys.adminKeyAccount) ?? ""
        allowInsecureHTTP = UserDefaults.standard.bool(forKey: Keys.allowInsecure)
    }

    /// Normalised base URL, or nil when the input cannot be parsed.
    var baseURL: URL? {
        var raw = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") {
            raw = (allowInsecureHTTP ? "http://" : "https://") + raw
        }
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        // The console mounts at the server root; a trailing slash keeps
        // relative resource paths (style.css, app.js) resolving correctly.
        components.path = components.path.hasSuffix("/") ? components.path : components.path + "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    var isConfigured: Bool { baseURL != nil }

    /// URL that logs the console in without putting the key in history.
    /// Mirrors console/web/desktop-key.js behaviour: the key is only honoured
    /// for loopback hosts there, but our loader strips it from the address bar
    /// before any page script runs, so remote hosts are safe too.
    var loginURL: URL? {
        guard let base = baseURL, !adminKey.isEmpty else { return baseURL }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        components.queryItems = [URLQueryItem(name: "admin_key", value: adminKey)]
        return components.url
    }

    func clearCredentials() {
        adminKey = ""
        serverURLString = ""
        Keychain.delete(account: Keys.adminKeyAccount)
    }
}

enum Keychain {
    private static let service = "com.workbuddy2api.mobile"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base = query(account: account)
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        var attributes = query(account: account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    static func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}
