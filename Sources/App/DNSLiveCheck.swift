import Foundation
import Darwin
import AppKit
import SystemConfiguration

// Explicit, bounded live diagnostic. Profiles remain inside this process and
// the authenticated helper; no Keychain, home-network or route settings are saved.
enum DNSLiveCheck {
    static func restoreStored() -> Int32 {
        do {
            let saved = try Storage.load()
            let response = try IPC.request(RPCRequest(command:"configure",settings:saved,network:nil))
            return response.ok ? 0 : 1
        } catch { return 1 }
    }
    static func run() -> Int32 {
        func report(_ text: String) { print("\(ISO8601DateFormatter().string(from:Date())) \(text)"); fflush(stdout) }
        func require(_ value: Bool, _ text: String) throws { if !value { throw AppError.message(text) } }
        func request(_ command: String, _ settings: Settings? = nil) throws -> ServiceStatus {
            let response = try IPC.request(RPCRequest(command:command,settings:settings,network:nil))
            guard response.ok else { throw AppError.message(response.error ?? response.status.message) }
            return response.status
        }
        func waitConnected(_ timeout: TimeInterval = 75) throws -> ServiceStatus {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                let status = try request("status")
                if status.phase == .connected { return status }
                if status.phase == .error { throw AppError.message(status.message) }
                Thread.sleep(forTimeInterval:0.5)
            } while Date() < deadline
            throw AppError.message("Истекло время ожидания VPN")
        }
        func dns(_ domain: String, tcp: Bool = false) throws -> (code: Int, addresses: [String]) {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/dig")
            process.arguments = ["@127.0.0.1",domain,"A","+time=4","+tries=1"] + (tcp ? ["+tcp"] : [])
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            let text = String(data:data,encoding:.utf8) ?? ""
            let code = text.contains("status: NOERROR") ? 0 : text.contains("status: NXDOMAIN") ? 3 : text.contains("status: SERVFAIL") ? 2 : -1
            let addresses = text.components(separatedBy:.newlines).compactMap { line -> String? in
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 5, parts[3] == "A", let last = parts.last, Profile.isIP(String(last)) else { return nil }
                return String(last)
            }
            return (code,addresses)
        }
        func https(_ url: String, expected: Bool = true) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/curl")
            process.arguments = ["-q","--silent","--fail","--noproxy","*","--connect-timeout","8","--max-time","15",url]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            try require((process.terminationStatus == 0) == expected,"HTTPS не соответствует ожидаемому маршруту: \(url), код \(process.terminationStatus)")
        }
        var saved: Settings?
        var paused: [pid_t] = []
        var watchdog: Process?
        defer {
            if let original = saved {
                do { _ = try request("configure",original); _ = try waitConnected(); report("RESTORED original settings and working VPN") }
                catch { report("RESTORE ERROR: \(error.localizedDescription)") }
            }
            for pid in paused { kill(pid,SIGCONT) }
            watchdog?.terminate()
        }
        do {
            let original = try Storage.load(); saved = original
            try require(!original.profiles.isEmpty,"Нет сохранённого профиля")
            let initial = try request("status")
            try require(initial.dnsProtocol == 1,"Требуется новая VPN-служба")
            // Pause only the ordinary UI so its background catalog/configure
            // cannot race the temporary matrix. The watchdog resumes it on crash.
            paused = NSRunningApplication.runningApplications(withBundleIdentifier:"ru.hl100.autoturn").map { $0.processIdentifier }.filter { $0 != getpid() }
            for pid in paused { kill(pid,SIGSTOP) }
            let watchdogProcess = Process(); watchdogProcess.executableURL = URL(fileURLWithPath:"/bin/sh")
            let resume = paused.map { "kill -CONT \($0) 2>/dev/null || true" }.joined(separator:"; ")
            watchdogProcess.arguments = ["-c","sleep 600; \(resume.isEmpty ? ":" : resume); exec \"$1\" --restore-stored-settings","autoturn-watchdog",Bundle.main.executablePath!]
            watchdogProcess.standardInput = FileHandle.nullDevice; watchdogProcess.standardOutput = FileHandle.nullDevice; watchdogProcess.standardError = FileHandle.nullDevice
            try watchdogProcess.run(); watchdog = watchdogProcess
            var settings = original; settings.mode = .on; settings.routing.mode = .rules
            let primary = original.profiles.first(where: { $0.id == initial.profileID }) ?? original.connectionOrder[0]
            settings.profiles = [primary]; settings.primaryID = primary.id; settings.selectedID = primary.id
            settings.routing.rules += [RoutingRule(name:"DNS audit direct",domains:["example.com","www.apple.com"],destination:.direct),RoutingRule(name:"DNS audit VPN",domains:["www.cloudflare.com","private.autoturn.invalid"],destination:.vpn)]
            report("BEGIN rules / protected DNS / direct HTTPS")
            _ = try request("configure",settings); _ = try waitConnected()
            try require(try dns("example.com").code == 0,"Не работает DNS по UDP")
            try require(try dns("example.com",tcp:true).code == 0,"Не работает DNS по TCP")
            try https("https://example.com/"); try https("https://www.cloudflare.com/cdn-cgi/trace")
            report("PASS rules: DNS UDP/TCP, direct and VPN HTTPS")

            var second = primary; second.id = UUID().uuidString; second.name = "Ephemeral DNS audit reserve"
            settings.profiles = [primary,second]
            _ = try request("configure",settings); _ = try waitConnected()
            _ = try request("next")
            let switchingDNS = try dns("private.autoturn.invalid")
            try require(switchingDNS.code == 2 || switchingDNS.code == 3,"Неожиданный DNS при смене профиля")
            let next = try waitConnected()
            try require(next.profileID == second.id,"Резервный профиль не выбран")
            try https("https://example.com/"); report("PASS two-profile switch and DNS recovery")

            var unavailable = primary; unavailable.id = UUID().uuidString; unavailable.name = "Ephemeral unreachable audit profile"; unavailable.endpointPort = 9
            settings.profiles = [unavailable]; settings.primaryID = unavailable.id; settings.selectedID = unavailable.id
            _ = try request("configure",settings)
            try require(try dns("private.autoturn.invalid").code == 2,"VPN-домен вышел в прямой DNS при отказе VPN")
            try require(try dns("example.com").code == 0,"Прямой резервный DNS не работает")
            try https("https://example.com/")
            report("PASS rules outage: protected DNS blocked; ordinary DNS and HTTPS work")

            settings.profiles = [primary]; settings.primaryID = primary.id; settings.selectedID = primary.id
            settings.dns.providers = [.custom,.quad9]
            settings.dns.customURL = "https://dns.autoturn.invalid/dns-query"; settings.dns.customIP = "192.0.2.1"
            _ = try request("configure",settings); _ = try waitConnected()
            try require(try dns("example.com").code == 0,"Резервный DNS не заменил недоступный основной")
            report("PASS DNS-provider failover through VPN")

            settings.dns = original.dns; settings.routing.mode = .all
            _ = try request("configure",settings); _ = try waitConnected()
            try require(try dns("example.com").code == 0,"DNS полного туннеля не работает")
            try https("https://example.com/"); try https("https://www.cloudflare.com/cdn-cgi/trace")
            report("PASS full tunnel: DNS and HTTPS")
            settings.profiles = [unavailable]; settings.primaryID = unavailable.id; settings.selectedID = unavailable.id
            _ = try request("configure",settings)
            try require(try dns("example.com").code == 2,"Полный туннель использовал прямой DNS-резерв")
            try https("https://example.com/",expected:false)
            report("PASS full-tunnel outage: direct DNS and HTTPS blocked")
            report("LIVE DNS MATRIX PASSED; restoring original configuration")
            return 0
        } catch { report("LIVE DNS MATRIX FAILED: \(error.localizedDescription)"); return 1 }
    }
}
