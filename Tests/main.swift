import Foundation
import CryptoKit

var passed = 0
func expect(_ condition: @autoclosure () -> Bool, _ text: String) { if !condition() { fatalError(text) }; passed += 1 }
func rejects(_ text: String) { do { _ = try Profile.parse(text,name:"test"); fatalError("Accepted invalid config") } catch { passed += 1 } }
let key = Data(repeating:7,count:32).base64EncodedString()
let config = """
[Interface]
PrivateKey=\(key)
Address=10.8.0.2/32, fd00::2/128
DNS=1.1.1.1, 2606:4700:4700::1111
Jc=4
Jmin=40
Jmax=70
S1=16
S2=17
S3=18
S4=19
H1=100-200
H2=300-400
H3=500-600
H4=700-800
I1=<b 0x1234><r 16>
I2=<r 32>
I3=<r 48>
I4=<r 64>
I5=<r 80>
HeaderProtectionKey=\(key)
ContentPaddingAddition=1-8
RandomTrailers=true
DisableCookies=true
[Peer]
PublicKey=\(key)
PresharedKey=\(key)
Endpoint=198.51.100.10:51820
AllowedIPs=192.168.1.0/24
PersistentKeepalive=22-30
"""
let profile = try Profile.parse(config,name:"Primary")
expect(profile.hasIPv6,"IPv6 address lost")
expect(profile.peer["allowedips"] == "0.0.0.0/0, ::/0","V1 must enforce full tunnel")
let uapi = try profile.uapi(ip:"198.51.100.10")
expect(uapi.contains("s3=18\n") && uapi.contains("s4=19\n"),"AWG 3.1 padding lost")
expect(uapi.contains("h1=100-200\n") && uapi.contains("i5=<r 80>\n"),"AWG 3.1 obfuscation lost")
expect(uapi.contains("header_protection_key=") && uapi.contains("content_padding_addition=1-8\n"),"AWG 3.1 protection lost")
expect(uapi.contains("allowed_ip=::/0\n"),"IPv6 bypassed")
expect(uapi.contains("persistent_keepalive_interval=22-30\n"),"AWG 3.1 keepalive range lost")
expect(!uapi.contains(key),"Base64 key not transformed")
let validated = try profile.validated()
expect(validated == profile,"Profile transport validation changed config")
rejects(config + "\nPostUp=touch /tmp/unsafe")
rejects(config.replacingOccurrences(of:"[Peer]",with:"[Interface]"))
rejects(config.replacingOccurrences(of:"H1=100-200",with:"H1=200-100"))
rejects(config.replacingOccurrences(of:"S4=19",with:"S4=99999999"))
rejects(config.replacingOccurrences(of:"DNS=1.1.1.1, 2606:4700:4700::1111",with:"DNS=evil.example"))
rejects(config.replacingOccurrences(of:"Endpoint=198.51.100.10:51820",with:"Endpoint=host;rm:51820"))
rejects(config.replacingOccurrences(of:"PrivateKey=\(key)",with:"PrivateKey=invalid"))
rejects(config + "\n[Peer]\nPublicKey=\(key)")
// Regression: real Amnezia exports on/off, whereas Go UAPI parses true/false.
for (input,expected) in [("on","true"),("off","false"),("yes","true"),("no","false"),("t","true"),("f","false"),("1","true"),("0","false"),("TrUe","true"),("FaLsE","false"),("ON","true"),("OFF","false")] {
    let variant = config.replacingOccurrences(of:"RandomTrailers=true",with:"RandomTrailers=\(input)").replacingOccurrences(of:"DisableCookies=true",with:"DisableCookies=\(input)")
    let parsed = try Profile.parse(variant,name:"Boolean test")
    expect(parsed.interface["randomtrailers"] == expected && parsed.interface["disablecookies"] == expected,"Config booleans were not normalized")
    let api = try parsed.uapi(ip:"198.51.100.10")
    expect(api.contains("random_trailers=\(expected)\n") && api.contains("disable_cookies=\(expected)\n"),"Go UAPI boolean serialization")
    let transported = try parsed.validated()
    expect(transported == parsed,"Helper validation changed boolean values")
}
rejects(config.replacingOccurrences(of:"RandomTrailers=true",with:"RandomTrailers=maybe"))
rejects(config.replacingOccurrences(of:"DisableCookies=true",with:"DisableCookies=2"))
let home = NetworkObservation(available:true,interface:"en0",ssid:"Home",gateway:"192.168.1.1")
let away = NetworkObservation(available:true,interface:"en0",ssid:"Cafe",gateway:"192.168.2.1")
let offline = NetworkObservation(available:false,interface:nil,ssid:"Home",gateway:nil)
let unknown = NetworkObservation(available:true,interface:"en0",ssid:nil,gateway:"192.168.1.1")
expect(!Policy.wantsVPN(mode:.auto,network:home,homes:["Home"]),"Home should use router")
expect(Policy.wantsVPN(mode:.auto,network:away,homes:["Home"]),"Away must use VPN")
expect(Policy.wantsVPN(mode:.auto,network:offline,homes:["Home"]),"Offline must retain protection")
expect(Policy.wantsVPN(mode:.auto,network:unknown,homes:["Home"]),"Unknown SSID must not be trusted")
expect(Policy.wantsVPN(mode:.on,network:home,homes:["Home"]),"Manual on lost")
expect(!Policy.wantsVPN(mode:.off,network:away,homes:["Home"]),"Explicit off lost")
expect(Policy.next(index:0,count:1) == 0,"One profile must retry itself")
expect(Policy.next(index:2,count:3) == 0,"Failover cycle broken")
expect(Policy.retryDelay(round:0) == 30 && Policy.retryDelay(round:1) == 60 && Policy.retryDelay(round:8) == 120,"Backoff broken")
let signingKey = Curve25519.Signing.PrivateKey()
let manifest = MacRelease(version:"0.2.0",build:2,minimumOS:"13.0",archiveURL:"https://github.com/cveloy102/autoturn-macos/releases/download/macos-v0.2.0/AutoTurn.zip",sha256:String(repeating:"0",count:64),signature:"unused",notes:"test")
func sign(_ release: MacRelease) throws -> Data { let payload = try JSONEncoder().encode(release); return try JSONEncoder().encode(SignedRelease(payload:payload.base64EncodedString(),signature:try signingKey.signature(for:payload).base64EncodedString())) }
let validEnvelope = try sign(manifest)
let verified = try Updater.validateMetadata(validEnvelope,publicKey:signingKey.publicKey.rawRepresentation,installedBuild:1)
expect(verified?.build == 2,"Valid signed release rejected")
let old = try Updater.validateMetadata(validEnvelope,publicKey:signingKey.publicKey.rawRepresentation,installedBuild:3)
expect(old == nil,"Updater offered downgrade")
do { _ = try Updater.validateMetadata(validEnvelope,publicKey:Curve25519.Signing.PrivateKey().publicKey.rawRepresentation,installedBuild:1); fatalError("Wrong signer accepted") } catch { passed += 1 }
var invalid = manifest; invalid.archiveURL = "https://evil.example/AutoTurn.zip"
do { _ = try Updater.validateMetadata(sign(invalid),publicKey:signingKey.publicKey.rawRepresentation,installedBuild:1); fatalError("Unapproved host accepted") } catch { passed += 1 }
invalid = manifest; invalid.minimumOS = "13.foo"
do { _ = try Updater.validateMetadata(sign(invalid),publicKey:signingKey.publicKey.rawRepresentation,installedBuild:1); fatalError("Invalid minimum OS accepted") } catch { passed += 1 }
invalid = manifest; invalid.minimumOS = "99.0"
do { _ = try Updater.validateMetadata(sign(invalid),publicKey:signingKey.publicKey.rawRepresentation,installedBuild:1); fatalError("Incompatible OS accepted") } catch { passed += 1 }
var altered = try JSONDecoder().decode(SignedRelease.self,from:validEnvelope)
var alteredPayload = Data(base64Encoded:altered.payload)!; alteredPayload[0] ^= 1; altered.payload = alteredPayload.base64EncodedString()
do { _ = try Updater.validateMetadata(JSONEncoder().encode(altered),publicKey:signingKey.publicKey.rawRepresentation,installedBuild:1); fatalError("Altered metadata accepted") } catch { passed += 1 }
let now = Date(timeIntervalSince1970:1_800_000_000)
expect(UpdateHistory.isDue(now:now,lastSuccess:nil,lastAttempt:nil),"Initial update check missing")
expect(!UpdateHistory.isDue(now:now,lastSuccess:now.addingTimeInterval(-3599),lastAttempt:nil),"Hourly check ran early")
expect(UpdateHistory.isDue(now:now,lastSuccess:now.addingTimeInterval(-3600),lastAttempt:nil),"Hourly check did not run at one hour")
expect(!UpdateHistory.isDue(now:now,lastSuccess:nil,lastAttempt:now.addingTimeInterval(-3599)),"Failed check retried too soon")
expect(UpdateHistory.isDue(now:now,lastSuccess:nil,lastAttempt:now.addingTimeInterval(-3600)),"Failed check never retried")
expect(UpdateHistory.isDue(now:now,lastSuccess:now.addingTimeInterval(1000),lastAttempt:now.addingTimeInterval(1000)),"Clock change blocked checks indefinitely")
let suite = "AutoTurn-tests-" + UUID().uuidString
let defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
let history = UpdateHistory(defaults)
expect(history.shouldNotify(6),"New update notification suppressed")
history.notified(6)
expect(!history.shouldNotify(6) && !history.shouldNotify(5) && history.shouldNotify(7),"Repeated/downgrade notification or next release suppressed")
history.notified(version:"1.2.3",build:10)
expect(!UpdateHistory(defaults).shouldNotify(version:"1.2.3",build:11),"Same version notified again with a new build")
expect(UpdateHistory(defaults).shouldNotify(version:"1.2.4",build:12),"New version notification suppressed")
history.attempted(at:now); expect(!history.isDue(at:now),"Attempt history not persisted")
history.succeeded(at:now); expect(!UpdateHistory(defaults).isDue(at:now.addingTimeInterval(3599)),"Relaunch forgot successful check")
let archiveData = Data("signed test archive".utf8)
var archiveRelease = manifest
archiveRelease.sha256 = SHA256.hash(data:archiveData).map { String(format:"%02x",$0) }.joined()
archiveRelease.signature = try signingKey.signature(for:archiveData).base64EncodedString()
try Updater.validateArchive(archiveData,release:archiveRelease,publicKey:signingKey.publicKey.rawRepresentation); passed += 1
do { try Updater.validateArchive(Data("altered archive".utf8),release:archiveRelease,publicKey:signingKey.publicKey.rawRepresentation); fatalError("Altered archive accepted") } catch { passed += 1 }
do { try Updater.validateArchive(archiveData,release:archiveRelease,publicKey:Curve25519.Signing.PrivateKey().publicKey.rawRepresentation); fatalError("Wrong archive signer accepted") } catch { passed += 1 }
let loginTestDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at:loginTestDirectory) }
expect(!LoginRegistration.existing(in:loginTestDirectory),"missing login agent enabled")
try LoginRegistration.set(true,in:loginTestDirectory)
expect(LoginRegistration.existing(in:loginTestDirectory),"login choice not registered")
let loginFile = loginTestDirectory.appendingPathComponent(LoginRegistration.label + ".plist")
let registered = try PropertyListSerialization.propertyList(from:Data(contentsOf:loginFile),format:nil) as! [String:Any]
expect(registered["ProgramArguments"] as? [String] == ["/usr/bin/open","-g","-a","/Applications/AutoTurn.app","--args","--background"],"login did not launch app through LaunchServices")
try LoginRegistration.set(true,in:loginTestDirectory)
expect(LoginRegistration.existing(in:loginTestDirectory),"repeated registration lost preference")
let legacy:[String:Any] = ["Label":LoginRegistration.label,"ProgramArguments":["/Applications/AutoTurn.app/Contents/MacOS/AutoTurn","--background"],"RunAtLoad":true]
try PropertyListSerialization.data(fromPropertyList:legacy,format:.xml,options:0).write(to:loginFile)
expect(LoginRegistration.existing(in:loginTestDirectory),"previous login registration not migrated")
try LoginRegistration.set(true,in:loginTestDirectory)
expect(LoginRegistration.existing(in:loginTestDirectory),"migration lost registration")
try LoginRegistration.set(false,in:loginTestDirectory)
expect(!LoginRegistration.existing(in:loginTestDirectory),"explicit login Off was undone")
try LoginRegistration.set(false,in:loginTestDirectory)
expect(!FileManager.default.fileExists(atPath:loginFile.path),"login Off is not idempotent")
print("\(passed) checks passed: AWG 3.1 parser, full tunnel, home policy, failover order, retries, update signatures, downgrade/host/OS rejection")

