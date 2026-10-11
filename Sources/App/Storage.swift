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
    static func setLaunchAtLogin(_ enabled: Bool) throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("ru.hl100.autoturn.login.plist")
        if enabled {
            guard let executable = Bundle.main.executableURL?.path else { throw AppError.message("Нет пути приложения") }
            let plist: [String:Any] = ["Label":"ru.hl100.autoturn.login", "ProgramArguments":[executable,"--background"], "RunAtLoad":true, "ProcessType":"Interactive"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file, options: .atomic)
        } else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

final class ServiceClient {
    let queue = DispatchQueue(label: "ru.hl100.autoturn.client")
    func send(_ request: RPCRequest, completion: @escaping (Result<RPCResponse, Error>) -> Void) {
        queue.async { let result = Result { try IPC.request(request) }; DispatchQueue.main.async { completion(result) } }
    }
}
