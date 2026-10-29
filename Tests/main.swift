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
let ipv4Core = try JSONSerialization.jsonObject(with:RoutingCoreConfiguration.make(routes,physicalInterface:"en0",physicalDNS:"192.168.1.53",tunnel:"utun3",dns:"1.1.1.1")) as! [String:Any]
for address in ["198.18.0.0","198.18.0.197","198.19.255.255","fc00::1","fc00:3fff::1"] {
    expect(Profile.isRoutingFakeIP(address),"Synthetic routing address accepted as a real endpoint: \(address)")
    do { _ = try profile.uapi(ip:address); fatalError("Synthetic endpoint reached UAPI") } catch {}
}
for address in ["198.17.255.255","198.20.0.0","192.0.2.1","fc00:4000::1","fd00::1"] {
    expect(!Profile.isRoutingFakeIP(address),"Real endpoint rejected outside fake-IP prefix: \(address)")
}
let ipv4Inbounds = ipv4Core["inbounds"] as! [[String:Any]]
expect(ipv4Inbounds[0]["address"] as? [String] == ["172.29.255.1/30"],"IPv4-only VPN falsely advertised IPv6 to Chrome")
let dualCore = try JSONSerialization.jsonObject(with:RoutingCoreConfiguration.make(routes,physicalInterface:"en0",physicalDNS:"192.168.1.53",tunnel:"utun3",dns:"1.1.1.1",supportsIPv6:true)) as! [String:Any]
let dualInbounds = dualCore["inbounds"] as! [[String:Any]]
expect((dualInbounds[0]["address"] as? [String])?.count == 2,"Dual-stack VPN lost IPv6 configuration")
var telegramRoutes = RoutingSettings(); telegramRoutes.mode = .rules
var telegramRule = RoutingRule(name:"Telegram",serviceID:"telegram",sourcePath:"source2/telegram.txt")
telegramRule.baseDomains = try RoutingPolicy.parseList("# mixed upstream\n149.154.160.0/20\n2001:67c:4e8::/48\ntelegram.org\nt.me\n")
telegramRule.ipRanges = ["192.0.2.0/24"]
telegramRoutes.rules = [telegramRule]; telegramRoutes = try telegramRoutes.validated()
expect(telegramRoutes.rules[0].baseDomains == ["t.me","telegram.org"],"Service IP ranges remained in domain list")
expect(telegramRoutes.rules[0].allIPRanges.count == 3,"Service IP ranges or manual additions lost")
expect(RoutingPolicy.addressDestination("149.154.167.51",settings:telegramRoutes) == .vpn,"Telegram IP not routed through VPN")
let telegramConfig = try JSONSerialization.jsonObject(with:RoutingCoreConfiguration.make(telegramRoutes,physicalInterface:"en0",physicalDNS:"192.168.1.53",tunnel:"utun3",dns:"1.1.1.1")) as! [String:Any]
let routeConfig = telegramConfig["route"] as! [String:Any]
expect(routeConfig["final"] as? String == "direct","Unselected or opaque traffic incorrectly defaults to VPN")
let coreRules = routeConfig["rules"] as! [[String:Any]]
expect(coreRules.contains { ($0["ip_cidr"] as? [String])?.contains("149.154.160.0/20") == true && $0["outbound"] as? String == "vpn" },"Imported service IP ranges absent from live core policy")
let roundTrip = try RoutingExport.read(JSONEncoder().encode(RoutingExport(routing:telegramRoutes)))
expect(roundTrip.rules == telegramRoutes.rules,"Export/import lost service IP ranges")
let oldRule = try JSONDecoder().decode(RoutingRule.self,from:Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Telegram\",\"baseDomains\":[\"149.154.160.0/20\",\"t.me\"],\"domains\":[],\"ipRanges\":[],\"destination\":\"vpn\",\"enabled\":true}".utf8))
var oldRoutes = RoutingSettings(); oldRoutes.rules = [oldRule]
let migratedRoutes = try oldRoutes.validated()
expect(migratedRoutes.rules[0].allDomains == ["t.me"] && migratedRoutes.rules[0].allIPRanges == ["149.154.160.0/20"],"Old mixed service rule could not be migrated")
print("\(passed) total checks including migration, domain/CIDR precedence, route export and input validation.")
let projectRoot = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
let seedData = try Data(contentsOf:projectRoot.appendingPathComponent("Resources/Routing/seed.json"))
let seedJSON = try JSONSerialization.jsonObject(with:seedData) as! [String:Any]
for seedService in seedJSON["services"] as! [[String:Any]] {
 var item = RoutingRule(name:seedService["name"] as! String,serviceID:seedService["id"] as? String,sourcePath:seedService["sourcePath"] as? String)
 item.baseDomains = seedService["domains"] as! [String]
 var settings = RoutingSettings(); settings.rules = [item]
 let accepted = try settings.validated()
 expect(!accepted.rules[0].allDomains.isEmpty || !accepted.rules[0].allIPRanges.isEmpty,"Bundled service cannot be added")
}
print("\(passed) checks including every actual bundled service passed")
let plainIPs = try RoutingIPImport.parse("# ChatGPT\n104.18.0.1\n2606:4700::/32\n104.18.0.1\n")
expect(plainIPs.count == 1 && plainIPs[0].ranges == ["104.18.0.1/32","2606:4700::/32"],"IP-list import lost IPv6 or duplicate handling")
let hydraIPs = try RoutingIPImport.parse("##ChatGPT\n/HydraRoute\n104.18.0.0/16\n\n##Disabled\n#/Other\n192.0.2.0/24\n\n##YouTube\n/Other\n203.0.113.1\n")
expect(hydraIPs.count == 2 && hydraIPs[0].name.contains("ChatGPT") && !hydraIPs.flatMap { $0.ranges }.contains("192.0.2.0/24"),"Hydra import merged groups or imported disabled block")
expect((try? RoutingIPImport.parse("chatgpt.com")) == nil,"Domain silently accepted as IP")
expect((try? RoutingIPImport.parse("/VPN\ngeoip:ru")) == nil,"Unsupported GeoIP directive silently accepted")
print("\(passed) checks including IP-list and Hydra block imports passed")

