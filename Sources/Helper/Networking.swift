import Foundation
import SystemConfiguration
import Darwin

protocol TrafficProtection: AnyObject {
    var token: String? { get }
    var active: Bool { get }
    func restoreToken(_ value: String?)
    func apply(tunnel: String?, profile: Profile?) throws
    func remove() throws
    func configureRouting(_ settings: RoutingSettings, physical: PhysicalNetwork) throws
    func setRoutingInterface(_ interface: String?) throws
    func setDirectAddresses(_ addresses: Set<String>) throws
}
extension TrafficProtection {
    func setRoutingInterface(_ interface: String?) throws {}
    func configureRouting(_ settings: RoutingSettings, physical: PhysicalNetwork) throws {}
    func setDirectAddresses(_ addresses: Set<String>) throws {}
}
protocol ManagedTunnel: AnyObject {
    var running: Bool { get }
    var interface: String? { get }
    func recoverJournal()
    func start(_ profile: Profile, physical: PhysicalNetwork, engine: String) throws
    func stop() throws
    func setRoutingMode(_ mode: RoutingMode)
}
extension ManagedTunnel { func setRoutingMode(_ mode: RoutingMode) {} }

struct CommandResult { var code: Int32; var output: String }
enum SystemCommand {
    static func run(_ executable: String, _ arguments: [String], input: String? = nil) throws -> CommandResult {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        if let input = input { let pipe = Pipe(); process.standardInput = pipe; try process.run(); pipe.fileHandleForWriting.write(Data(input.utf8)); pipe.fileHandleForWriting.closeFile() } else { try process.run() }
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return CommandResult(code: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }
    static func checked(_ executable: String, _ args: [String], input: String? = nil) throws -> String {
        let result = try run(executable, args, input: input)
        guard result.code == 0 else { throw AppError.message("Системная операция \(URL(fileURLWithPath: executable).lastPathComponent) не выполнена") }
        return result.output
    }
}

struct PhysicalNetwork {
    var interface: String?
    var gateway: String?
    var service: String?
    var gateway6: String?
    var available: Bool { interface != nil && gateway != nil }
    static func read() -> PhysicalNetwork {
        guard let store = SCDynamicStoreCreate(nil, "AutoTurn" as CFString, nil, nil), let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any], let service = global["PrimaryService"] as? String, let values = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(service)/IPv4" as CFString) as? [String: Any] else { return PhysicalNetwork() }
        let iface = (values["InterfaceName"] as? String) ?? (global["PrimaryInterface"] as? String)
        guard let interface = iface, interface.range(of: "^(en|bridge|eth)[0-9]+$", options: .regularExpression) != nil else { return PhysicalNetwork() }
        let router = values["Router"] as? String
        guard let gateway = router, Profile.isIP(gateway) else { return PhysicalNetwork(interface: interface, gateway: nil, service: service) }
        let v6 = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(service)/IPv6" as CFString) as? [String:Any]
        var gateway6 = v6?["Router"] as? String
        if let g = gateway6, Profile.isIP(g) { if g.lowercased().hasPrefix("fe80:") { gateway6 = g + "%" + interface } } else { gateway6 = nil }
        return PhysicalNetwork(interface: interface, gateway: gateway, service: service,gateway6:gateway6)
    }
}

