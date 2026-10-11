import Foundation
import Darwin

enum AppError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum Mode: String, Codable, CaseIterable { case auto, on, off }
enum Phase: String, Codable { case setup, home, connecting, connected, waiting, recovering, off, error }

struct Profile: Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var addresses: [String]
    var dns: [String]
    var mtu: Int
    var interface: [String: String]
    var peer: [String: String]
    var endpointHost: String
    var endpointPort: Int
    var resolvedIP: String?

    static func parse(_ text: String, name: String) throws -> Profile {
        guard text.utf8.count <= 128 * 1024 else { throw AppError.message("Конфигурация слишком большая") }
        var section = "", fields: [String: [String: String]] = [:]
        let interfaceKeys: Set<String> = ["privatekey", "address", "dns", "mtu", "listenport", "jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5", "headerprotectionkey", "contentpaddingaddition", "rekeyaftertime", "rekeytimeout", "rejectaftertime", "keepalivetimeout", "maxhandshakeattempts", "randomtrailers", "disablecookies"]
        let peerKeys: Set<String> = ["publickey", "presharedkey", "endpoint", "allowedips", "persistentkeepalive"]
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if let comment = line.range(of: " #") { line = String(line[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("[") {
                guard ["[Interface]", "[Peer]"].contains(line), fields[line] == nil else { throw AppError.message("Нужны одна секция Interface и один Peer") }
                section = line; fields[section] = [:]; continue
            }
            guard !section.isEmpty, let equal = line.firstIndex(of: "=") else { throw AppError.message("Некорректная строка конфигурации") }
            let key = String(line[..<equal]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: equal)...]).trimmingCharacters(in: .whitespaces)
            guard (section == "[Interface]" ? interfaceKeys : peerKeys).contains(key) else { throw AppError.message("Параметр \(key) пока не поддерживается. Конфигурация не импортирована.") }
            guard fields[section]?[key] == nil, !value.isEmpty, !value.contains("\0"), value.utf8.count < 16384 else { throw AppError.message("Некорректный или повторный параметр \(key)") }
            fields[section]?[key] = value
        }
        guard var iface = fields["[Interface]"], var peer = fields["[Peer]"] else { throw AppError.message("Нет Interface или Peer") }
        for (key, value) in [("privatekey", iface["privatekey"]), ("publickey", peer["publickey"])] {
            guard let value = value, let data = Data(base64Encoded: value), data.count == 32 else { throw AppError.message("Некорректный \(key)") }
        }
        if let key = peer["presharedkey"], Data(base64Encoded: key)?.count != 32 { throw AppError.message("Некорректный PresharedKey") }
        if let key = iface["headerprotectionkey"], Data(base64Encoded: key)?.count != 32 { throw AppError.message("Некорректный HeaderProtectionKey") }
        let addresses = list(iface.removeValue(forKey: "address") ?? "")
        guard !addresses.isEmpty, addresses.allSatisfy(validCIDR) else { throw AppError.message("Некорректный Address") }
        let dns = list(iface.removeValue(forKey: "dns") ?? "")
        guard !dns.isEmpty, dns.allSatisfy(isIP) else { throw AppError.message("Укажи IP-адрес DNS в конфигурации") }
        let mtuText = iface.removeValue(forKey: "mtu") ?? "1280"
        guard let mtu = Int(mtuText), (1280...1500).contains(mtu) else { throw AppError.message("MTU должен быть от 1280 до 1500") }
        guard let endpoint = peer.removeValue(forKey: "endpoint"), let colon = endpoint.lastIndex(of: ":"), let port = Int(endpoint[endpoint.index(after: colon)...]), (1...65535).contains(port) else { throw AppError.message("Некорректный Endpoint") }
        var host = String(endpoint[..<colon]); if host.hasPrefix("[") && host.hasSuffix("]") { host.removeFirst(); host.removeLast() }
        guard !host.isEmpty, host.utf8.count <= 253, host.range(of: "^[A-Za-z0-9.:-]+$", options: .regularExpression) != nil else { throw AppError.message("Некорректный адрес сервера") }
        let allowed = list(peer.removeValue(forKey: "allowedips") ?? "")
        guard !allowed.isEmpty, allowed.allSatisfy(validCIDR) else { throw AppError.message("Некорректный AllowedIPs") }
        // V1 deliberately routes all traffic; IPv6 is blocked when no IPv6 tunnel address exists.
        peer["allowedips"] = "0.0.0.0/0, ::/0"
        for key in ["listenport", "jc", "jmin", "jmax", "s1", "s2", "s3", "s4"] {
            if let value = iface[key] { guard let n = UInt32(value), !key.hasPrefix("s") || n <= 65535, key != "listenport" || n <= 65535 else { throw AppError.message("Некорректный \(key)") } }
        }
        for key in ["h1", "h2", "h3", "h4", "contentpaddingaddition", "rekeyaftertime", "rekeytimeout", "rejectaftertime", "keepalivetimeout", "maxhandshakeattempts"] {
            if let value = iface[key] { let parts = value.components(separatedBy: "-"); guard (1...2).contains(parts.count), parts.allSatisfy({ UInt32($0) != nil }), parts.count == 1 || UInt32(parts[0])! <= UInt32(parts[1])! else { throw AppError.message("Некорректный диапазон \(key)") } }
        }
        // Configuration files use on/off; the Go engine's UAPI expects canonical booleans.
        for key in ["randomtrailers", "disablecookies"] {
            guard let value = iface[key] else { continue }
            switch value.lowercased() {
            case "on", "yes", "true", "t", "1": iface[key] = "true"
            case "off", "no", "false", "f", "0": iface[key] = "false"
            default: throw AppError.message("Некорректный \(key): нужны on/off, yes/no, true/false или 1/0")
            }
        }
        if let value = peer["persistentkeepalive"] { let parts = value.components(separatedBy:"-"); guard (1...2).contains(parts.count), parts.allSatisfy({UInt32($0) != nil}), parts.count == 1 || UInt32(parts[0])! <= UInt32(parts[1])! else { throw AppError.message("Некорректный PersistentKeepalive") } }
        if let low = iface["jmin"], let high = iface["jmax"], UInt32(low)! > UInt32(high)! { throw AppError.message("Jmin больше Jmax") }
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        return Profile(name: cleanName.isEmpty ? "AmneziaWG" : cleanName, addresses: addresses, dns: dns, mtu: mtu, interface: iface, peer: peer, endpointHost: host, endpointPort: port, resolvedIP: isIP(host) ? host : nil)
    }

    var hasIPv6: Bool { addresses.contains { $0.contains(":") } }
    func validated() throws -> Profile {
        let host = endpointHost.contains(":") ? "[\(endpointHost)]" : endpointHost
        var lines = ["[Interface]", "Address=\(addresses.joined(separator: ","))", "DNS=\(dns.joined(separator: ","))", "MTU=\(mtu)"]
        for key in interface.keys.sorted() { lines.append("\(key)=\(interface[key]!)") }
        lines += ["[Peer]", "Endpoint=\(host):\(endpointPort)"]
        for key in peer.keys.sorted() { lines.append("\(key)=\(peer[key]!)") }
        guard lines.allSatisfy({ !$0.contains("\n") && !$0.contains("\r") }), UUID(uuidString: id) != nil else { throw AppError.message("Некорректные данные профиля") }
        var copy = try Profile.parse(lines.joined(separator: "\n"), name: name); copy.id = id
        if let ip = resolvedIP { guard Profile.isIP(ip) else { throw AppError.message("Некорректный IP сервера") }; copy.resolvedIP = ip }
        return copy
    }
    func uapi(ip: String) throws -> String {
        guard Profile.isIP(ip) else { throw AppError.message("Сервер ещё не разрешён в IP") }
        let mapping = ["privatekey":"private_key", "listenport":"listen_port", "headerprotectionkey":"header_protection_key", "contentpaddingaddition":"content_padding_addition", "rekeyaftertime":"rekey_after_time", "rekeytimeout":"rekey_timeout", "rejectaftertime":"reject_after_time", "keepalivetimeout":"keepalive_timeout", "maxhandshakeattempts":"max_handshake_attempts", "randomtrailers":"random_trailers", "disablecookies":"disable_cookies"]
        var lines = ["set=1"]
        for key in interface.keys.sorted() {
            let value = interface[key]!
            lines.append("\(mapping[key] ?? key)=\(["privatekey", "headerprotectionkey"].contains(key) ? hexKey(value) : value)")
        }
        lines += ["replace_peers=true", "public_key=\(hexKey(peer["publickey"]!))"]
        if let key = peer["presharedkey"] { lines.append("preshared_key=\(hexKey(key))") }
        lines += ["endpoint=\(ip.contains(":") ? "[\(ip)]" : ip):\(endpointPort)", "replace_allowed_ips=true", "allowed_ip=0.0.0.0/0", "allowed_ip=::/0"]
        lines.append("persistent_keepalive_interval=\(peer["persistentkeepalive"] ?? "25")")
        return lines.joined(separator: "\n") + "\n\n"
    }
    private func hexKey(_ value: String) -> String { Data(base64Encoded: value)!.map { String(format:"%02x", $0) }.joined() }
    static func list(_ text: String) -> [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    static func isIP(_ text: String) -> Bool { var a = in_addr(), b = in6_addr(); return text.withCString { inet_pton(AF_INET, $0, &a) == 1 || inet_pton(AF_INET6, $0, &b) == 1 } }
    static func validCIDR(_ text: String) -> Bool { let p = text.split(separator: "/"); guard p.count == 2, isIP(String(p[0])), let n = Int(p[1]) else { return false }; return (0...(p[0].contains(":") ? 128 : 32)).contains(n) }
}

