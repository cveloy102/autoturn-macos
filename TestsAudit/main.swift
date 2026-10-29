import Foundation
import Darwin

var checks = 0, failures = 0
func check(_ condition: Bool, _ name: String) {
    checks += 1
    if !condition { failures += 1; print("FAIL: \(name)") }
}
func rejects(_ action: () throws -> Void) -> Bool {
    do { try action(); return false } catch { return true }
}
let key = Data(repeating: 7, count: 32).base64EncodedString()
let config = "[Interface]\nPrivateKey=\(key)\nAddress=10.0.0.2/32\nDNS=1.1.1.1\n[Peer]\nPublicKey=\(key)\nEndpoint=198.51.100.10:51820\nAllowedIPs=0.0.0.0/0\n"
let profile = try Profile.parse(config, name: "Audit")
// The router need not provide DNS (e.g. tethering with separate DHCP DNS).
// Global/DNS includes supplemental VPN resolvers and must never feed the core.
var networkValues: [String:[String:Any]] = [
    "State:/Network/Global/IPv4":["PrimaryService":"wifi","PrimaryInterface":"en0"],
    "State:/Network/Service/wifi/IPv4":["InterfaceName":"en0","Router":"192.0.2.1"],
    "State:/Network/Service/wifi/DNS":["ServerAddresses":["192.0.2.53","192.0.2.54"]],
    "State:/Network/Global/DNS":["ServerAddresses":["172.29.255.2"]]
]
func testPhysical() -> PhysicalNetwork { PhysicalNetwork.read { networkValues[$0] } }
check(testPhysical().dnsServers == ["192.0.2.53","192.0.2.54"],"Physical DNS comes from DHCP, not gateway or our global resolver")
networkValues["Setup:/Network/Service/wifi/DNS"] = ["ServerAddresses":["192.0.2.99"]]
check(testPhysical().dnsServers == ["192.0.2.99"],"Manual DNS overrides DHCP DNS")
networkValues["Setup:/Network/Service/wifi/DNS"] = ["ServerAddresses":[]]
check(testPhysical().dnsServers == ["192.0.2.53","192.0.2.54"],"Empty manual DNS preserves DHCP DNS")
networkValues["State:/Network/Service/wifi/DNS"] = ["ServerAddresses":["2001:db8::53","192.0.2.53","invalid"]]
check(testPhysical().dnsServers == ["192.0.2.53","2001:db8::53"],"Invalid DNS is excluded and IPv4 DNS is preferred")
networkValues["State:/Network/Service/wifi/DNS"] = nil
check(testPhysical().dnsServers.isEmpty,"Missing DNS fabricated a resolver from the gateway or Global/DNS")
networkValues["State:/Network/Global/IPv4"] = ["PrimaryService":"other","PrimaryInterface":"en1"]
networkValues["State:/Network/Service/other/IPv4"] = ["InterfaceName":"en1","Router":"198.51.100.1"]
networkValues["State:/Network/Service/other/DNS"] = ["ServerAddresses":["198.51.100.53"]]
check(testPhysical().dnsServers == ["198.51.100.53"],"Network switch reused the previous service's DNS")
func endpointDNSReply(_ query:Data,_ bytes:[UInt8]) -> Data {
    var response = Array(query); response[2] = 0x81; response[3] = 0x80; response[6] = 0; response[7] = 1
    response += [0xc0,12,0,1,0,1,0,0,0,60,0,4] + bytes
    return Data(response)
}
let resolverNetwork = PhysicalNetwork(interface:"en0",gateway:"192.0.2.1",service:"dns",dnsServers:["192.0.2.53","192.0.2.54"])
var resolverServers: [String] = []
let endpointAddress = try EndpointResolver.resolve("vpn.example",physical:resolverNetwork,exchange:{ query,server,iface in
    resolverServers.append(server)
    check(iface == "en0","Endpoint DNS did not bind the physical interface")
    return endpointDNSReply(query,server == "192.0.2.53" ? [198,18,0,197] : [203,0,113,10])
})
check(endpointAddress == "203.0.113.10" && resolverServers == ["192.0.2.53","192.0.2.54"],"Endpoint resolver accepted fake IP or queried gateway instead of actual DNS")
check(rejects { _ = try EndpointResolver.resolve("vpn.example",physical:resolverNetwork,exchange:{ query,_,_ in endpointDNSReply(query,[198,19,0,1]) }) },"Synthetic-only DNS answers escaped endpoint resolution")
check(rejects { _ = try EndpointResolver.resolve("198.18.0.197",physical:resolverNetwork) },"Literal fake endpoint bypassed DNS validation")
check(try EndpointResolver.resolve("203.0.113.20",physical:PhysicalNetwork()) == "203.0.113.20","Literal real endpoint unnecessarily required network DNS")
check(!Profile.isIP("192.0.2.1\0unexpected"), "IP validation rejects embedded NUL before C conversion")
check(!Profile.validCIDR("192.0.2.1\0unexpected/32"), "CIDR validation rejects embedded NUL")
check(rejects { _ = try RoutingIPImport.parse("192.0.2.1\0unexpected") }, "IP-list import rejects embedded NUL")
for cidr in ["/192.0.2.1/32", "192.0.2.1/32/", "192.0.2.1//32", "192.0.2.1/+32", "2001:db8::1/128/"] {
    check(!Profile.validCIDR(cidr), "Malformed CIDR rejected: \(cidr)")
    check(rejects { _ = try RoutingIPImport.parse(cidr) }, "IP import rejects malformed CIDR: \(cidr)")
}
for endpoint in ["-bad.example:51820", "bad..example:51820", "host:evil:51820", "999.999.999.999:51820", "2001:db8::1:51820"] {
    check(rejects { _ = try Profile.parse(config.replacingOccurrences(of: "198.51.100.10:51820", with: endpoint), name: "Audit") }, "Malformed endpoint rejected: \(endpoint)")
}
for endpoint in ["vpn.example:51820", "[2001:db8::1]:51820", "198.51.100.10:51820"] {
    check(!rejects { _ = try Profile.parse(config.replacingOccurrences(of: "198.51.100.10:51820", with: endpoint), name: "Audit") }, "Valid endpoint accepted: \(endpoint)")
}
func readLine(_ payload: String, limit: Int) throws -> Data {
    var fds: [Int32] = [-1, -1]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw AppError.message("socketpair failed") }
    defer { close(fds[0]); close(fds[1]) }
    try IPC.write(Data(payload.utf8), fd: fds[0]); shutdown(fds[0], SHUT_WR)
    return try IPC.readLine(fd: fds[1], limit: limit)
}
check(rejects { _ = try readLine("123456789\n", limit: 8) }, "IPC enforces limit before newline in same read")
check((try? readLine("12345678\n", limit: 8)) == Data("12345678".utf8), "IPC accepts line exactly at limit")
check(rejects { _ = try readLine("123456789", limit: 8) }, "IPC rejects oversized unterminated line")
check((try? readLine("\n", limit: 8)) == Data(), "IPC accepts empty frame")

