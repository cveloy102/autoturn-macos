import Foundation
var passed = 0
func check(_ value:Bool,_ message:String) { guard value else { fatalError(message) }; passed += 1 }
var operations: [String] = []
final class GuardFake: TrafficProtection {
 var token:String?; var active = false; var failRelease = false
 func restoreToken(_ value:String?) { token = value }
 func apply(tunnel:String?,profile:Profile?) throws { active = true; token = "1"; operations.append("protect") }
 func remove() throws { operations.append("release"); active = false; if failRelease { throw AppError.message("Release failure") }; token = nil }
}
final class TunnelFake: ManagedTunnel {
 var running = false; var interface:String?; var starts = 0
 func recoverJournal() {}
 func start(_ profile:Profile,physical:PhysicalNetwork,engine:String) throws { starts += 1; running = true; interface = "utun900"; operations.append("start") }
 func stop() throws { operations.append("stop"); running = false; interface = nil }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:directory) }
var physical = PhysicalNetwork(interface:"en0",gateway:"192.168.1.1",service:"test")
final class RoutingFake: DomainRouting {
 var configured: RoutingSettings?, stops = 0, rejectStart = false, tunnelChecks = 0
 func configure(_ settings:RoutingSettings,physical:PhysicalNetwork) throws { configured = settings }
 func setTunnel(_ interface:String?,dns:[String],supportsIPv6:Bool) throws {
  tunnelChecks += 1
  check(protection.active,"Routing core started before protection")
  check(!supportsIPv6,"IPv4-only profile advertised IPv6 to routing core")
  if rejectStart && configured?.mode == .rules { throw AppError.message("Test core failure") }
 }
 func stop() throws { stops += 1; configured = nil }
 func recoverJournal() {}
}
let protection = GuardFake(), tunnel = TunnelFake(), routing = RoutingFake()
let service = Service(Installation(uid:501,cdhashes:[],engine:"unused"),protection:protection,managedTunnel:tunnel,routing:routing,physical:{physical},health:{_ in true},stateDirectory:directory.path,monitoring:false)
let key = Data(repeating:7,count:32).base64EncodedString()
let profile = try Profile.parse("[Interface]\nPrivateKey=\(key)\nAddress=10.0.0.2/32\nDNS=1.1.1.1\n[Peer]\nPublicKey=\(key)\nEndpoint=198.51.100.10:1234\nAllowedIPs=0.0.0.0/0\n",name:"Test")
var settings = Settings(); settings.profiles = [profile]; settings.selectedID = profile.id; settings.homeSSIDs = ["home"]
func network(_ ssid:String) -> NetworkObservation { NetworkObservation(available:true,interface:physical.interface,ssid:ssid,gateway:physical.gateway) }
func configure(_ mode:Mode,_ ssid:String) -> RPCResponse { settings.mode = mode; return service.handle(RPCRequest(command:"configure",settings:settings,network:network(ssid))) }
var response = configure(.auto,"home")
check(response.ok && response.status.phase == .home,"Fresh home observation ignored by configure")
check(!protection.active && !tunnel.running && tunnel.starts == 0,"Home configuration started VPN unnecessarily")
for _ in 0..<6 { service.physicalNetworkChanged() }
check(service.status.phase == .home && tunnel.starts == 0,"VPN-generated path events invalidated home SSID")
response = configure(.on,"home")
check(response.ok && response.status.phase == .connected && tunnel.running && protection.active,"Manual on did not override home")
operations = []; response = configure(.auto,"home")
check(response.ok && response.status.phase == .home && !tunnel.running && !protection.active,"On-to-home left tunnel or guard")
check(operations == ["release","stop"],"PF release must precede engine shutdown")
_ = configure(.on,"home"); operations = []
response = service.handle(RPCRequest(command:"stop",settings:nil,network:nil))
check(response.ok && response.status.phase == .off && !protection.active && !tunnel.running,"Stop left protection or tunnel")
for _ in 0..<6 { service.physicalNetworkChanged() }
check(service.status.phase == .off && !tunnel.running && !protection.active,"Path events restarted manually disabled VPN")
response = configure(.auto,"cafe")
check(response.status.phase == .connected && protection.active && tunnel.running,"Outside-home policy lost")
physical.gateway = "192.168.2.1"; service.physicalNetworkChanged()
check(protection.active && tunnel.running,"Physical network change disabled required protection")
response = configure(.auto,"home")
check(response.status.phase == .home && !protection.active,"Fresh home after gateway change ignored")
_ = configure(.on,"home"); protection.failRelease = true; response = configure(.off,"home")
check(response.status.phase == .error && !response.status.guardActive && !tunnel.running,"Cleanup failure swallowed or engine left running")
protection.failRelease = false; service.tick()
check(service.status.phase == .off && protection.token == nil,"Cleanup retry did not release token")
settings.routing.mode = .rules
settings.routing.rules = [RoutingRule(name:"YouTube",domains:["youtube.com"])]
response = configure(.auto,"cafe")
check(response.ok && routing.configured?.mode == .rules,"DNS routing not configured outside home")
response = configure(.auto,"home")
check(response.ok && routing.configured == nil && !tunnel.running && !protection.active,"Home left DNS routing running")
response = configure(.on,"home")
check(response.ok && routing.configured?.mode == .rules,"Manual on did not configure routing")
let checksBeforeIdleTick = routing.tunnelChecks
service.nextCheck = Date().addingTimeInterval(60)
service.tick()
check(routing.tunnelChecks > checksBeforeIdleTick,"Core recovery waited for the VPN health timer")
check(protection.active && tunnel.running,"Idle core check lost VPN protection")
response = configure(.off,"home")
check(response.ok && routing.configured == nil,"Manual off left domain routing running")
routing.rejectStart = true
response = configure(.on,"home")
check(!response.ok || response.status.phase == .error,"Routing core startup failure was hidden")
check(response.status.guardActive && tunnel.running,"Routing core failure opened direct traffic")
response = configure(.off,"home")
check(response.status.phase == .off && !protection.active && !tunnel.running,"Off failed after routing core startup error")
routing.rejectStart = false
response = configure(.on,"home")
let startCount = tunnel.starts
settings.routing.databaseUpdatedAt = Date()
response = configure(.on,"home")
check(response.status.phase == .connected && tunnel.starts == startCount,"Database timestamp restarted the VPN")
settings.routing.rules[0].domains.append("googlevideo.com")
response = configure(.on,"home")
check(response.status.phase == .connected && tunnel.starts == startCount + 1,"Changed routing rules were not applied")
_ = configure(.off,"home")
print("\(passed) service transition checks passed: startup at home, VPN path events, on/auto/off, gateway changes, cleanup ordering and retries. No system network changes.")

