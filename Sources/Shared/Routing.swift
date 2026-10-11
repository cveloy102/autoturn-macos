import Foundation
import Darwin

enum RoutingMode: String, Codable { case all, rules }
enum RouteDestination: String, Codable { case vpn, direct }
struct RoutingRule: Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var serviceID: String?
    var sourcePath: String?
    var baseDomains: [String] = []
    var baseIPRanges: [String]?
    var domains: [String] = []
    var ipRanges: [String] = []
    var destination: RouteDestination = .vpn
    var enabled = true
    var allDomains: [String] { Array(Set((baseDomains + domains).filter { !Profile.validCIDR($0) && !Profile.isIP($0) })).sorted() }
    var allIPRanges: [String] { Array(Set((baseIPRanges ?? []) + ipRanges + baseDomains.compactMap { Profile.validCIDR($0) ? $0 : Profile.isIP($0) ? $0 + ($0.contains(":") ? "/128" : "/32") : nil })).sorted() }
}
struct RoutingSettings: Codable, Equatable {
    var mode: RoutingMode = .all
    var rules: [RoutingRule] = []
    var databaseUpdatedAt: Date?
    var automaticDatabaseUpdates = true
    func validated() throws -> RoutingSettings {
        guard rules.count <= 128, Set(rules.map { $0.id }).count == rules.count else { throw AppError.message("Максимум 128 уникальных правил") }
        var copy = self
        copy.rules = try rules.map { rule in
            guard UUID(uuidString:rule.id) != nil, !rule.name.isEmpty, rule.name.utf8.count <= 128, rule.ipRanges.count <= 2048 else { throw AppError.message("Некорректное правило маршрутизации") }
            var r = rule
            r.baseDomains = try rule.baseDomains.filter { !Profile.validCIDR($0) && !Profile.isIP($0) }.map(RoutingPolicy.normalizeDomain)
            let baseRanges = Array(Set((rule.baseIPRanges ?? []) + rule.baseDomains.compactMap { Profile.validCIDR($0) ? $0 : Profile.isIP($0) ? $0 + ($0.contains(":") ? "/128" : "/32") : nil })).sorted()
            r.baseIPRanges = baseRanges.isEmpty ? rule.baseIPRanges : baseRanges
            r.domains = try rule.domains.map(RoutingPolicy.normalizeDomain)
            guard r.allIPRanges.count <= 12000, r.allIPRanges.allSatisfy(Profile.validCIDR), r.serviceID == nil || r.sourcePath.map(RoutingPolicy.validSourcePath) == true else { throw AppError.message("Некорректный источник или IP-подсеть") }
            return r
        }
        guard copy.rules.reduce(0, { $0 + $1.allDomains.count + $1.allIPRanges.count }) <= 12000, (try JSONEncoder().encode(copy)).count <= 700000 else { throw AppError.message("Список слишком большой: максимум 12 000 доменов и IP-подсетей") }
        return copy
    }
}
struct RoutingExport: Codable {
    var format = "hl100.autoturn.routes"
    var version = 1
    var routing: RoutingSettings
    static func read(_ data: Data) throws -> RoutingSettings {
        guard data.count <= 800000 else { throw AppError.message("Файл маршрутов слишком большой") }
        let file = try JSONDecoder().decode(Self.self,from:data)
        guard file.format == "hl100.autoturn.routes", file.version == 1 else { throw AppError.message("Неподдерживаемый формат маршрутов") }
        return try file.routing.validated()
    }
}
enum RoutingPolicy {
    static func normalizeDomain(_ value: String) throws -> String {
        var text = value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        if text.hasPrefix("*.") { text.removeFirst(2) }
        if text.hasSuffix(".") { text.removeLast() }
        guard text.utf8.count <= 253, text.contains("."), !Profile.isIP(text), text.split(separator:".",omittingEmptySubsequences:false).allSatisfy({ p in !p.isEmpty && p.utf8.count <= 63 && p.first != "-" && p.last != "-" && p.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { throw AppError.message("Укажи домен без https:// и пути: например youtube.com. Для международного имени используй punycode.") }
        return text
    }
    static func validSourcePath(_ path: String) -> Bool { path.range(of:"^source[12]/[a-zA-Z0-9_-]+\\.txt$",options:.regularExpression) != nil }
    static func matches(_ domain: String, suffix: String) -> Bool { domain == suffix || domain.hasSuffix("." + suffix) }
    static func destination(for domain: String, settings: RoutingSettings) -> RouteDestination {
        guard settings.mode == .rules else { return .vpn }
        let name = domain.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:"."))
        // Most specific suffix wins. On equal specificity VPN wins conservatively.
        var best = -1, result = RouteDestination.direct
        for rule in settings.rules where rule.enabled {
            for suffix in rule.allDomains where matches(name,suffix:suffix) {
                if suffix.count > best || suffix.count == best && rule.destination == .vpn { best = suffix.count; result = rule.destination }
            }
        }
        return result
    }
    static func addressDestination(_ ip: String, settings: RoutingSettings) -> RouteDestination? {
        var result: RouteDestination?
        for rule in settings.rules where rule.enabled { for range in rule.allIPRanges where contains(ip,cidr:range) { if rule.destination == .vpn { return .vpn }; result = .direct } }
        return result
    }
    static func contains(_ ip: String, cidr: String) -> Bool {
        let p = cidr.split(separator:"/"); guard p.count == 2, let prefix = Int(p[1]), Profile.validCIDR(cidr), Profile.isIP(ip), ip.contains(":") == p[0].contains(":") else { return false }
        var a = [UInt8](repeating:0,count:16), b = a
        let family = ip.contains(":") ? AF_INET6 : AF_INET
        ip.withCString { _ = inet_pton(family,$0,&a) }; String(p[0]).withCString { _ = inet_pton(family,$0,&b) }
        for bit in 0..<prefix { let mask = UInt8(1 << (7-bit%8)); if a[bit/8] & mask != b[bit/8] & mask { return false } }; return true
    }
    static func parseList(_ text: String) throws -> [String] {
        guard text.utf8.count <= 700000 else { throw AppError.message("Список сервиса слишком большой") }
        var result = Set<String>()
        for raw in text.components(separatedBy:.newlines) {
            let line = raw.trimmingCharacters(in:.whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if Profile.validCIDR(line) { result.insert(line) }
            else if Profile.isIP(line) { result.insert(line + (line.contains(":") ? "/128" : "/32")) }
            else { result.insert(try normalizeDomain(line)) }
        }
        guard !result.isEmpty else { throw AppError.message("Источник вернул пустой список доменов") }
        return result.sorted()
    }
}

struct RoutingIPBlock {
    var name: String
    var ranges: [String]
}
enum RoutingIPImport {
    static func parse(_ text: String) throws -> [RoutingIPBlock] {
        guard text.utf8.count <= 700000 else { throw AppError.message("IP-список слишком большой") }
        let lines = text.components(separatedBy:.newlines)
        let hydra = lines.contains { $0.trimmingCharacters(in:.whitespaces).hasPrefix("/") || $0.trimmingCharacters(in:.whitespaces).hasPrefix("#/") }
        var blocks: [RoutingIPBlock] = [], ranges = Set<String>(), name = "IP-список", enabled = !hydra, description = ""
        func flush() { if !ranges.isEmpty { blocks.append(RoutingIPBlock(name:name,ranges:ranges.sorted())); ranges.removeAll() } }
        for (index,raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in:.whitespacesAndNewlines)
            if line.hasPrefix("##") { if hydra { flush(); enabled = false }; description = String(line.dropFirst(2)).trimmingCharacters(in:.whitespaces); continue }
            if line.hasPrefix("#/") { flush(); enabled = false; continue }
            if line.hasPrefix("/") { flush(); enabled = true; name = description.isEmpty ? String(line.dropFirst()) : description + " · " + String(line.dropFirst()); description = ""; continue }
            if line.isEmpty { if hydra { flush(); enabled = false }; continue }
            if line.hasPrefix("#") || !enabled { continue }
            guard !line.hasPrefix("geoip:") else { throw AppError.message("GeoIP-директивы требуют готового списка IP/CIDR. Экспортируй адреса, а не geoip:тег.") }
            if Profile.validCIDR(line) { ranges.insert(line) }
            else if Profile.isIP(line) { ranges.insert(line + (line.contains(":") ? "/128" : "/32")) }
            else { throw AppError.message("Некорректный IP или CIDR в строке \(index + 1)") }
            guard ranges.count <= 2048 else { throw AppError.message("В дополнениях допускается до 2048 IP/подсетей") }
        }
        flush(); guard !blocks.isEmpty else { throw AppError.message("В файле нет включённых IP-адресов или подсетей") }; return blocks
    }
}
