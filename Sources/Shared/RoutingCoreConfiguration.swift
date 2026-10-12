import Foundation

enum RoutingCoreConfiguration {
    static func make(_ settings: RoutingSettings, physicalInterface: String, gateway: String, tunnel: String, dns: String, routingInterface: String = "utun99", supportsIPv6: Bool = false) throws -> Data {
        let value = try settings.validated()
        guard physicalInterface.range(of:"^(en|bridge|eth)[0-9]+$",options:.regularExpression) != nil, [tunnel,routingInterface].allSatisfy({ $0.range(of:"^utun[0-9]+$",options:.regularExpression) != nil }), Profile.isIP(gateway), Profile.isIP(dns) else { throw AppError.message("Некорректные интерфейсы маршрутизации") }
        var rules: [[String:Any]] = [["inbound":["routing-in"],"action":"sniff","timeout":"300ms"],["protocol":"dns","action":"hijack-dns"]]
        let enabled = value.rules.filter { $0.enabled }
        // Domain rules precede IP fallback: sharing a CDN IP does not merge flows.
        let lengths = Set(enabled.flatMap { $0.allDomains.map { $0.count } }).sorted(by:>)
        for length in lengths { for destination in [RouteDestination.vpn,.direct] {
            let domains = Array(Set(enabled.filter { $0.destination == destination }.flatMap { $0.allDomains }.filter { $0.count == length })).sorted()
            if !domains.isEmpty { rules.append(["domain_suffix":domains,"action":"route","outbound":destination.rawValue]) }
        } }
        rules.append(["action":"resolve","server":"physical-dns","strategy":"ipv4_only"])
        for destination in [RouteDestination.vpn,.direct] {
            let ranges = Array(Set(enabled.filter { $0.destination == destination }.flatMap { $0.allIPRanges })).sorted()
            if !ranges.isEmpty { rules.append(["ip_cidr":ranges,"action":"route","outbound":destination.rawValue]) }
        }
        rules.append(["inbound":["autoturn-domain"],"action":"route","outbound":"direct"])
        let config: [String:Any] = [
            "log":["disabled":true],
            "experimental":["cache_file":["enabled":true,"path":"/Library/Application Support/AutoTurn/routing-cache.db","store_fakeip":true]],
            // Advertising synthetic IPv6 for an IPv4-only VPN makes Chrome/DoH
            // prefer unreachable IPv6 endpoints instead of using IPv4.
            "inbounds":[["type":"tun","tag":"routing-in","interface_name":routingInterface,"address":supportsIPv6 ? ["172.29.255.1/30","fd99:6175:746f::1/126"] : ["172.29.255.1/30"],"mtu":1280,"auto_route":true,"strict_route":true,"dns_mode":"hijack","stack":"gvisor"]],
            "outbounds":[["type":"direct","tag":"direct","bind_interface":physicalInterface,"domain_resolver":["server":"physical-dns","strategy":"ipv4_only"]],["type":"direct","tag":"vpn","bind_interface":tunnel,"domain_resolver":["server":"vpn-dns","strategy":"ipv4_only"]]],
            "dns":["servers":[["type":"udp","tag":"physical-dns","server":gateway,"detour":"direct"],["type":"udp","tag":"vpn-dns","server":dns,"detour":"vpn"],["type":"fakeip","tag":"domain-map","inet4_range":"198.18.0.0/15","inet6_range":"fc00::/18"]],"rules":[["query_type":["A","AAAA"],"action":"route","server":"domain-map"]],"final":"physical-dns","strategy":"ipv4_only"],
            "route":["default_interface":physicalInterface,"default_domain_resolver":"physical-dns","rules":rules,"final":"direct"]
        ]
        return try JSONSerialization.data(withJSONObject:config,options:[.sortedKeys])
    }
}
