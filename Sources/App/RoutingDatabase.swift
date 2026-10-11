import Foundation

struct CatalogService: Codable {
    var id: String
    var name: String
    var cat: String
    var icon: String?
    var src: String
}
struct RoutingCatalog: Codable { var version: Int; var generated: String; var services: [CatalogService] }
struct ServiceDomains: Codable { var id: String; var name: String; var sourcePath: String; var domains: [String] }
struct RoutingSeed: Codable { var generated: String; var services: [ServiceDomains] }
struct RoutingDatabaseSnapshot: Codable { var catalog: RoutingCatalog; var services: [String:ServiceDomains]; var updatedAt: Date?; var commit: String? }

final class RoutingDatabase {
    static let upstream = "https://raw.githubusercontent.com/Ground-Zerro/Geo-Aggregator/"
    var snapshot: RoutingDatabaseSnapshot
    let cacheURL: URL
    init() {
        cacheURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AutoTurn/routing-database.json")
        let fallback = RoutingCatalog(version:1,generated:"",services:[])
        let catalog = Bundle.main.url(forResource:"catalog",withExtension:"json",subdirectory:"Routing").flatMap { try? Data(contentsOf:$0) }.flatMap { try? JSONDecoder().decode(RoutingCatalog.self,from:$0) } ?? fallback
        let seed = Bundle.main.url(forResource:"seed",withExtension:"json",subdirectory:"Routing").flatMap { try? Data(contentsOf:$0) }.flatMap { try? JSONDecoder().decode(RoutingSeed.self,from:$0) }
        snapshot = RoutingDatabaseSnapshot(catalog:catalog,services:Dictionary(uniqueKeysWithValues:(seed?.services ?? []).map { ($0.id,$0) }),updatedAt:nil,commit:nil)
        if let data = try? Data(contentsOf:cacheURL), data.count < 2000000, let saved = try? JSONDecoder().decode(RoutingDatabaseSnapshot.self,from:data), Self.validCatalog(saved.catalog), saved.services.values.allSatisfy({ RoutingPolicy.validSourcePath($0.sourcePath) && (try? RoutingPolicy.parseList($0.domains.joined(separator:"\n"))) != nil }) { snapshot = saved }
    }
    static func validCatalog(_ value: RoutingCatalog) -> Bool { value.version == 1 && value.services.count < 2000 && Set(value.services.map { $0.id }).count == value.services.count && value.services.allSatisfy { !$0.id.isEmpty && $0.id.utf8.count < 128 && !$0.name.isEmpty && $0.name.utf8.count < 128 && RoutingPolicy.validSourcePath($0.src) } }
    func find(_ text: String) -> CatalogService? {
        let q = text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        let aliases = ["youtube.com":"youtube","youtu.be":"youtube","telegram.org":"telegram","t.me":"telegram","chatgpt.com":"openai","chatgpt":"openai","openai.com":"openai","github.com":"github","discord.com":"discord","ютуб":"youtube","телеграм":"telegram"]
        let id = aliases[q] ?? q
        return snapshot.catalog.services.first { $0.id.lowercased() == id || $0.name.lowercased() == q } ?? snapshot.catalog.services.first { service in snapshot.services[service.id]?.domains.contains(q) == true }
    }
    private static func download(_ url: URL, limit: Int) throws -> Data {
        var request = URLRequest(url:url); request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource = 25; config.httpMaximumConnectionsPerHost = 2
        let session = URLSession(configuration:config); defer { session.invalidateAndCancel() }
        let done = DispatchSemaphore(value:0); var result: Result<Data,Error> = .failure(AppError.message("База не ответила"))
        let task = session.dataTask(with:request) { data,response,error in
            defer { done.signal() }
            if let error = error { result = .failure(error); return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let final = http.url, ["api.github.com","raw.githubusercontent.com"].contains(final.host ?? ""), final.scheme == "https", let data = data, data.count <= limit else { result = .failure(AppError.message("Источник базы вернул ошибку или слишком большой файл")); return }
            result = .success(data)
        }; task.resume()
        guard done.wait(timeout:.now()+26) == .success else { task.cancel(); throw AppError.message("Истекло время загрузки базы") }; return try result.get()
    }
    // Catalog and lists are fetched from one pinned Git commit. A partial failure
    // never replaces the currently working snapshot.
    func refresh(rules: [RoutingRule], completion: @escaping (Result<RoutingDatabaseSnapshot,Error>) -> Void) {
        let old = snapshot
        DispatchQueue.global(qos:.utility).async {
            let result = Result { () -> RoutingDatabaseSnapshot in
                let commitData = try Self.download(URL(string:"https://api.github.com/repos/Ground-Zerro/Geo-Aggregator/git/ref/heads/main")!,limit:300000)
                guard let json = try JSONSerialization.jsonObject(with:commitData) as? [String:Any], let object = json["object"] as? [String:Any], let sha = object["sha"] as? String, sha.range(of:"^[a-f0-9]{40}$",options:.regularExpression) != nil else { throw AppError.message("Не удалось определить версию базы") }
                let prefix = Self.upstream + sha + "/"
                let catalog = try JSONDecoder().decode(RoutingCatalog.self,from:Self.download(URL(string:prefix+"db/catalog.json")!,limit:400000))
                guard Self.validCatalog(catalog) else { throw AppError.message("Некорректный каталог сервисов") }
                var services = old.services
                let ids = Set(rules.compactMap { $0.serviceID })
                for id in ids {
                    guard let service = catalog.services.first(where: { $0.id == id }) else { throw AppError.message("Сервис \(id) исчез из базы; старые правила сохранены") }
                    let data = try Self.download(URL(string:prefix+service.src)!,limit:700000)
                    guard let text = String(data:data,encoding:.utf8) else { throw AppError.message("Некорректная кодировка базы") }
                    services[id] = ServiceDomains(id:id,name:service.name,sourcePath:service.src,domains:try RoutingPolicy.parseList(text))
                }
                var routing = RoutingSettings(); routing.rules = rules.map { rule in var r = rule; if let id = r.serviceID, let service = services[id] { r.baseDomains = service.domains; r.sourcePath = service.sourcePath }; return r }; _ = try routing.validated()
                return RoutingDatabaseSnapshot(catalog:catalog,services:services,updatedAt:Date(),commit:sha)
            }
            DispatchQueue.main.async {
                do { let value = try result.get(); try FileManager.default.createDirectory(at:self.cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true); try JSONEncoder().encode(value).write(to:self.cacheURL,options:.atomic); self.snapshot = value; completion(.success(value)) } catch { completion(.failure(error)) }
            }
        }
    }
}