// An isolated anchor; never flush or replace the system's ruleset.
final class TrafficGuard: TrafficProtection {
    static let anchor = "com.apple/autoturn"
    private(set) var token: String?
    private var lastRules = ""
    private let lock = NSRecursiveLock()
    private var routing = RoutingSettings(), physical = PhysicalNetwork()
    private var coreInterface: String?
    func configureRouting(_ settings: RoutingSettings, physical: PhysicalNetwork) throws { lock.lock(); defer { lock.unlock() }; routing = settings; self.physical = physical }
    func setRoutingInterface(_ interface: String?) throws {
        lock.lock(); defer { lock.unlock() }
        guard interface == nil || interface!.range(of:"^utun[0-9]+$",options:.regularExpression) != nil else { throw AppError.message("Некорректный интерфейс маршрутов") }
        coreInterface = interface
    }
    func setDirectAddresses(_ addresses: Set<String>) throws {}
    var active = false
    func restoreToken(_ value: String?) { if let value = value, UInt64(value) != nil, let result = try? SystemCommand.run("/sbin/pfctl", ["-s", "info"]), result.output.contains("Status: Enabled") { token = value } }
    func apply(tunnel: String?, profile: Profile?) throws {
        lock.lock(); defer { lock.unlock() }
        let root = try SystemCommand.checked("/sbin/pfctl", ["-sr"])
        guard root.contains("anchor \"com.apple/*\"") else { throw AppError.message("В PF нет системного якоря com.apple/*. Автоматически менять правила не будем.") }
        if let tunnel = tunnel, tunnel.range(of: "^utun[0-9]+$", options: .regularExpression) == nil { throw AppError.message("Некорректный интерфейс") }
        var rules = "pass out quick on lo0 all\n"
        if routing.mode == .rules, let core = coreInterface { rules += "pass out quick on \(core) all\n" }
        if let tunnel = tunnel { rules += "pass out quick on \(tunnel) all\n" }
        if let profile = profile, let ip = profile.resolvedIP, Profile.isIP(ip) { rules += "pass out quick \(ip.contains(":") ? "inet6" : "inet") proto udp to \(ip) port \(profile.endpointPort) keep state\n" }
        if routing.mode == .rules, coreInterface != nil, let iface = physical.interface {
            // All ordinary app flows enter the routing TUN. Only the root-owned
            // core can open physical outbound sockets; it has no proxy listener.
            rules += "pass out quick on \(iface) proto { tcp udp } user root keep state\n"
        }
        rules += "pass out quick inet proto udp from any port 68 to any port 67\npass out quick inet6 proto udp from any port 546 to any port 547\npass out quick inet6 proto icmp6 icmp6-type { routersol, neighbrsol, neighbradv }\nblock drop out quick all\n"
        if rules != lastRules || !active {
            _ = try SystemCommand.checked("/sbin/pfctl", ["-a", Self.anchor, "-f", "-"], input: rules)
            if token == nil {
                let result = try SystemCommand.checked("/sbin/pfctl", ["-E"])
                guard let line = result.components(separatedBy: .newlines).first(where: { $0.contains("Token :") }), let value = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces), UInt64(value) != nil else { throw AppError.message("Не удалось получить ссылку на PF") }
                token = value
            }
            // Established direct flows must not bypass new fail-closed rules.
            _ = try SystemCommand.checked("/sbin/pfctl", ["-k", "0.0.0.0/0"])
            _ = try SystemCommand.checked("/sbin/pfctl", ["-k", "::/0"])
            lastRules = rules; active = true
        }
    }
    func remove() throws {
        lock.lock(); defer { lock.unlock() }
        _ = try SystemCommand.checked("/sbin/pfctl", ["-a", Self.anchor, "-F", "rules"])
        active = false; lastRules = ""
        if let token = token { _ = try SystemCommand.checked("/sbin/pfctl", ["-X", token]) }
        token = nil
    }
}