var events: [String] = []
final class AuditGuard: TrafficProtection {
    var token: String?, active = false, rejectRemove = false
    func restoreToken(_ value: String?) { token = value }
    func apply(tunnel: String?, profile: Profile?) throws { active = true; token = "1"; events.append("protect") }
    func remove() throws {
        events.append("release")
        if rejectRemove { throw AppError.message("Simulated PF cleanup failure") }
        active = false; token = nil
    }
}
final class AuditTunnel: ManagedTunnel {
    var running = false, interface: String?, starts = 0
    func recoverJournal() {}
    func start(_ profile: Profile, physical: PhysicalNetwork, engine: String) throws {
        guard interface == nil else { throw AppError.message("Stale endpoint route from crashed engine") }
        starts += 1; running = true; interface = "utun900"; events.append("start")
    }
    func stop() throws { events.append("stop"); running = false; interface = nil }
}
final class AuditRoutes: DomainRouting {
    var running = false
    func recoverJournal() {}
    func configure(_ settings: RoutingSettings, physical: PhysicalNetwork) throws {}
    func setTunnel(_ interface: String?, dns: [String], supportsIPv6: Bool) throws { running = true }
    func stop() throws { events.append("routing-stop"); running = false }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let protection = AuditGuard(), tunnel = AuditTunnel(), routes = AuditRoutes()
var healthy = true
let service = Service(Installation(uid: getuid(), cdhashes: [], engine: "unused"), protection: protection, managedTunnel: tunnel, routing: routes, physical: { PhysicalNetwork(interface: "en0", gateway: "192.168.1.1", service: "audit") }, health: { _ in healthy }, stateDirectory: directory.path, monitoring: false)
service.tick()
check(service.status.phase == .setup && !protection.active && !tunnel.running, "Unconfigured service asks for profiles instead of claiming home")
var settings = Settings(); settings.mode = .on; settings.profiles = [profile]; settings.selectedID = profile.id; settings.routing.mode = .rules
func configure() -> RPCResponse { service.handle(RPCRequest(command: "configure", settings: settings, network: nil)) }
check(configure().status.phase == .connected, "Audit fixture connects")
tunnel.running = false; events = []
let crashRecovery = service.handle(RPCRequest(command: "check", settings: nil, network: nil))
check(crashRecovery.status.phase == .connected && tunnel.starts == 2, "Crashed AWG engine cleans stale state before reconnecting")
check(events.firstIndex(of: "routing-stop").map { $0 < (events.firstIndex(of: "start") ?? -1) } == true, "AWG crash stops stale routing core before reconnecting")
protection.rejectRemove = true
let failedStop = service.handle(RPCRequest(command: "stop", settings: nil, network: nil))
check(!failedStop.ok && failedStop.error != nil && failedStop.status.phase == .error, "Stop reports cleanup failure to caller")
check(!tunnel.running && !routes.running, "Cleanup continues after PF failure")
check(service.handle(RPCRequest(command: "status", settings: nil, network: nil)).ok, "Status remains readable after cleanup failure")
protection.rejectRemove = false
check(service.handle(RPCRequest(command: "stop", settings: nil, network: nil)).status.phase == .off, "Stop retries cleanup")
var backup = profile; backup.id = UUID().uuidString; backup.name = "Backup"
settings.profiles.append(backup)
_ = configure(); events = []
_ = service.handle(RPCRequest(command: "next", settings: nil, network: nil))
check(events.firstIndex(of: "routing-stop").map { $0 < (events.firstIndex(of: "stop") ?? -1) } == true, "Manual failover stops routing core before old tunnel")
check(events.first == "protect", "Manual failover protects traffic before stopping processes")
healthy = false; _ = configure(); events = []
for _ in 0..<2 { _ = service.handle(RPCRequest(command: "check", settings: nil, network: nil)) }
check(events.firstIndex(of: "routing-stop").map { $0 < (events.firstIndex(of: "stop") ?? -1) } == true, "Automatic failover stops routing core before old tunnel")
healthy = true; _ = service.handle(RPCRequest(command: "stop", settings: nil, network: nil))

// Exercise malformed wire data without trusting the packet's lengths/pointers.
var randomState: UInt64 = 0x6175746f7475726e
for _ in 0..<5000 {
    randomState = randomState &* 6364136223846793005 &+ 1
    let length = Int(randomState % 256)
    var bytes: [UInt8] = []
    for _ in 0..<length { randomState = randomState &* 6364136223846793005 &+ 1; bytes.append(UInt8(truncatingIfNeeded: randomState >> 32)) }
    let packet = DNSPacket(Data(bytes))
    _ = try? packet.question(); _ = try? packet.answers(matching: Data(bytes)); _ = DNSPacket.failure(Data(bytes))
}
check(true, "5000 deterministic malformed DNS packets do not crash")
let loop = Data([0,1,1,0,0,1,0,0,0,0,0,0,0xc0,12,0,1,0,1])
check(rejects { _ = try DNSPacket(loop).question() }, "DNS compression pointer loop rejected")

if let path = ProcessInfo.processInfo.environment["AT_TEST_ROUTING_CORE"] {
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
    let seed = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Resources/Routing/seed.json"))) as! [String:Any]
    for entry in seed["services"] as! [[String:Any]] {
        var rules = RoutingSettings(); rules.mode = .rules
        rules.rules = [RoutingRule(name:entry["name"] as! String,serviceID:entry["id"] as? String,sourcePath:entry["sourcePath"] as? String,baseDomains:entry["domains"] as! [String])]
        for ipv6 in [false,true] {
            let config = directory.appendingPathComponent("core-config.json")
            try RoutingCoreConfiguration.make(rules,physicalInterface:"en0",physicalDNS:"192.168.1.53",tunnel:"utun3",dns:"1.1.1.1",supportsIPv6:ipv6).write(to:config)
            let process = Process(); process.executableURL = URL(fileURLWithPath:path); process.arguments = ["check","-c",config.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            check(process.terminationStatus == 0, "Bundled routing core accepts service \(entry["id"]!) IPv6=\(ipv6)")
        }
    }
}

// These run actual native subprocesses; no root, DNS or route mutations.
check((try? SystemCommand.run("/usr/bin/printf",["hello"]))?.output == "hello","System command captures normal output")
check((try? SystemCommand.run("/bin/sh",["-c","exit 7"]))?.code == 7,"System command preserves failure exit status")
let inputText = String(repeating:"bounded input\n",count:5000)
check((try? SystemCommand.run("/bin/cat",[],input:inputText))?.output == inputText,"System command simultaneously drains output and writes pipe-sized input")
let commandStarted = ContinuousTime.now()
check(rejects { _ = try SystemCommand.run("/bin/sleep",["10"],timeout:0.15) },"Hung subprocess is terminated at deadline")
check(ContinuousTime.now() - commandStarted < 2,"Hung subprocess does not delay recovery indefinitely")
check(rejects { _ = try SystemCommand.run("/usr/bin/yes",[],timeout:2,outputLimit:1024) },"Unbounded subprocess output is rejected")
check(rejects { _ = try SystemCommand.run("/bin/sh",["-c","exec 1>&- 2>&-; sleep 10"],timeout:0.15) },"Closed output does not hide a hung subprocess")
check((try? SystemCommand.run("/bin/cat",[],input:""))?.output == "","Empty stdin is closed without hanging")
check(rejects { _ = try SystemCommand.run("/missing-autoturn-command",[]) },"Missing executable reports a launch error")
let journalPath = directory.appendingPathComponent("recovery-journal.json").path
let savedJournal = Tunnel.Journal(endpoint:"198.51.100.10",gateway:"192.168.1.1",dnsKey:"State:/Network/Service/AutoTurn-test/DNS")
try JSONEncoder().encode(savedJournal).write(to:URL(fileURLWithPath:journalPath))
var failDNSRemoval = true, routeCode: Int32 = 1, routeOutput = "route: permission denied", routeDeletes = 0
let recoveryTunnel = Tunnel(journal:journalPath,command:{ _,_ in routeDeletes += 1; return CommandResult(code:routeCode,output:routeOutput) },removeDNS:{ _ in if failDNSRemoval { throw AppError.message("simulated DNS failure") } })
check(rejects { try recoveryTunnel.recoverJournal() } && FileManager.default.fileExists(atPath:journalPath),"Failed DNS recovery retains journal and reports failure")
failDNSRemoval = false
check(rejects { try recoveryTunnel.stop() } && FileManager.default.fileExists(atPath:journalPath),"Nonzero route deletion exit preserves recovery journal")
routeCode = 0
check(!rejects { try recoveryTunnel.stop() } && !FileManager.default.fileExists(atPath:journalPath),"Repeated Stop completes saved route and DNS cleanup")
try JSONEncoder().encode(savedJournal).write(to:URL(fileURLWithPath:journalPath))
routeCode = 1; routeOutput = "route: writing to routing socket: not in table"
check(!rejects { try recoveryTunnel.stop() } && !FileManager.default.fileExists(atPath:journalPath),"Already removed route is an idempotent cleanup success")
try JSONEncoder().encode(Tunnel.Journal(endpoint:"invalid",gateway:"192.168.1.1",dnsKey:nil)).write(to:URL(fileURLWithPath:journalPath))
let deletesBeforeInvalid = routeDeletes
check(rejects { try recoveryTunnel.stop() } && routeDeletes == deletesBeforeInvalid,"Malformed journal cannot execute a route mutation")

print("Audit: \(checks) checks, \(failures) failures. No system network or Keychain changes.")
exit(failures == 0 ? 0 : 1)
