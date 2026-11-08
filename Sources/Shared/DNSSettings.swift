import Foundation

enum DNSProvider: String, Codable, CaseIterable {
    case cloudflare, quad9, google, profile, custom
    var title: String {
        switch self {
        case .cloudflare: return "Cloudflare"
        case .quad9: return "Quad9"
        case .google: return "Google"
        case .profile: return "DNS из VPN-профиля"
        case .custom: return "Свой DoH-сервер"
        }
    }
    var endpoint: (url: String, ip: String)? {
        switch self {
        case .cloudflare: return ("https://cloudflare-dns.com/dns-query", "1.1.1.1")
        case .quad9: return ("https://dns.quad9.net/dns-query", "9.9.9.9")
        case .google: return ("https://dns.google/dns-query", "8.8.8.8")
        default: return nil
        }
    }
}

struct DNSSettings: Codable, Equatable {
    var providers: [DNSProvider] = [.cloudflare, .quad9]
    var customURL = ""
    var customIP = ""
    func validated() throws -> DNSSettings {
        guard !providers.isEmpty, providers.count <= 3,
              customURL.utf8.count <= 1024, customIP.utf8.count <= 64, Set(providers).count == providers.count,
              providers.contains(where: { $0 != .profile }) else {
            throw AppError.message("Выбери основной DNS и хотя бы один DoH-сервер для резерва и подключения VPN")
        }
        if providers.contains(.custom) {
            guard let u = URLComponents(string: customURL), u.scheme == "https", let host = u.host,
                  Profile.validEndpointHost(host), u.user == nil, u.password == nil, u.fragment == nil,
                  u.query == nil, u.port == nil || u.port == 443,
                  customURL.utf8.count <= 1024, !customURL.contains(where: { $0.isWhitespace || $0.isNewline }),
                  Profile.isIP(customIP), !customIP.contains(":"), !Profile.isRoutingFakeIP(customIP),
                  !RoutingPolicy.contains(customIP,cidr:"127.0.0.0/8"), customIP != "0.0.0.0" else {
                throw AppError.message("Для своего DNS нужны HTTPS-адрес без параметров и настоящий IPv4 сервера. Порт — 443.")
            }
        }
        return self
    }
    var endpoints: [(url: String, ip: String)] {
        providers.compactMap { $0 == .custom ? (customURL,customIP) : $0.endpoint }
    }
}
