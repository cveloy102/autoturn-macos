import Foundation
var passed = 0
func check(_ value: Bool, _ message: String) { guard value else { fatalError(message) }; passed += 1 }
let youtube = CatalogService(id:"youtube",name:"YouTube",cat:"media",src:"source2/youtube.txt")
let twitter = CatalogService(id:"x",name:"X (Twitter)",cat:"social",src:"source2/x.txt")
let old = RoutingDatabaseSnapshot(catalog:RoutingCatalog(version:1,generated:"old",services:[youtube,twitter]),services:["youtube":ServiceDomains(id:"youtube",name:"YouTube",sourcePath:youtube.src,domains:["youtube.com"])],updatedAt:nil,commit:nil)
var existing = RoutingRule(name:"YouTube",serviceID:"youtube",sourcePath:youtube.src,baseDomains:["youtube.com"],domains:["manual.example"],ipRanges:["192.0.2.0/24"])
let incoming = RoutingRule(name:"X",serviceID:"x",sourcePath:twitter.src)
let reduced = RoutingCatalog(version:1,generated:"new",services:[])
var paths: [String] = []
let value = try RoutingDatabase.updatedSnapshot(old:old,catalog:reduced,rules:[existing,incoming],commit:"fixture") { path in
 paths.append(path); return path == twitter.src ? "x.com\ntwitter.com\n" : "youtube.com\nyoutu.be\n"
}
check(Set(value.catalog.services.map { $0.id }) == Set(["youtube","x"]),"Reduced upstream catalog hid existing services")
check(Set(value.services["x"]!.domains) == Set(["x.com","twitter.com"]),"X could not be added when YouTube was absent from upstream catalog")
check(Set(paths) == Set([youtube.src,twitter.src]),"Legacy list sources were not fetched at the pinned revision")
var routing = RoutingSettings();routing.rules = [existing,incoming]
for i in routing.rules.indices { if let id = routing.rules[i].serviceID,let service = value.services[id] { routing.rules[i].baseDomains = service.domains } }
routing = try routing.validated()
check(routing.rules[0].domains == ["manual.example"] && routing.rules[0].ipRanges == ["192.0.2.0/24"],"Refreshing service lists lost manual additions")
let fallback = try RoutingDatabase.updatedSnapshot(old:old,catalog:reduced,rules:[existing,incoming],commit:"fixture") { path in
 if path == youtube.src { throw AppError.message("Source unavailable") };return "x.com\ntwitter.com"
}
check(fallback.services["youtube"]?.domains == ["youtube.com"] && fallback.services["x"] != nil,"An unavailable old list blocked a new service")
check(fallback.warnings == ["YouTube"],"Cached fallback was not disclosed")
let changed = CatalogService(id:"youtube",name:"YouTube",cat:"media",src:"source1/youtube.txt")
let moved = try RoutingDatabase.updatedSnapshot(old:old,catalog:RoutingCatalog(version:1,generated:"new",services:[changed]),rules:[existing],commit:"fixture") { path in
 check(path == changed.src,"Remote source update was ignored");return "youtube.com"
}
check(moved.catalog.services.first { $0.id == "youtube" }?.src == changed.src,"Merged catalog duplicated or reverted updated service")
do {
 _ = try RoutingDatabase.updatedSnapshot(old:old,catalog:reduced,rules:[incoming],commit:"fixture") { _ in throw AppError.message("Offline") }
 fatalError("New uncached service succeeded without data")
} catch { passed += 1 }
check(old.services["x"] == nil,"Failed load changed the previous snapshot")
print("\(passed) routing database regressions passed: reduced catalog, X/Twitter addition, stale-list fallback and manual-rule preservation")
let restored = try RoutingDatabase.preservingCatalog(reduced,known:[youtube,twitter])
check(restored.services.contains { $0.id == "x" },"A reduced on-disk catalog hid bundled X after startup")
let emptyCache = RoutingDatabaseSnapshot(catalog:old.catalog,services:[:],updatedAt:nil,commit:nil)
let savedFallback = try RoutingDatabase.updatedSnapshot(old:emptyCache,catalog:reduced,rules:[existing],commit:"fixture") { _ in throw AppError.message("Offline") }
check(savedFallback.services["youtube"]?.domains == ["youtube.com"],"Manual additions became undeletable base domains during cache recovery")
print("\(passed) routing database checks including catalog recovery and clean manual/base separation passed")
if CommandLine.arguments.contains("--upstream") {
 let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
 let user = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AutoTurn")
 var cached = try JSONDecoder().decode(RoutingDatabaseSnapshot.self,from:Data(contentsOf:user.appendingPathComponent("routing-database.json")))
 let bundled = try JSONDecoder().decode(RoutingCatalog.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Routing/catalog.json")))
 cached.catalog = try RoutingDatabase.preservingCatalog(cached.catalog,known:bundled.services)
 let ref = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(string:"https://api.github.com/repos/Ground-Zerro/Geo-Aggregator/git/ref/heads/main")!)) as! [String:Any]
 let sha = (ref["object"] as! [String:Any])["sha"] as! String
 check(sha.range(of:"^[a-f0-9]{40}$",options:.regularExpression) != nil,"Invalid upstream commit")
 let prefix = "https://raw.githubusercontent.com/Ground-Zerro/Geo-Aggregator/"+sha+"/"
 let latest = try JSONDecoder().decode(RoutingCatalog.self,from:Data(contentsOf:URL(string:prefix+"db/catalog.json")!))
 var rules = try RoutingExport.read(Data(contentsOf:user.appendingPathComponent("routing-state/current.json"))).rules
 rules.append(RoutingRule(name:"X audit",serviceID:"x",sourcePath:"source2/x.txt"))
 let live = try RoutingDatabase.updatedSnapshot(old:cached,catalog:latest,rules:rules,commit:sha) { path in
  let data = try Data(contentsOf:URL(string:prefix+path)!);check(data.count<=700000,"Upstream list exceeds limit")
  return String(data:data,encoding:.utf8)!
 }
 check(live.services["x"]?.domains.contains("x.com") == true,"Real X list did not load")
 check(live.services["youtube"] != nil,"Real reduced catalog broke existing YouTube")
 print("PASS live upstream: X loaded alongside saved services; existing user route files untouched")
}
let copilot = RoutingRule(name:"GitHub Copilot",serviceID:"github-copilot",sourcePath:"source2/github-copilot.txt",baseDomains:["githubcopilot.com"])
let copilotResult = try RoutingDatabase.updatedSnapshot(old:emptyCache,catalog:reduced,rules:[copilot,incoming],commit:"fixture") { path in
 if path.contains("github-copilot") { throw AppError.message("404") }; return "x.com"
}
check(copilotResult.services["github-copilot"]?.domains == ["githubcopilot.com"] && copilotResult.services["x"] != nil,"Missing Copilot prevented adding another service")
let seedURL = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Routing/seed.json")
let seed = try JSONDecoder().decode(RoutingSeed.self,from:Data(contentsOf:seedURL))
for service in seed.services { _ = try RoutingPolicy.parseList(service.domains.joined(separator:"\n")) }
let google = CatalogService(id:"google",name:"Google",cat:"work",src:"source1/google.txt")
let googleSeed = seed.services.first { $0.id == "google" }!
check(googleSeed.domains.contains("google.com"),"Fresh installation has no Google domain seed")
check(seed.services.first { $0.id == "anthropic" }?.domains.contains("claude.ai") == true,"Fresh installation has no Claude domain seed")
let clean = RoutingDatabaseSnapshot(catalog:RoutingCatalog(version:1,generated:"",services:[google]),services:["google":googleSeed],updatedAt:nil,commit:nil)
let googleRule = RoutingRule(name:"Google",serviceID:google.id,sourcePath:google.src,baseDomains:["saved.google.example"],baseIPRanges:["192.0.2.0/24"],domains:["private.example"],ipRanges:["198.51.100.0/24"])
let ipOnly = try RoutingDatabase.updatedSnapshot(old:clean,catalog:clean.catalog,rules:[googleRule],commit:"fixture") { _ in "203.0.113.0/24" }
check(ipOnly.services["google"]!.domains.contains("google.com") && ipOnly.services["google"]!.domains.contains("saved.google.example"),"IP-only update erased domain rules")
check(!ipOnly.services["google"]!.domains.contains("192.0.2.0/24") && !ipOnly.services["google"]!.domains.contains("private.example"),"IP-only update retained stale IPs or promoted manual domains")
var damaged = RoutingSettings();damaged.rules = [googleRule];damaged.rules[0].baseDomains = []
let repaired = try RoutingDatabase.restoringMissingDomains(damaged,seed:seed.services)
check(repaired.rules[0].baseDomains.contains("google.com") && repaired.rules[0].baseIPRanges == googleRule.baseIPRanges && repaired.rules[0].domains == googleRule.domains && repaired.rules[0].ipRanges == googleRule.ipRanges,"Repair failed to restore domains while preserving IP/manual entries")
check(try RoutingDatabase.restoringMissingDomains(repaired,seed:seed.services) == repaired,"Domain repair is not idempotent")
var large = RoutingSettings()
large.rules = [RoutingRule(name:"Google",baseDomains:RoutingDatabase.domainPart(googleSeed.domains),baseIPRanges:(0..<8426).map { "10.\($0 / 256).\($0 % 256).0/24" }),RoutingRule(name:"GitHub",baseIPRanges:(0..<5293).map { "11.\($0 / 256).\($0 % 256).0/24" })]
_ = try large.validated()
check(large.rules.reduce(0) { $0 + $1.allDomains.count + $1.allIPRanges.count } > 12000,"Large-list regression did not exceed the old limit")
try JSONEncoder().encode(large.validated()).write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/routing-large-fixture.json"))
print("\(passed) routing database checks passed including Copilot, fresh Google/Claude, IP-only updates, automatic repair and Google + GitHub capacity")

