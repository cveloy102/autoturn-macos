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
    func configureEndpointDNS(_ servers: [String], physical: PhysicalNetwork) throws
}
extension TrafficProtection {
    func setRoutingInterface(_ interface: String?) throws {}
    func configureRouting(_ settings: RoutingSettings, physical: PhysicalNetwork) throws {}
    func setDirectAddresses(_ addresses: Set<String>) throws {}
    func configureEndpointDNS(_ servers: [String], physical: PhysicalNetwork) throws {}
}
protocol ManagedTunnel: AnyObject {
    var running: Bool { get }
    var interface: String? { get }
    func recoverJournal() throws
    func start(_ profile: Profile, physical: PhysicalNetwork, engine: String) throws
    func stop() throws
    func setRoutingMode(_ mode: RoutingMode)
}
extension ManagedTunnel { func setRoutingMode(_ mode: RoutingMode) {} }

struct CommandResult { var code: Int32; var output: String }
enum SystemCommand {
    static func run(_ executable: String, _ arguments: [String], input: String? = nil, timeout: TimeInterval = 15, outputLimit: Int = 1024 * 1024) throws -> CommandResult {
        guard timeout.isFinite, timeout > 0, outputLimit > 0 else { throw AppError.message("Некорректные ограничения системной операции") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(), source = input.map { Data($0.utf8) }
        guard (source?.count ?? 0) <= 1024 * 1024 else { throw AppError.message("Слишком большой ввод системной операции") }
        process.standardOutput = output; process.standardError = output
        let inputPipe = source == nil ? nil : Pipe()
        process.standardInput = inputPipe.map { $0 as Any } ?? FileHandle.nullDevice
        let readFD = output.fileHandleForReading.fileDescriptor
        let writeFD = inputPipe?.fileHandleForWriting.fileDescriptor
        _ = fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK)
        if let fd = writeFD { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK); _ = fcntl(fd, F_SETNOSIGPIPE, 1) }
        defer { try? output.fileHandleForReading.close(); try? inputPipe?.fileHandleForWriting.close() }
        try process.run()
        // Close parent copies of the child's pipe ends so EOF remains observable.
        try? output.fileHandleForWriting.close(); try? inputPipe?.fileHandleForReading.close()
        let deadline = ContinuousTime.now() + timeout
        var data = Data(), buffer = [UInt8](repeating:0,count:16384), offset = 0, eof = false, inputClosed = false
        do {
            while !eof || process.isRunning {
                // Bound the drain loop too: an endless writer must not starve the deadline.
                for _ in 0..<16 where !eof {
                    let count = Darwin.read(readFD,&buffer,buffer.count)
                    if count > 0 {
                        guard count <= outputLimit - data.count else { throw AppError.message("Слишком большой вывод системной операции") }
                        data.append(contentsOf:buffer.prefix(count))
                    } else if count == 0 { eof = true }
                    else if errno == EINTR { continue }
                    else if errno == EAGAIN { break }
                    else { throw AppError.message("Не удалось прочитать ответ системной операции") }
                }
                if let source = source, let fd = writeFD, !inputClosed {
                    if offset < source.count {
                        let count = source.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!.advanced(by:offset),min(16384,source.count-offset)) }
                        if count > 0 { offset += count }
                        else if count < 0 && errno != EAGAIN && errno != EINTR { throw AppError.message("Не удалось передать ввод системной операции") }
                    }
                    if offset == source.count { try inputPipe?.fileHandleForWriting.close(); inputClosed = true }
                }
                if eof && !process.isRunning { break }
                guard ContinuousTime.now() < deadline else { throw AppError.message("Системная операция \(URL(fileURLWithPath:executable).lastPathComponent) превысила время ожидания") }
                Thread.sleep(forTimeInterval:0.01)
            }
        } catch {
            // Do not wait for a subprocess or inherited pipe indefinitely.
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            let end = ContinuousTime.now() + 1
            while process.isRunning && ContinuousTime.now() < end { Thread.sleep(forTimeInterval:0.01) }
            throw error
        }
        process.waitUntilExit()
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
    var dnsServers: [String] = []
    var available: Bool { interface != nil && gateway != nil }
    static func read() -> PhysicalNetwork {
        guard let store = SCDynamicStoreCreate(nil, "AutoTurn" as CFString, nil, nil) else { return PhysicalNetwork() }
        return read { SCDynamicStoreCopyValue(store, $0 as CFString) as? [String:Any] }
    }
    static func read(valuesForKey: (String) -> [String:Any]?) -> PhysicalNetwork {
        guard let global = valuesForKey("State:/Network/Global/IPv4"), let service = global["PrimaryService"] as? String,
              let values = valuesForKey("State:/Network/Service/\(service)/IPv4") else { return PhysicalNetwork() }
        let iface = (values["InterfaceName"] as? String) ?? (global["PrimaryInterface"] as? String)
        guard let interface = iface, interface.range(of: "^(en|bridge|eth)[0-9]+$", options: .regularExpression) != nil else { return PhysicalNetwork() }
        let router = values["Router"] as? String
        guard let gateway = router, Profile.isIP(gateway) else { return PhysicalNetwork(interface: interface, gateway: nil, service: service) }
        let v6 = valuesForKey("State:/Network/Service/\(service)/IPv6")
        var gateway6 = v6?["Router"] as? String
        if let g = gateway6, Profile.isIP(g) { if g.lowercased().hasPrefix("fe80:") { gateway6 = g + "%" + interface } } else { gateway6 = nil }
        // Read the physical service, never Global/DNS: the latter can point back
        // to our own synthetic resolver. Manual DNS overrides DHCP DNS.
        let manualDNS = valuesForKey("Setup:/Network/Service/\(service)/DNS")?["ServerAddresses"] as? [String] ?? []
        let networkDNS = valuesForKey("State:/Network/Service/\(service)/DNS")?["ServerAddresses"] as? [String] ?? []
        let addresses = (manualDNS.isEmpty ? networkDNS : manualDNS).filter { Profile.isIP($0) }
        // This client requires an IPv4 uplink; prefer its IPv4 resolver, while
        // retaining an IPv6 resolver for networks that only supply one.
        let dns = addresses.filter { !$0.contains(":") } + addresses.filter { $0.contains(":") }
        return PhysicalNetwork(interface: interface, gateway: gateway, service: service,gateway6:gateway6,dnsServers:dns)
    }
}

