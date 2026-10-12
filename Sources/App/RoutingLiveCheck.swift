import Foundation
import SystemConfiguration
import Darwin

// Explicit developer diagnostic. It never writes Keychain, login settings or
// database files. The caller supplies a parsed profile, from a file or Keychain.
enum RoutingLiveCheck {
    static func run(profilePath: String) -> Int32 {
        do { return run(profile: try Profile.parse(String(contentsOfFile:profilePath,encoding:.utf8),name:"Routing diagnostic")) }
        catch { fputs("LIVE ROUTING CHECK FAILED: \(error.localizedDescription)\n",stderr); return 1 }
    }
    static func run(profile suppliedProfile: Profile) -> Int32 {
        func report(_ message: String) { print(message); fflush(stdout) }
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw AppError.message(message) } }
        func request(_ command: String, settings: Settings? = nil, network: NetworkObservation? = nil) throws -> ServiceStatus {
            let reply = try IPC.request(RPCRequest(command:command,settings:settings,network:network))
            guard reply.ok else { throw AppError.message(reply.error ?? "Service rejected diagnostic") }
            return reply.status
        }
        func https(_ url: String) -> Bool {
            let p = Process(); p.executableURL = URL(fileURLWithPath:"/usr/bin/curl")
            p.arguments = ["--silent","--fail","--noproxy","*","--max-time","12",url]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
        }
        func wait(_ phase: Phase) throws -> ServiceStatus {
            for _ in 0..<20 {
                let status = try request("status")
                if status.phase == phase { return status }
                if status.phase == .error { throw AppError.message(status.message) }
                Thread.sleep(forTimeInterval:1)
            }
            throw AppError.message("Diagnostic timed out waiting for \(phase.rawValue)")
        }
        var touchedService = false
        defer {
            if touchedService {
                do { _ = try request("stop"); report("CLEANUP: test VPN stopped; saved application settings untouched") }
                catch { fputs("CLEANUP FAILED: open AutoTurn and choose Off immediately\n",stderr) }
            }
        }
        do {
            let initial = try request("status")
            try require(initial.routingProtocol == 2,"Install the new helper before this diagnostic")
            try require(!initial.guardActive && [.home,.off,.setup].contains(initial.phase),"Diagnostic requires an idle VPN at home or Off")
            guard let store = SCDynamicStoreCreate(nil,"AutoTurnRoutingCheck" as CFString,nil,nil), let global = SCDynamicStoreCopyValue(store,"State:/Network/Global/IPv4" as CFString) as? [String:Any], let iface = global["PrimaryInterface"] as? String, let gateway = global["Router"] as? String, !iface.hasPrefix("utun") else { throw AppError.message("No physical network") }
            let network = NetworkObservation(available:true,interface:iface,ssid:"AUTOTURN_SELF_CHECK_HOME",gateway:gateway)
            var profile = try suppliedProfile.validated()
            profile.resolvedIP = try Storage.resolve(profile.endpointHost)
            var settings = Settings(); settings.profiles = [profile]; settings.selectedID = profile.id; settings.mode = .on
            settings.homeSSIDs = ["AUTOTURN_SELF_CHECK_HOME"]
            settings.routing.mode = .rules
            settings.routing.rules = [RoutingRule(name:"Diagnostic VPN",domains:["cloudflare.com"],destination:.vpn),RoutingRule(name:"Diagnostic direct",domains:["apple.com","example.com"],destination:.direct)]
            report("BEGIN live TUN test: real profile, direct HTTPS, selected VPN HTTPS, cleanup and simulated home policy; no secrets printed")
            touchedService = true
            _ = try request("configure",settings:settings,network:network)
            let connected = try wait(.connected)
            try require(connected.guardActive && if_nametoindex("utun99") != 0,"Routing TUN/PF not active")
            try require(https("https://www.apple.com/library/test/success.html"),"Direct HTTPS failed through routing TUN")
            try require(https("https://www.cloudflare.com/cdn-cgi/trace"),"Selected VPN HTTPS failed through routing TUN")
            report("PASS rules: TUN active, direct HTTPS and selected VPN HTTPS both work")
            settings.mode = .auto
            _ = try request("configure",settings:settings,network:network)
            let home = try wait(.home)
            try require(!home.guardActive && if_nametoindex("utun99") == 0,"Home transition did not clean TUN/PF")
            try require(https("https://www.apple.com/library/test/success.html"),"Direct HTTPS failed after home transition")
            report("PASS home policy: physical interface unchanged, simulated trusted home SSID; TUN removed and HTTPS works")
            settings.mode = .on; settings.routing.mode = .all
            _ = try request("configure",settings:settings,network:network)
            _ = try wait(.connected)
            try require(if_nametoindex("utun99") == 0 && https("https://www.cloudflare.com/cdn-cgi/trace"),"Full VPN mode regression")
            report("PASS full VPN compatibility")
            _ = try request("stop")
            let off = try wait(.off)
            try require(!off.guardActive && if_nametoindex("utun99") == 0 && https("https://www.apple.com/library/test/success.html"),"Off cleanup failed")
            report("LIVE ROUTING CHECK PASSED; final mode Off. Real Wi-Fi switching and browser DoH require additional live checks.")
            return 0
        } catch { fputs("LIVE ROUTING CHECK FAILED: \(error.localizedDescription)\n",stderr); return 1 }
    }
}