for minimumOS in ["13.-1", "13.+1", "13.0.-1", "13..0"] {
    var release = manifest; release.minimumOS = minimumOS
    do { _ = try Updater.validateMetadata(sign(release),publicKey:signingKey.publicKey.rawRepresentation,installedBuild:1); fatalError("Invalid OS component accepted") } catch { passed += 1 }
}
// A correctly signed bundle must include a universal routing engine too.
if let path = ProcessInfo.processInfo.environment["AT_TEST_BUNDLE"] {
    let app = URL(fileURLWithPath:path)
    let bundle = Bundle(url:app)!
    var release = manifest
    release.version = bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as! String
    release.build = Int(bundle.object(forInfoDictionaryKey:"CFBundleVersion") as! String)!
    try Updater.validateBundle(app,release:release); passed += 1
    // Reproduce a Mac without usable developer tools. codesign must still work.
    do {
        let previous = getenv("DEVELOPER_DIR").map { String(cString:$0) }
        setenv("DEVELOPER_DIR","/nonexistent-autoturn-developer-tools",1)
        defer { if let previous = previous { setenv("DEVELOPER_DIR",previous,1) } else { unsetenv("DEVELOPER_DIR") } }
        try Updater.validateBundle(app,release:release); passed += 1
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:temporary) }
    try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
    let incomplete = temporary.appendingPathComponent("AutoTurn.app")
    try FileManager.default.copyItem(at:app,to:incomplete)
    try FileManager.default.removeItem(at:incomplete.appendingPathComponent("Contents/Resources/routing-core"))
    let signer = Process(); signer.executableURL = URL(fileURLWithPath:"/usr/bin/codesign")
    signer.arguments = ["--force","--sign","-","--identifier","ru.hl100.autoturn",incomplete.path]
    signer.standardOutput = FileHandle.nullDevice; signer.standardError = FileHandle.nullDevice
    try signer.run(); signer.waitUntilExit()
    expect(signer.terminationStatus == 0,"Incomplete bundle fixture signing failed")
    do { try Updater.validateBundle(incomplete,release:release); fatalError("Updater accepted a signed bundle missing routing-core") } catch { passed += 1 }
    // A valid signature alone is insufficient: reject a signed, Intel-only core.
    let core = incomplete.appendingPathComponent("Contents/Resources/routing-core")
    let thinner = Process(); thinner.executableURL = URL(fileURLWithPath:"/usr/bin/lipo")
    thinner.arguments = [app.appendingPathComponent("Contents/Resources/routing-core").path,"-thin","x86_64","-output",core.path]
    try thinner.run(); thinner.waitUntilExit()
    expect(thinner.terminationStatus == 0,"Thin routing-core fixture creation failed")
    let coreSigner = Process(); coreSigner.executableURL = URL(fileURLWithPath:"/usr/bin/codesign")
    coreSigner.arguments = ["--force","--sign","-",core.path]
    try coreSigner.run(); coreSigner.waitUntilExit()
    expect(coreSigner.terminationStatus == 0,"Thin routing-core fixture signing failed")
    let bundleSigner = Process(); bundleSigner.executableURL = signer.executableURL; bundleSigner.arguments = signer.arguments
    try bundleSigner.run(); bundleSigner.waitUntilExit()
    expect(bundleSigner.terminationStatus == 0,"Thin bundle fixture signing failed")
    do { try Updater.validateBundle(incomplete,release:release); fatalError("Updater accepted a signed Intel-only routing-core") }
    catch { expect(error.localizedDescription.contains("routing-core") && error.localizedDescription.contains("arm64"),"Missing architecture error must identify component and architecture") }
}
print("\(passed) shared checks including malformed OS versions and optional update bundle validation passed")