response = configure(.on,"external")
response = service.handle(RPCRequest(command:"recover",settings:nil,network:nil))
check(response.ok && response.status.phase == .off && !protection.active && !tunnel.running,"Emergency recovery did not release network")
check(service.settings.mode == .off && service.settings.profiles.count == 1 && !service.settings.routing.rules.isEmpty,"Emergency recovery lost profiles or routing rules")
let matches = OwnedProcessRecovery.candidates("111 0 /Library/Application Support/AutoTurn/routing-core run -c /Library/Application Support/AutoTurn/routing-core.json\n112 501 /Library/Application Support/AutoTurn/amneziawg-go -f utun\n113 0 /tmp/routing-core run -c /tmp/config\n114 0 /Library/Application Support/AutoTurn/amneziawg-go -f utun\n")
check(Set(matches.keys) == Set([Int32(111),Int32(114)]),"Recovery identified another user's or unrelated process")
response = service.handle(RPCRequest(command:"recover",settings:nil,network:nil))
check(response.ok && response.status.phase == .off,"Repeated emergency recovery failed")
print("\(passed) checks including emergency recovery and owned-process selection passed")

// Deterministic lease, sleep-sized gaps, cleanup and retry regressions. No waits
// or real PF/routes/Keychain access; the service clock is supplied by the test.
final class LeaseRoutes: DomainRouting {
 var failStop = false, stops = 0
 func configure(_ settings: RoutingSettings, physical: PhysicalNetwork) throws {}
 func setTunnel(_ interface: String?, dns: [String], supportsIPv6: Bool) throws {}
 func recoverJournal() {}
 func stop() throws { stops += 1; if failStop { throw AppError.message("DNS cleanup failed") } }
}
var clock = Date(timeIntervalSince1970:1_800_000_000)
var leasePhysical = PhysicalNetwork(interface:"en0",gateway:"192.168.1.1",service:"lease-test")
let leaseGuard = GuardFake(), leaseTunnel = TunnelFake(), leaseRoutes = LeaseRoutes()
var healthy = true, probes = 0, ownedRecoveryFails = false
let leaseDirectory = directory.appendingPathComponent("lease")
try FileManager.default.createDirectory(at:leaseDirectory,withIntermediateDirectories:true)
let leaseService = Service(Installation(uid:501,cdhashes:[],engine:"unused"),protection:leaseGuard,managedTunnel:leaseTunnel,routing:leaseRoutes,physical:{leasePhysical},health:{_ in probes += 1; return healthy},stateDirectory:leaseDirectory.path,monitoring:false,now:{clock},continuousNow:{clock.timeIntervalSince1970},recoverProcesses:{ if ownedRecoveryFails { throw AppError.message("Owned process still running") } })
var leaseSettings = settings; leaseSettings.mode = .auto
func leaseSample(_ ssid:String?, at date:Date? = nil) -> NetworkObservation {
 NetworkObservation(available:true,interface:leasePhysical.interface,ssid:ssid,gateway:leasePhysical.gateway,sampledAt:date ?? clock)
}
func leaseNetwork(_ sample:NetworkObservation) -> RPCResponse { leaseService.handle(RPCRequest(command:"network",settings:nil,network:sample)) }
_ = leaseService.handle(RPCRequest(command:"configure",settings:leaseSettings,network:leaseSample("home")))
clock += 3
check(leaseNetwork(leaseSample(nil)).status.phase == .home && !leaseGuard.active,"One nil SSID immediately blocked home internet")
clock += 3
check(leaseNetwork(leaseSample("cafe")).status.phase == .connected,"A known external SSID retained home trust")
let probesBeforePath = probes
for _ in 0..<10 { leaseService.physicalNetworkChanged() }
check(probes == probesBeforePath,"VPN path notifications defeated health-check backoff")
_ = leaseNetwork(leaseSample("home")); clock += 21
check(leaseNetwork(leaseSample(nil)).status.phase != .home && leaseGuard.active,"Nil samples extended home trust indefinitely")
_ = leaseNetwork(leaseSample("home")); clock += 21
let delayedReply = leaseNetwork(leaseSample("home",at:clock.addingTimeInterval(-21)))
check(delayedReply.status.phase != .home,"Delayed queued home sample acquired a fresh lease")
_ = leaseNetwork(leaseSample("home")); clock += 1
_ = leaseNetwork(leaseSample("cafe"))
check(leaseNetwork(leaseSample("home",at:clock.addingTimeInterval(-0.5))).status.phase != .home,"Out-of-order home sample replaced newer external sample")
check(leaseNetwork(leaseSample("home",at:clock.addingTimeInterval(60))).status.phase != .home,"Future timestamp extended home trust")
_ = leaseNetwork(leaseSample("home")); leasePhysical.gateway = "192.168.2.1"
leaseService.physicalNetworkChanged()
check(leaseService.status.phase != .home && leaseGuard.active,"Gateway change retained a cached home SSID")
_ = leaseNetwork(leaseSample("home")); leasePhysical = PhysicalNetwork()
leaseService.physicalNetworkChanged()
check(leaseService.status.phase == .waiting && leaseGuard.active,"Physical disconnect retained direct home access")
leasePhysical = PhysicalNetwork(interface:"en0",gateway:"192.168.1.1",service:"lease-test")
_ = leaseNetwork(leaseSample("cafe")); leaseRoutes.failStop = true
check(leaseNetwork(leaseSample("home")).status.phase == .error,"Routing cleanup failure was hidden")
let failedStops = leaseRoutes.stops; leaseRoutes.failStop = false; leaseService.tick()
check(leaseService.status.phase == .home && leaseRoutes.stops == failedStops+1,"Home failed to retry routing cleanup after guard and AWG stopped")
leaseService.startupRecoveryError = AppError.message("Simulated startup recovery error")
ownedRecoveryFails = true
check(leaseService.handle(RPCRequest(command:"stop",settings:nil,network:nil)).status.phase == .error,"Off hid an orphaned process recovery failure")
ownedRecoveryFails = false
check(leaseService.handle(RPCRequest(command:"stop",settings:nil,network:nil)).status.phase == .off,"Startup error prevented explicit Off")
leaseService.startupRecoveryError = nil
leaseSettings.mode = .on; healthy = false
_ = leaseService.handle(RPCRequest(command:"configure",settings:leaseSettings,network:leaseSample("cafe")))
for _ in 0..<2 { _ = leaseService.handle(RPCRequest(command:"check",settings:nil,network:nil)) }
let startsBeforeRetry = leaseTunnel.starts
leaseService.tick()
check(leaseTunnel.starts == startsBeforeRetry,"Single-profile retry skipped its backoff")
clock += 31; leaseService.tick()
check(leaseTunnel.starts == startsBeforeRetry+1 && leaseGuard.active,"Single-profile retry never recreated the unresponsive tunnel")
healthy = true; clock += 11; leaseService.tick()
check(leaseService.status.phase == .connected,"Single-profile retry did not recover")
let restoredService = Service(Installation(uid:501,cdhashes:[],engine:"unused"),protection:GuardFake(),managedTunnel:TunnelFake(),routing:LeaseRoutes(),physical:{leasePhysical},health:{_ in true},stateDirectory:leaseDirectory.path,monitoring:false,now:{clock})
check(restoredService.status.events.contains { $0.contains("повторные проверки") },"Restart discarded the failure history")
check(restoredService.status.events.count <= 100,"Persistent history grew beyond the diagnostic limit")
let permissions = try FileManager.default.attributesOfItem(atPath:leaseDirectory.appendingPathComponent("events.json").path)[.posixPermissions] as? NSNumber
check(permissions?.intValue == 0o600,"Persistent diagnostic events are not private")
_ = leaseService.handle(RPCRequest(command:"stop",settings:nil,network:nil))
print("\(passed) checks including home lease expiry, transient nil SSID, delayed samples, cleanup retries, single-profile reconnect and persistent history passed")

