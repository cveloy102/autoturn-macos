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
let protection = GuardFake(), tunnel = TunnelFake()
let service = Service(Installation(uid:501,cdhashes:[],engine:"unused"),protection:protection,managedTunnel:tunnel,physical:{physical},health:{_ in true},stateDirectory:directory.path,monitoring:false)
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
print("\(passed) service transition checks passed: startup at home, VPN path events, on/auto/off, gateway changes, cleanup ordering and retries. No system network changes.")