var primarySettings = Settings()
var second = profile; second.id = UUID().uuidString; second.name = "Primary"
var third = profile; third.id = UUID().uuidString; third.name = "Reserve"
primarySettings.profiles = [profile,second,third]; primarySettings.selectedID = profile.id; primarySettings.primaryID = second.id
expect(primarySettings.connectionOrder.map(\.id) == [second.id,profile.id,third.id],"Primary profile was not first without losing reserve order")
let primaryRoundTrip = try JSONDecoder().decode(Settings.self,from:JSONEncoder().encode(primarySettings))
expect(primaryRoundTrip.primaryID == second.id,"Primary profile did not persist")
var legacyJSON = try JSONSerialization.jsonObject(with:JSONEncoder().encode(primarySettings)) as! [String:Any]
legacyJSON.removeValue(forKey:"primaryID")
let migratedPrimary = try JSONDecoder().decode(Settings.self,from:JSONSerialization.data(withJSONObject:legacyJSON))
expect(migratedPrimary.primaryProfileID == profile.id,"Legacy selection did not migrate to primary")
primarySettings.profiles.removeAll { $0.id == second.id }
expect(primarySettings.connectionOrder.map(\.id) == [profile.id,third.id],"Deleted primary produced an invalid profile order")
var ready = SetupReadiness()
expect(ready.stage == .keychain,"Setup skipped Keychain access")
ready.keychainReady = true; expect(ready.stage == .profile,"Setup skipped profile prerequisite")
ready.profileReady = true; expect(ready.stage == .location,"Setup skipped location access")
ready.locationGranted = true; expect(ready.stage == .service,"Setup skipped privileged service")
ready.serviceReady = true; expect(ready.stage == .notifications,"Setup skipped notification choice")
ready.notificationsSkipped = true; expect(ready.stage == .ready,"Optional notifications blocked VPN setup")
ready.locationGranted = false; expect(ready.stage == .location,"Revoked location permission was ignored after setup completion")
ready.locationRequired = false; expect(ready.stage == .ready,"Manual VPN unnecessarily required location")
ready.serviceReady = false; expect(ready.stage == .service,"Unavailable service was ignored after setup completion")
print("\(passed) shared checks including primary migration and permission revocation passed")
let imports = ProfileImportQueue()
let fileA = URL(fileURLWithPath:"/tmp/drop-one.conf"), fileB = URL(fileURLWithPath:"/tmp/drop-two.CONF")
expect(imports.enqueue([fileA,fileB]),"Profile drop was rejected while busy")
expect(imports.takeIfIdle(false) == nil && imports.count == 2,"Busy operation silently consumed dropped profiles")
expect(imports.enqueue([fileA]) && imports.count == 2,"Repeated drop duplicated a pending profile")
expect(imports.takeIfIdle(true)?.urls == [fileA,fileB] && imports.count == 0,"Deferred profile drop did not drain after operation finished")
expect(!imports.enqueue([URL(string:"https://example.com/profile.conf")!]),"Remote URL was treated as a user-authorized local profile file")
expect(!imports.enqueue([URL(fileURLWithPath:"/tmp/unrelated.txt")]),"Non-profile drop was accepted")
print("\(passed) shared checks including deferred profile drops passed")