final class Tunnel: ManagedTunnel {
    var process: Process?
    var interface: String?
    private var endpointRoute: (String, String)?
    private var dnsService: String?
    var routingMode: RoutingMode = .all
    func setRoutingMode(_ mode: RoutingMode) { routingMode = mode }
    private var splitRoutes: [(Bool, String)] = []
    private let journal = "/Library/Application Support/AutoTurn/network-journal.json"
    struct Journal: Codable { var endpoint: String?; var gateway: String?; var dnsKey: String? }
    private func saveJournal() { if let data = try? JSONEncoder().encode(Journal(endpoint:endpointRoute?.0,gateway:endpointRoute?.1,dnsKey:dnsService)) { try? data.write(to:URL(fileURLWithPath:journal),options:.atomic); chmod(journal,0o600) } }
    func recoverJournal() {
        guard let data = try? Data(contentsOf:URL(fileURLWithPath:journal)), let saved = try? JSONDecoder().decode(Journal.self,from:data) else { return }
        if let key = saved.dnsKey, key.range(of:"^State:/Network/Service/AutoTurn-[A-Za-z0-9-]+/DNS$",options:.regularExpression) != nil, let store = SCDynamicStoreCreate(nil,"AutoTurnDNS" as CFString,nil,nil) { SCDynamicStoreRemoveValue(store,key as CFString) }
        if let endpoint = saved.endpoint, let gateway = saved.gateway, Profile.isIP(endpoint), Profile.isIP(gateway) { _ = try? SystemCommand.run("/sbin/route",["-n","delete","-host",endpoint,gateway]) }
        try? FileManager.default.removeItem(atPath:journal)
    }
    var running: Bool { process?.isRunning == true }
    func start(_ profile: Profile, physical: PhysicalNetwork, engine: String) throws {
        guard let ip = profile.resolvedIP, Profile.isIP(ip), let gateway = physical.gateway, let primaryService = physical.service else { throw AppError.message("Нет физического маршрута или IP сервера") }
        // IPv6-only physical uplinks will be supported after on-device validation.
        guard !ip.contains(":") else { throw AppError.message("В первой сборке нужен IPv4 Endpoint; IPv6 трафик в туннеле поддерживается") }
        _ = try SystemCommand.checked("/sbin/route", ["-n", "add", "-host", ip, gateway])
        endpointRoute = (ip, gateway)
        saveJournal()
        let nameFile = IPC.directory + "/tunnel-name"
        try? FileManager.default.removeItem(atPath: nameFile)
        let p = Process(); p.executableURL = URL(fileURLWithPath: engine); p.arguments = ["-f", "utun"]
        p.environment = ["PATH":"/usr/bin:/bin:/usr/sbin:/sbin", "WG_TUN_NAME_FILE":nameFile, "LOG_LEVEL":"silent"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); process = p
        var name: String?
        for _ in 0..<100 {
            if let data = try? String(contentsOfFile: nameFile,encoding:.utf8), data.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^utun[0-9]+$", options: .regularExpression) != nil { name = data.trimmingCharacters(in: .whitespacesAndNewlines); break }
            if !p.isRunning { break }; Thread.sleep(forTimeInterval: 0.05)
        }
        guard let iface = name else { throw AppError.message("Не удалось создать туннель AmneziaWG") }
        interface = iface
        _ = try IPC.uapi(path: IPC.directory + "/uapi/\(iface).sock", message: profile.uapi(ip: ip))
        for address in profile.addresses {
            let components = address.split(separator: "/"), host = String(components[0])
            if host.contains(":") { _ = try SystemCommand.checked("/sbin/ifconfig", [iface, "inet6", address, "alias"]) }
            else { _ = try SystemCommand.checked("/sbin/ifconfig", [iface, "inet", host, host, "netmask", netmask(Int(components[1])!), "alias"]) }
        }
        _ = try SystemCommand.checked("/sbin/ifconfig", [iface, "mtu", String(profile.mtu), "up"])
        if routingMode == .rules {
            _ = try SystemCommand.checked("/sbin/route",["-n","add","-ifscope",iface,"default","-interface",iface])
            if profile.hasIPv6 { _ = try SystemCommand.checked("/sbin/route",["-n","add","-inet6","-ifscope",iface,"default","-interface",iface]) }
        } else {
        for route in ["0.0.0.0/1", "128.0.0.0/1"] { _ = try SystemCommand.checked("/sbin/route", ["-n", "add", "-net", route, "-interface", iface]); splitRoutes.append((false, route)) }
        if profile.hasIPv6 { for route in ["::/1", "8000::/1"] { _ = try SystemCommand.checked("/sbin/route", ["-n", "add", "-inet6", route, "-interface", iface]); splitRoutes.append((true, route)) } }
        }
        guard let store = SCDynamicStoreCreate(nil, "AutoTurnDNS" as CFString, nil, nil) else { throw AppError.message("DNS недоступен") }
        // A separate supplemental resolver, removed by key; never overwrite user DNS.
        let key = "State:/Network/Service/AutoTurn-\(primaryService)/DNS" as CFString
        let dns: [String: Any] = ["ServerAddresses": profile.dns, "SupplementalMatchDomains": [""], "SupplementalMatchOrders": [0], "InterfaceName": iface]
        if routingMode == .rules { return }
        dnsService = key as String
        saveJournal()
        guard SCDynamicStoreSetValue(store, key, dns as CFDictionary) else { throw AppError.message("Не удалось установить DNS") }
    }
    func stop() throws {
        var errors: [String] = []
        if let key = dnsService, let store = SCDynamicStoreCreate(nil, "AutoTurnDNS" as CFString, nil, nil) {
            if SCDynamicStoreCopyValue(store,key as CFString) != nil && !SCDynamicStoreRemoveValue(store, key as CFString) { errors.append("Не удалось убрать DNS AutoTurn") }
            else { dnsService = nil }
        }
        if routingMode == .rules, let iface = interface {
            _ = try? SystemCommand.run("/sbin/route",["-n","delete","-ifscope",iface,"default","-interface",iface])
            _ = try? SystemCommand.run("/sbin/route",["-n","delete","-inet6","-ifscope",iface,"default","-interface",iface])
        }
        for (v6, route) in splitRoutes.reversed() {
            let result = try? SystemCommand.run("/sbin/route", ["-n", "delete"] + (v6 ? ["-inet6"] : []) + ["-net", route, "-interface", interface ?? ""])
            if result == nil { errors.append("Не удалось удалить маршрут AutoTurn") }
        }
        splitRoutes = []
        if let process = process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval:0.025) }
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            let killDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < killDeadline { Thread.sleep(forTimeInterval:0.025) }
            if process.isRunning { errors.append("Движок VPN не остановился") }
        }
        process = nil; interface = nil
        if let (ip, gateway) = endpointRoute { _ = try? SystemCommand.run("/sbin/route", ["-n", "delete", "-host", ip, gateway]) }; endpointRoute = nil
        if errors.isEmpty { try? FileManager.default.removeItem(atPath:journal) }
        else { throw AppError.message(errors.joined(separator:". ")) }
    }
    private func netmask(_ prefix: Int) -> String { let bits: UInt32 = prefix == 0 ? 0 : UInt32.max << (32-prefix); return [24,16,8,0].map { String((bits >> $0) & 255) }.joined(separator: ".") }
}

