import Foundation
import Security
import LocalAuthentication
import Darwin

enum Storage {
    static let service = "ru.hl100.autoturn.settings"
    static let routingStore = RoutingPersistence(directory:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AutoTurn/routing-state"))
    static func canReadWithoutPrompt() -> Bool {
        var result: CFTypeRef?
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"settings-v1",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationContext as String:context]
        let code = SecItemCopyMatching(query as CFDictionary,&result)
        return code == errSecSuccess || code == errSecItemNotFound
    }
    static func load(useIndependentRouting: Bool = true) throws -> Settings {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"settings-v1", kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound {
            var settings = Settings()
            if useIndependentRouting { settings.routing = try routingStore.load(fallback:settings.routing) }
            return settings
        }
        guard code == errSecSuccess, let data = result as? Data else { throw AppError.message("Не удалось прочитать профили из Keychain") }
        var settings = try JSONDecoder().decode(Settings.self, from:data)
        if useIndependentRouting { settings.routing = try routingStore.load(fallback:settings.routing) }
        return settings
    }
    static func save(_ settings: Settings, expectedRouting: RoutingSettings, allowRouteChanges: Bool = false) throws -> RoutingSettings {
        // Commit routes first: a denied Keychain write must not discard a route
        // edit. A retry with the already-committed value is idempotent.
        var value = settings
        value.routing = try routingStore.save(allowRouteChanges ? settings.routing : expectedRouting,expected:expectedRouting)
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"settings-v1"]
        var code = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if code == errSecItemNotFound { var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly; code = SecItemAdd(item as CFDictionary, nil) }
        guard code == errSecSuccess else { throw AppError.message("Не удалось сохранить профили в Keychain") }
        return value.routing
    }
    static func resolve(_ host: String) throws -> String {
        if Profile.isIP(host) {
            guard !Profile.isRoutingFakeIP(host) else { throw AppError.message("Адрес VPN-сервера попал в служебную сеть AutoTurn") }
            return host
        }
        var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_DGRAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { throw AppError.message("Не удалось определить IP VPN-сервера. Повтори импорт при работающем интернете.") }
        defer { freeaddrinfo(first) }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { throw AppError.message("IP сервера недоступен") }
        let address = String(cString:buffer)
        guard !Profile.isRoutingFakeIP(address) else { throw AppError.message("DNS вернул служебный адрес AutoTurn вместо VPN-сервера") }
        return address
    }
    static var loginDirectory:URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents") }
    static func setLaunchAtLogin(_ enabled:Bool) throws { try LoginRegistration.set(enabled,in:loginDirectory) }
    static func restoreLaunchAtLogin(_ settings:inout Settings) throws {
        // An existing valid registration records the user's prior choice. Explicit Off removes it.
        let enabled = settings.launchAtLogin || LoginRegistration.existing(in:loginDirectory)
        try setLaunchAtLogin(enabled)
        if enabled != settings.launchAtLogin {
            settings.launchAtLogin = enabled
            settings.routing = try save(settings,expectedRouting:settings.routing)
        }
    }

}

final class ServiceClient {
    let queue = DispatchQueue(label: "ru.hl100.autoturn.client")
    private let transport: (RPCRequest) throws -> RPCResponse
    init(transport: @escaping (RPCRequest) throws -> RPCResponse = IPC.request) { self.transport = transport }
    // Main-thread mailbox. Collapse unsent profile changes into the latest
    // intent; keep Stop/Recover and other commands as ordering barriers.
    private typealias Completion = (Result<RPCResponse, Error>) -> Void
    private struct Job { var request: RPCRequest; var completions: [Completion] }
    private var commands: [Job] = []
    private var pendingNetwork: Job?
    private var inFlight = false
    func send(_ request: RPCRequest, completion: @escaping (Result<RPCResponse, Error>) -> Void) {
        if request.command == "network" {
            pendingNetwork = Job(request:request,completions:[completion])
        } else if request.command == "configure", commands.last?.request.command == "configure" {
            commands[commands.count-1].request = request
            commands[commands.count-1].completions.append(completion)
        } else {
            commands.append(Job(request:request,completions:[completion]))
        }
        sendNext()
    }
    private func sendNext() {
        guard !inFlight else { return }
        let job: Job
        if !commands.isEmpty { job = commands.removeFirst() }
        else if let sample = pendingNetwork { job = sample; pendingNetwork = nil }
        else { return }
        inFlight = true
        queue.async {
            let result = Result { try self.transport(job.request) }
            DispatchQueue.main.async {
                self.inFlight = false
                for completion in job.completions { completion(result) }
                self.sendNext()
            }
        }
    }
}