expect(ProfileSelectionDecision.evaluate(target:"reserve",current:"main",busy:false,pending:false,phase:.connected) == .confirm,"Changing profile skipped confirmation")
expect(ProfileSelectionDecision.evaluate(target:"main",current:"main",busy:false,pending:false,phase:.connected) == .unchanged,"Current profile unnecessarily reconnects")
for phase in [Phase.connecting,.recovering] {
 expect(ProfileSelectionDecision.evaluate(target:"reserve",current:"main",busy:false,pending:false,phase:phase) == .wait,"In-flight connection allowed another profile switch")
}
expect(ProfileSelectionDecision.evaluate(target:"reserve",current:"main",busy:true,pending:false,phase:.connected) == .wait,"Unacknowledged configure allowed another switch")
expect(ProfileSelectionDecision.evaluate(target:"reserve",current:"main",busy:false,pending:true,phase:.connected) == .wait,"Pending switch was overwritten by stale connected status")
ready.locationRequired = true; ready.locationGranted = true; ready.locationChecked = false
expect(ready.stage == .location,"Unknown location check skipped onboarding")
ready.locationChecked = true; ready.serviceChecked = false
expect(ready.stage == .service,"Unfinished service check skipped onboarding")
ready.serviceChecked = true; ready.serviceInstalling = true
expect(ready.stage == .service,"In-progress service installation declared ready")
ready.serviceInstalling = false; ready.serviceReady = true
expect(ready.stage == .ready,"Granted permissions were not skipped")
print("\(passed) checks including profile confirmation policy and completed permission steps passed")

var autoState = SetupReadiness()
autoState.keychainReady = true; autoState.profileReady = true; autoState.locationGranted = true; autoState.notifications = .allowed
for mode in Mode.allCases {
 var startupSettings = Settings(); startupSettings.mode = mode
 var automation = SetupAutomation()
 expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == .service,"Missing service required a button in mode \(mode)")
 for _ in 0..<100 { expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == nil,"Cancelled/failed service setup repeated the native prompt") }
 expect(startupSettings.mode == mode,"Permission setup changed saved VPN mode")
}
var automation = SetupAutomation()
autoState.serviceChecked = false
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == nil,"Service install raced its initial availability check")
autoState.serviceChecked = true
expect(automation.next(autoState,busy:true,modal:false,canRequestLocation:false) == nil,"Busy startup started another permission prompt")
expect(automation.next(autoState,busy:false,modal:true,canRequestLocation:false) == nil,"Permission prompt interrupted a modal dialog")
autoState.serviceReady = true
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == nil,"Working service unnecessarily requested installation")
autoState.serviceReady = false; automation.deferred = true
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == nil,"Later did not defer automatic setup")
automation.deferred = false
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == .service,"Resumed setup never requested missing service")
automation = SetupAutomation(); autoState.locationGranted = false
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == nil,"Denied location permission was requested again")
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:true) == .location,"Missing location did not request native permission automatically")
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:true) == nil,"Native location prompt repeated")
autoState.locationGranted = true
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == .service,"Granting location did not advance to automatic service setup")
autoState.serviceReady = true; autoState.notifications = .notRequested
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == .notifications,"Ready service did not advance to notification prompt")
autoState.notifications = .allowed
expect(automation.next(autoState,busy:false,modal:false,canRequestLocation:false) == nil,"Already-complete setup repeated permission prompts")
print("\(passed) shared checks including automatic setup in Off/Auto/On and cancelled-prompt suppression passed")