enum HealthProbe {
    static func check(tunnel: String, dns: [String]? = nil) -> Bool {
        // Curl is bound to this utun; physical egress is independently blocked by PF.
        let endpoints = ["https://www.apple.com/library/test/success.html", "https://www.cloudflare.com/cdn-cgi/trace"]
        for endpoint in endpoints {
            var extra: [String] = []
            if let dns = dns, let server = dns.first(where: { !$0.contains(":") }), let host = URL(string:endpoint)?.host {
                let labels = host.split(separator:".")
                var query = Data([0x43,0x21,1,0,0,1,0,0,0,0,0,0]); for l in labels { query.append(UInt8(l.utf8.count)); query.append(contentsOf:l.utf8) }; query.append(contentsOf:[0,0,1,0,1])
                guard let response = try? RoutingDNSProxy.exchange(query,upstream:server,interface:tunnel,tcp:false), let records = try? DNSPacket(response).answers(matching:query), let ip = records.compactMap({$0.ip}).first(where: { !$0.contains(":") }) else { continue }
                extra = ["--resolve","\(host):443:\(ip)"]
            }
            if let result = try? SystemCommand.run("/usr/bin/curl", ["--silent", "--fail", "--noproxy", "*", "--interface", tunnel, "--connect-timeout", "3", "--max-time", "5", "--max-filesize", "8192"] + extra + [endpoint]), result.code == 0, !result.output.isEmpty { return true }
        }
        return false
    }
}
