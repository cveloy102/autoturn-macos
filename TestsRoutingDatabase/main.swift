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
