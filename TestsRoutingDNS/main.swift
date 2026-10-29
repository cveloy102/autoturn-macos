import Foundation

// Export the production policy for a loopback integration fixture. The harness
// substitutes only the TUN/socket bindings and ports, leaving DNS/routing intact.
var settings = RoutingSettings(); settings.mode = .rules
settings.rules = [RoutingRule(name:"VPN fixture",domains:["vpn.autoturn.test"],destination:.vpn)]
let data = try RoutingCoreConfiguration.make(settings,physicalInterface:"en0",physicalDNS:"127.0.0.1",tunnel:"utun3",dns:"127.0.0.1")
FileHandle.standardOutput.write(data)
