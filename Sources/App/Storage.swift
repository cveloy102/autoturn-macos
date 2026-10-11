import Foundation
import Security
import Darwin

enum Storage {
    static let service = "ru.hl100.autoturn.settings"
    static func load() throws -> Settings {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"settings-v1", kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound { return Settings() }
        guard code == errSecSuccess, let data = result as? Data else { throw AppError.message("Не удалось прочитать профили из Keychain") }
        return try JSONDecoder().decode(Settings.self, from: data)
    }
    static func save(_ settings: Settings) throws {
        let data = try JSONEncoder().encode(settings)
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"settings-v1"]
        var code = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if code == errSecItemNotFound { var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly; code = SecItemAdd(item as CFDictionary, nil) }
        guard code == errSecSuccess else { throw AppError.message("Не удалось сохранить профили в Keychain") }
    }
    static func resolve(_ host: String) throws -> String {
        if Profile.isIP(host) { return host }
        var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_DGRAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { throw AppError.message("Не удалось определить IP VPN-сервера. Повтори импорт при работающем интернете.") }
        defer { freeaddrinfo(first) }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { throw AppError.message("IP сервера недоступен") }
        return String(cString: buffer)
    }
    static var loginDirectory:URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents") }
    static func setLaunchAtLogin(_ enabled:Bool) throws { try LoginRegistration.set(enabled,in:loginDirectory) }
    static func restoreLaunchAtLogin(_ settings:inout Settings) throws {
        // An existing valid registration records the user's prior choice. Explicit Off removes it.
        let enabled = settings.launchAtLogin || LoginRegistration.existing(in:loginDirectory)
        try setLaunchAtLogin(enabled)
        if enabled != settings.launchAtLogin {
            settings.launchAtLogin = enabled
            try save(settings)
        }
    }

}

final class ServiceClient {
    let queue = DispatchQueue(label: "ru.hl100.autoturn.client")
    func send(_ request: RPCRequest, completion: @escaping (Result<RPCResponse, Error>) -> Void) {
        queue.async { let result = Result { try IPC.request(request) }; DispatchQueue.main.async { completion(result) } }
    }
}