let legacySettings = try JSONDecoder().decode(Settings.self,from:Data("{\"mode\":\"off\",\"homeSSIDs\":[\"Keen_5G\"],\"profiles\":[],\"launchAtLogin\":true}".utf8))
expect(legacySettings.mode == .off && legacySettings.homeSSIDs == ["Keen_5G"] && legacySettings.launchAtLogin && legacySettings.routing.mode == .all,"Routing migration reset user settings")
var routes = RoutingSettings(); routes.mode = .rules
routes.rules = [RoutingRule(name:"YouTube",domains:["youtube.com","googlevideo.com"]),RoutingRule(name:"Specific direct",domains:["help.youtube.com"],destination:.direct)]
expect(RoutingPolicy.destination(for:"r1.googlevideo.com",settings:routes) == .vpn,"Subdomain not matched")
expect(RoutingPolicy.destination(for:"notyoutube.com",settings:routes) == .direct,"Domain suffix crossed label boundary")
expect(RoutingPolicy.destination(for:"help.youtube.com",settings:routes) == .direct,"Specific direct rule ignored")
routes.rules.append(RoutingRule(name:"Safe tie",domains:["help.youtube.com"]))
expect(RoutingPolicy.destination(for:"help.youtube.com",settings:routes) == .vpn,"Equal rule conflict leaked VPN domain")
expect(RoutingPolicy.contains("192.0.2.12",cidr:"192.0.2.0/24") && !RoutingPolicy.contains("192.0.3.12",cidr:"192.0.2.0/24"),"IPv4 subnet matching wrong")
expect(RoutingPolicy.contains("2001:db8::1",cidr:"2001:db8::/32") && !RoutingPolicy.contains("2001:db9::1",cidr:"2001:db8::/32"),"IPv6 subnet matching wrong")
for invalid in ["https://youtube.com/path","evil.example; pass all","a..example","127.0.0.1","-bad.example"] {
 do { _ = try RoutingPolicy.normalizeDomain(invalid); fatalError("Invalid domain accepted") } catch { passed += 1 }
}
let normalizedDomain = try RoutingPolicy.normalizeDomain("*.Example.COM.")
expect(normalizedDomain == "example.com","Domain normalization wrong")
let imported = try RoutingExport.read(JSONEncoder().encode(RoutingExport(routing:routes)))
expect(imported.rules == routes.rules,"Route import/export lost rules")
let routeJSON = String(data:try JSONEncoder().encode(RoutingExport(routing:routes)),encoding:.utf8)!
expect(!routeJSON.contains("privatekey") && !routeJSON.contains("profiles"),"Route export included VPN keys")
expect(!RoutingPolicy.validSourcePath("../../secret") && RoutingPolicy.validSourcePath("source2/youtube.txt"),"Database source traversal allowed")
print("\(passed) total checks including migration, domain/CIDR precedence, route export and input validation.")