let largeConfig = try RoutingCoreConfiguration.make(large,physicalInterface:"en0",physicalDNS:"127.0.0.1",tunnel:"utun1999",dns:"1.1.1.1")
let configURL = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/routing-large-core.json")
try largeConfig.write(to:configURL)
if let core = ProcessInfo.processInfo.environment["AT_TEST_ROUTING_CORE"] {
 let process = Process();process.executableURL = URL(fileURLWithPath:core);process.arguments = ["check","-c",configURL.path]
 try process.run();process.waitUntilExit();check(process.terminationStatus == 0,"Real routing core rejected Google + GitHub capacity")
 print("PASS native routing core accepted large Google + GitHub configuration")
}

let emptyResponse = try RoutingDatabase.updatedSnapshot(old:old,catalog:reduced,rules:[existing],commit:"fixture") { _ in "# temporarily empty" }
check(emptyResponse.services["youtube"]?.domains == ["youtube.com"] && emptyResponse.warnings == ["YouTube"],"Empty upstream erased working service lists")
let persistenceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("at-domain-migration-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at:persistenceDirectory) }
let persistence = RoutingPersistence(directory:persistenceDirectory)
let originalStored = try persistence.load(fallback:damaged)
let migrated = try RoutingDatabase.restoringMissingDomains(originalStored,seed:seed.services)
_ = try persistence.save(migrated,expected:originalStored)
check(try persistence.load(fallback:RoutingSettings()) == migrated,"Repaired routes did not survive persistence/restart")
var tooLarge = large
for index in 0..<3 { var rule = large.rules[0];rule.id = UUID().uuidString;rule.name = "Extra \(index)";tooLarge.rules.append(rule) }
do { _ = try tooLarge.validated();fatalError("Oversized route collection accepted") } catch { passed += 1 }
print("\(passed) routing database checks passed, including empty-source recovery, persisted migration and capacity rejection")

if let bundlePath = ProcessInfo.processInfo.environment["AT_TEST_BUNDLE"], let bundle = Bundle(path:bundlePath) {
 let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("at-clean-database-" + UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:cacheDirectory) }
 try FileManager.default.createDirectory(at:cacheDirectory,withIntermediateDirectories:true)
 let cache = cacheDirectory.appendingPathComponent("routing-database.json")
 let fresh = RoutingDatabase(cacheURL:cache,bundle:bundle)
 check(fresh.snapshot.services["google"]?.domains.contains("google.com") == true,"Actual fresh app bundle has no Google domains")
 var stale = fresh.snapshot
 stale.services["google"] = ServiceDomains(id:"google",name:"Google",sourcePath:google.src,domains:["203.0.113.0/24"])
 stale.catalog = reduced
 try JSONEncoder().encode(stale).write(to:cache)
 let recovered = RoutingDatabase(cacheURL:cache,bundle:bundle)
 check(recovered.snapshot.services["google"]?.domains.contains("google.com") == true && recovered.snapshot.services["google"]?.domains.contains("203.0.113.0/24") == true,"Cached IP-only Google did not recover its bundled domains")
 check(recovered.find("twitter.com")?.id == "x","Stale catalog hid X on relaunch")
 print("PASS clean bundle and IP-only cache recovery; no user cache changed")
}