func expectRoute(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    let result = try value(); expect(result,message)
}
let routeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at:routeDirectory) }
let routeStore = RoutingPersistence(directory:routeDirectory)
var originalRoutes = RoutingSettings(); originalRoutes.mode = .rules
originalRoutes.rules = [RoutingRule(name:"Saved VPN",domains:["saved.example"],destination:.vpn),RoutingRule(name:"Saved direct",ipRanges:["192.0.2.0/24"],destination:.direct)]
try expectRoute(try routeStore.load(fallback:originalRoutes) == originalRoutes,"Legacy Keychain routes did not migrate")
try expectRoute(try RoutingExport.read(Data(contentsOf:routeStore.currentURL)) == originalRoutes,"Independent current copy is not a usable route export")
try expectRoute(try routeStore.load(fallback:RoutingSettings()) == originalRoutes,"Old/empty Keychain snapshot erased routes after app replacement")
let permissions = try FileManager.default.attributesOfItem(atPath:routeStore.currentURL.path)[.posixPermissions] as! NSNumber
expect(permissions.intValue == 0o600,"Route backup is not private")
var editedRoutes = originalRoutes; editedRoutes.rules.append(RoutingRule(name:"Added",domains:["added.example"]))
try expectRoute(try routeStore.save(editedRoutes,expected:originalRoutes) == editedRoutes,"Route edit was not committed")
try expectRoute(try routeStore.save(originalRoutes,expected:originalRoutes) == editedRoutes,"Unrelated stale settings save erased a newer route list")
var conflictingRoutes = originalRoutes; conflictingRoutes.rules.removeLast()
do { _ = try routeStore.save(conflictingRoutes,expected:originalRoutes); fatalError("Concurrent route edits overwrote each other") }
catch let conflict as RoutingPersistenceConflict { expect(conflict.current == editedRoutes,"Conflict did not return the current route list") }
try expectRoute(try routeStore.save(editedRoutes,expected:originalRoutes) == editedRoutes,"Retry after failed Keychain persistence was not idempotent")
try expectRoute(try RoutingExport.read(Data(contentsOf:routeStore.previousURL)) == originalRoutes,"Previous route snapshot was not retained")
try Data("damaged current".utf8).write(to:routeStore.currentURL)
try expectRoute(try routeStore.load(fallback:RoutingSettings()) == originalRoutes,"Damaged current copy was not recovered from previous")
try expectRoute(try RoutingExport.read(Data(contentsOf:routeStore.currentURL)) == originalRoutes,"Recovered current copy was not repaired")
let clearedRoutes = RoutingSettings()
_ = try routeStore.save(clearedRoutes,expected:originalRoutes)
try expectRoute(try routeStore.load(fallback:editedRoutes) == clearedRoutes,"Explicitly deleted routes were silently resurrected")
try Data("damaged current".utf8).write(to:routeStore.currentURL)
try Data("damaged previous".utf8).write(to:routeStore.previousURL)
do { _ = try routeStore.load(fallback:RoutingSettings()); fatalError("Two damaged copies were overwritten with an empty list") }
catch is RoutingPersistenceFailure { expect(true,"Damaged copies correctly refused overwrite") }
try expectRoute(try String(contentsOf:routeStore.currentURL) == "damaged current","Damaged evidence was overwritten")
print("\(passed) shared checks including reinstall route preservation, stale writers, explicit deletion and backup recovery passed")

if let file = ProcessInfo.processInfo.environment["AT_TEST_ROUTES_EXPORT"] {
    let actual = try RoutingExport.read(Data(contentsOf:URL(fileURLWithPath:file)))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let first = RoutingPersistence(directory:directory)
    try expectRoute(try first.load(fallback:actual) == actual,"Actual exported routes changed during first migration")
    for _ in 0..<3 {
        let replacement = RoutingPersistence(directory:directory)
        try expectRoute(try replacement.load(fallback:RoutingSettings()) == actual,"App replacement erased actual exported routes")
        try expectRoute(try replacement.save(actual,expected:actual) == actual,"Unrelated settings save changed actual routes")
    }
    print("Actual route export preservation passed: \(actual.rules.count) rules, first migration and three simulated app replacements; system settings untouched")
}