struct Settings: Codable {
    var mode: Mode = .auto
    var homeSSIDs: [String] = []
    var profiles: [Profile] = []
    var selectedID: String?
    var launchAtLogin: Bool = false
}
struct NetworkObservation: Codable { var available: Bool; var interface: String?; var ssid: String?; var gateway: String? }
struct ServiceStatus: Codable {
    var phase: Phase = .setup
    var mode: Mode = .auto
    var profileID: String?
    var profileName: String?
    var network: String = "Сеть не определена"
    var message: String = "Импортируй профиль и установи службу"
    var guardActive: Bool = false
    var verifiedAt: Date?
    var events: [String] = []
    var tunnel: String?
}
struct RPCRequest: Codable { var command: String; var settings: Settings?; var network: NetworkObservation? }
struct RPCResponse: Codable { var ok: Bool; var status: ServiceStatus; var error: String? }

// Pure decisions are tested independently from root networking code.
struct Policy {
    static func wantsVPN(mode: Mode, network: NetworkObservation, homes: [String]) -> Bool {
        if mode == .off { return false }
        if mode == .on { return true }
        return !(network.available && network.ssid.map { homes.contains($0) } == true)
    }
    static func next(index: Int, count: Int) -> Int { count > 0 ? (index + 1) % count : 0 }
    static func retryDelay(round: Int) -> TimeInterval { min(120, 30 * pow(2, Double(min(round, 2)))) }
}