// Sleep advances the continuous clock even when the wall clock is corrected.
var wallClock = Date(timeIntervalSince1970:1_800_000_000), elapsedClock: TimeInterval = 1000
let wakeGuard = GuardFake(), wakeTunnel = TunnelFake()
let wakeService = Service(Installation(uid:501,cdhashes:[],engine:"unused"),protection:wakeGuard,managedTunnel:wakeTunnel,routing:LeaseRoutes(),physical:{leasePhysical},health:{_ in true},stateDirectory:directory.path,monitoring:false,now:{wallClock},continuousNow:{elapsedClock})
var wakeSettings = leaseSettings; wakeSettings.mode = .auto
func wakeSample(_ ssid:String?, age:TimeInterval = 0) -> NetworkObservation {
 NetworkObservation(available:true,interface:leasePhysical.interface,ssid:ssid,gateway:leasePhysical.gateway,sampledAt:wallClock.addingTimeInterval(-age),sampledContinuouslyAt:elapsedClock-age)
}
_ = wakeService.handle(RPCRequest(command:"configure",settings:wakeSettings,network:wakeSample("home")))
elapsedClock += 600; wallClock -= 3600; wakeService.tick()
check(wakeService.status.phase != .home && wakeGuard.active,"Clock rollback after sleep extended old home trust")
_ = wakeService.handle(RPCRequest(command:"network",settings:nil,network:wakeSample("home")))
check(wakeService.status.phase == .home && !wakeGuard.active,"Fresh home after clock rollback was rejected")
elapsedClock += 21 // Wall time stays still, as it can when corrected after sleep.
wakeService.tick()
check(wakeService.status.phase != .home && wakeGuard.active,"Lease expiry depended on wall-clock progress")
_ = wakeService.handle(RPCRequest(command:"network",settings:nil,network:wakeSample("home",age:600)))
check(wakeService.status.phase != .home,"Pre-sleep sample reacquired home trust")
_ = wakeService.handle(RPCRequest(command:"network",settings:nil,network:wakeSample("home")))
elapsedClock += 3; wallClock += 3
_ = wakeService.handle(RPCRequest(command:"network",settings:nil,network:wakeSample(nil)))
let deadlineAfterNil = wakeService.nextCheck
for _ in 0..<20 {
 _ = wakeService.handle(RPCRequest(command:"network",settings:nil,network:wakeSample("cafe",age:30)))
}
check(wakeService.status.phase == .home && wakeService.nextCheck == deadlineAfterNil,"Rejected events changed home policy or retry deadline")
// Unknown SSID must neither extend home trust nor defeat a retry backoff.
healthy = false; leaseSettings.mode = .on
_ = leaseService.handle(RPCRequest(command:"configure",settings:leaseSettings,network:leaseSample("cafe")))
let scheduledProbe = leaseService.nextCheck, probesAtBackoff = probes
_ = leaseNetwork(leaseSample(nil))
_ = leaseNetwork(leaseSample("cafe"))
_ = leaseNetwork(leaseSample("home",at:clock.addingTimeInterval(-30)))
check(probes == probesAtBackoff && leaseService.nextCheck == scheduledProbe,"Transient or rejected SSID samples defeated health backoff")
_ = leaseService.handle(RPCRequest(command:"stop",settings:nil,network:nil))
_ = wakeService.handle(RPCRequest(command:"stop",settings:nil,network:nil))
print("\(passed) checks including continuous sleep lease, clock rollback and rejected-observation backoff passed")