enum EndpointResolver {
    static func resolve(_ host: String, physical: PhysicalNetwork, exchange: (Data,String,String) throws -> Data = { try RoutingDNSProxy.exchange($0,upstream:$1,interface:$2,tcp:false) }) throws -> String {
        guard Profile.validEndpointHost(host) else { throw AppError.message("Некорректный адрес VPN-сервера") }
        if Profile.isIP(host) {
            guard !host.contains(":"), !Profile.isRoutingFakeIP(host) else { throw AppError.message("VPN-серверу нужен настоящий IPv4 адрес, вне служебной сети AutoTurn") }
            return host
        }
        guard let interface = physical.interface else { throw AppError.message("Нет физической сети для определения VPN-сервера") }
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        var query = Data([0x43,0x23,1,0,0,1,0,0,0,0,0,0])
        for label in name.split(separator:".") { query.append(UInt8(label.utf8.count)); query.append(contentsOf:label.utf8) }
        query.append(contentsOf:[0,0,1,0,1])
        for server in physical.dnsServers.filter({ Profile.isIP($0) && !$0.contains(":") && !Profile.isRoutingFakeIP($0) }).prefix(3) {
            guard let response = try? exchange(query,server,interface),
                  let records = try? DNSPacket(response).answers(matching:query),
                  let address = records.compactMap({ $0.ip }).first(where: { !$0.contains(":") && !Profile.isRoutingFakeIP($0) }) else { continue }
            return address
        }
        throw AppError.message("Не удалось определить настоящий IPv4 адрес VPN-сервера через DNS текущей сети")
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
    private var endpointDNS: [String] = [], endpointDNSInterface: String?
    func configureEndpointDNS(_ servers: [String], physical: PhysicalNetwork) throws {
        lock.lock(); defer { lock.unlock() }
        guard servers.allSatisfy({ Profile.isIP($0) && !$0.contains(":") && !Profile.isRoutingFakeIP($0) }),
              servers.isEmpty || physical.interface?.range(of:"^(en|bridge|eth)[0-9]+$",options:.regularExpression) != nil else { throw AppError.message("Некорректный DNS VPN-сервера") }
        endpointDNS = servers; endpointDNSInterface = servers.isEmpty ? nil : physical.interface
    }
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
        if let profile = profile, let ip = profile.resolvedIP {
            guard Profile.isIP(ip), !Profile.isRoutingFakeIP(ip) else { throw AppError.message("VPN-сервер подменён служебным адресом AutoTurn") }
            rules += "pass out quick \(ip.contains(":") ? "inet6" : "inet") proto udp to \(ip) port \(profile.endpointPort) keep state\n"
        }
        if let interface = endpointDNSInterface {
            for server in endpointDNS { rules += "pass out quick on \(interface) inet proto { tcp udp } to \(server) port 53 user root keep state\n" }
        }
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
    private var rulesIPv6 = false
    private var splitRoutes: [(Bool, String)] = []
    private let journal: String
    private let command: (String, [String]) throws -> CommandResult
    private let removeDNS: (String) throws -> Void
    init(journal: String = "/Library/Application Support/AutoTurn/network-journal.json", command: @escaping (String, [String]) throws -> CommandResult = { try SystemCommand.run($0,$1) }, removeDNS: @escaping (String) throws -> Void = Tunnel.removeDNSKey) {
        self.journal = journal; self.command = command; self.removeDNS = removeDNS
    }
    static func removeDNSKey(_ key: String) throws {
        guard let store = SCDynamicStoreCreate(nil,"AutoTurnDNS" as CFString,nil,nil) else { throw AppError.message("DNS недоступен для очистки") }
        if SCDynamicStoreCopyValue(store,key as CFString) != nil && !SCDynamicStoreRemoveValue(store,key as CFString) { throw AppError.message("Не удалось убрать DNS AutoTurn") }
    }
    private func deleteRoute(_ args: [String]) throws {
        let result = try command("/sbin/route",["-n","delete"] + args)
        // The kernel removes interface routes when a utun disappears. Repeating
        // that successful cleanup must work; other failures retain the journal.
        guard result.code == 0 || result.output.contains("not in table") || result.output.contains("No such process") else { throw AppError.message("Не удалось удалить маршрут AutoTurn") }
    }
    struct Journal: Codable { var endpoint: String?; var gateway: String?; var dnsKey: String? }
    private func saveJournal() { if let data = try? JSONEncoder().encode(Journal(endpoint:endpointRoute?.0,gateway:endpointRoute?.1,dnsKey:dnsService)) { try? data.write(to:URL(fileURLWithPath:journal),options:.atomic); chmod(journal,0o600) } }
    func recoverJournal() throws { try recoverSavedJournal() }
    private func recoverSavedJournal() throws {
        guard FileManager.default.fileExists(atPath:journal) else { return }
        let saved = try JSONDecoder().decode(Journal.self,from:Data(contentsOf:URL(fileURLWithPath:journal)))
        if let key = saved.dnsKey {
            guard key.range(of:"^State:/Network/Service/AutoTurn-[A-Za-z0-9-]+/DNS$",options:.regularExpression) != nil else { throw AppError.message("Некорректный журнал DNS AutoTurn") }
            try removeDNS(key)
        }
        if let endpoint = saved.endpoint, let gateway = saved.gateway {
            guard Profile.isIP(endpoint), Profile.isIP(gateway) else { throw AppError.message("Некорректный журнал маршрутов AutoTurn") }
            try deleteRoute(["-host",endpoint,gateway])
        }
        try FileManager.default.removeItem(atPath:journal)
    }
    var running: Bool { process?.isRunning == true }
    func start(_ profile: Profile, physical: PhysicalNetwork, engine: String) throws {
        guard let ip = profile.resolvedIP, Profile.isIP(ip), !Profile.isRoutingFakeIP(ip), let gateway = physical.gateway, let primaryService = physical.service else { throw AppError.message("Нет физического маршрута или настоящего IP сервера") }
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
            if profile.hasIPv6 { _ = try SystemCommand.checked("/sbin/route",["-n","add","-inet6","-ifscope",iface,"default","-interface",iface]); rulesIPv6 = true }
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
        // Also retry a journal left by a previous helper process. Do this before
        // touching live metadata, which is journaled again if anything fails.
        if process == nil && interface == nil && endpointRoute == nil && dnsService == nil {
            try recoverSavedJournal()
        }
        if let key = dnsService {
            do { try removeDNS(key); dnsService = nil } catch { errors.append(error.localizedDescription) }
        }
        if routingMode == .rules, let iface = interface {
            do { try deleteRoute(["-ifscope",iface,"default","-interface",iface]) } catch { errors.append(error.localizedDescription) }
            // Only an IPv6 default actually installed by us needs removal.
            if rulesIPv6 {
                do { try deleteRoute(["-inet6","-ifscope",iface,"default","-interface",iface]) } catch { errors.append(error.localizedDescription) }
            }
        }
        var remaining: [(Bool,String)] = []
        for (v6, route) in splitRoutes.reversed() {
            do { try deleteRoute((v6 ? ["-inet6"] : []) + ["-net",route,"-interface",interface ?? ""]) }
            catch { remaining.append((v6,route)); errors.append(error.localizedDescription) }
        }
        splitRoutes = remaining.reversed()
        if let process = process, process.isRunning {
            process.terminate()
            let deadline = ContinuousTime.now() + 2
            while process.isRunning && ContinuousTime.now() < deadline { Thread.sleep(forTimeInterval:0.025) }
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            let killDeadline = ContinuousTime.now() + 2
            while process.isRunning && ContinuousTime.now() < killDeadline { Thread.sleep(forTimeInterval:0.025) }
            if process.isRunning { errors.append("Движок VPN не остановился") }
        }
        if process?.isRunning != true { process = nil }
        if let (ip,gateway) = endpointRoute {
            do { try deleteRoute(["-host",ip,gateway]); endpointRoute = nil } catch { errors.append(error.localizedDescription) }
        }
        if errors.isEmpty {
            interface = nil; rulesIPv6 = false
            if FileManager.default.fileExists(atPath:journal) { try FileManager.default.removeItem(atPath:journal) }
        } else {
            if endpointRoute != nil || dnsService != nil { saveJournal() }
            throw AppError.message(errors.joined(separator:". "))
        }
    }
    private func netmask(_ prefix: Int) -> String { let bits: UInt32 = prefix == 0 ? 0 : UInt32.max << (32-prefix); return [24,16,8,0].map { String((bits >> $0) & 255) }.joined(separator: ".") }
}

enum HealthProbe {
    // The first successful HTTPS response is enough. A slow/blocked test site
    // must not hold a healthy VPN behind its timeout before trying the other.
    static func firstSuccess(_ probes: [() -> Bool], timeout: TimeInterval = 10) -> Bool {
        final class State {
            let condition = NSCondition()
            var remaining: Int
            var healthy = false
            init(_ count: Int) { remaining = count }
        }
        let state = State(probes.count)
        for probe in probes {
            DispatchQueue.global(qos:.utility).async {
                let result = probe()
                state.condition.lock()
                state.healthy = state.healthy || result; state.remaining -= 1
                state.condition.broadcast(); state.condition.unlock()
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        state.condition.lock(); defer { state.condition.unlock() }
        while !state.healthy && state.remaining > 0 {
            if !state.condition.wait(until:deadline) { break }
        }
        return state.healthy
    }
    static func check(tunnel: String, dns: [String]? = nil) -> Bool {
        // Curl stays bound to this utun; physical egress is blocked by PF.
        let endpoints = ["https://www.apple.com/library/test/success.html", "https://www.cloudflare.com/cdn-cgi/trace"]
        return firstSuccess(endpoints.map { endpoint in { checkEndpoint(endpoint,tunnel:tunnel,dns:dns) } })
    }
    private static func checkEndpoint(_ endpoint: String, tunnel: String, dns: [String]?) -> Bool {
        var extra: [String] = []
        if let dns = dns, let server = dns.first(where: { !$0.contains(":") }), let host = URL(string:endpoint)?.host {
            let labels = host.split(separator:".")
            var query = Data([0x43,0x21,1,0,0,1,0,0,0,0,0,0]); for l in labels { query.append(UInt8(l.utf8.count)); query.append(contentsOf:l.utf8) }; query.append(contentsOf:[0,0,1,0,1])
            guard let response = try? RoutingDNSProxy.exchange(query,upstream:server,interface:tunnel,tcp:false),
                  let records = try? DNSPacket(response).answers(matching:query),
                  let ip = records.compactMap({$0.ip}).first(where: { !$0.contains(":") && !Profile.isRoutingFakeIP($0) }) else { return false }
            extra = ["--resolve","\(host):443:\(ip)"]
        }
        if let result = try? SystemCommand.run("/usr/bin/curl", ["--silent", "--fail", "--noproxy", "*", "--interface", tunnel, "--connect-timeout", "3", "--max-time", "5", "--max-filesize", "8192"] + extra + [endpoint],timeout:6), result.code == 0, !result.output.isEmpty { return true }
        return false
    }
}