// Cross every mode/routing/link state with every other state. These are service
// transitions with the production decision code, not separate policy replicas.
let matrixGuard = GuardFake(), matrixTunnel = TunnelFake(), matrixRoutes = LeaseRoutes()
var matrixPhysical = PhysicalNetwork(interface:"en0",gateway:"192.168.1.1",service:"matrix")
let matrixService = Service(Installation(uid:501,cdhashes:[],engine:"unused"),protection:matrixGuard,managedTunnel:matrixTunnel,routing:matrixRoutes,physical:{matrixPhysical},health:{_ in true},stateDirectory:directory.path,monitoring:false,now:{clock},continuousNow:{clock.timeIntervalSince1970})
let modes: [Mode] = [.auto,.on,.off]
let routingModes: [RoutingMode] = [.all,.rules]
let links: [String?] = ["home","cafe",nil,"offline"]
var matrixTransitions = 0
func applyMatrix(_ mode:Mode,_ route:RoutingMode,_ link:String?) {
 clock += 1
 matrixPhysical = link == "offline" ? PhysicalNetwork() : PhysicalNetwork(interface:"en0",gateway:"192.168.1.1",service:"matrix")
 var candidate = settings; candidate.mode = mode; candidate.routing.mode = route
 let sample = NetworkObservation(available:matrixPhysical.available,interface:matrixPhysical.interface,ssid:link == "offline" ? nil : link,gateway:matrixPhysical.gateway,sampledAt:clock,sampledContinuouslyAt:clock.timeIntervalSince1970)
 let reply = matrixService.handle(RPCRequest(command:"configure",settings:candidate,network:sample))
 check(reply.ok,"Matrix transition returned an unexpected error")
 if mode == .off || (mode == .auto && link == "home") {
  check(!matrixGuard.active && !matrixTunnel.running && reply.status.phase == (mode == .off ? .off : .home),"Matrix direct transition left VPN or protection active")
 } else if link == "offline" {
  check(matrixGuard.active && reply.status.phase == .waiting,"Matrix disconnected transition lost protection")
 } else if mode == .on || link == "cafe" {
  check(matrixGuard.active && matrixTunnel.running && reply.status.phase == .connected,"Matrix VPN transition failed to connect under protection")
 } else {
  check((reply.status.phase == .home && !matrixGuard.active && !matrixTunnel.running) || (reply.status.phase == .connected && matrixGuard.active && matrixTunnel.running),"Matrix unknown SSID produced inconsistent status")
 }
 matrixTransitions += 1
}
for firstMode in modes { for firstRoute in routingModes { for firstLink in links {
 for secondMode in modes { for secondRoute in routingModes { for secondLink in links {
  applyMatrix(firstMode,firstRoute,firstLink)
  applyMatrix(secondMode,secondRoute,secondLink)
 } } }
} } }
_ = matrixService.handle(RPCRequest(command:"stop",settings:nil,network:nil))
print("\(passed) service checks passed, including \(matrixTransitions) mode/routing/link transitions")
