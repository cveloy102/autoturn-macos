import Foundation
import Darwin
import SystemConfiguration

final class RoutingCoreManager: DomainRouting {
    let protection: TrafficProtection, directory: String, executable: String
    var settings = RoutingSettings(), physical = PhysicalNetwork()
    var process: Process?, tunnelName: String?, dnsServers: [String] = []
    var coreInterface: String?, fingerprint = ""
    init(protection: TrafficProtection, directory: String = support) { self.protection = protection; self.directory = directory; executable = directory + "/routing-core" }
    private let dnsKey = "State:/Network/Service/AutoTurn-Routing/DNS"
    func recoverJournal() throws { try Tunnel.removeDNSKey(dnsKey) }
    private func installDNS() throws {
        guard let store = SCDynamicStoreCreate(nil,"AutoTurnRoutingDNS" as CFString,nil,nil) else { throw AppError.message("DNS маршрутов недоступен") }
        let value: [String:Any] = ["ServerAddresses":["172.29.255.2"],"SupplementalMatchDomains":[""],"SupplementalMatchOrders":[0],"InterfaceName":"utun99"]
        guard SCDynamicStoreSetValue(store,dnsKey as CFString,value as CFDictionary) else { throw AppError.message("Не удалось включить DNS маршрутов") }
    }
    func configure(_ settings: RoutingSettings, physical: PhysicalNetwork) throws {
        if self.settings.mode != settings.mode || (settings.mode == .rules && self.settings.rules != settings.rules) || self.physical.interface != physical.interface || self.physical.gateway != physical.gateway { try stop() }
        self.settings = settings; self.physical = physical
    }
    func setTunnel(_ interface: String?, dns: [String], supportsIPv6: Bool) throws {
        guard settings.mode == .rules else { return }
        guard let tunnel = interface, let physical = physical.interface, let gateway = self.physical.gateway, let server = dns.first else { throw AppError.message("Туннель ещё не готов для маршрутов") }
        let data = try RoutingCoreConfiguration.make(settings,physicalInterface:physical,gateway:gateway,tunnel:tunnel,dns:server,supportsIPv6:supportsIPv6)
        let fingerprint = String(data:data,encoding:.utf8)!
        if self.fingerprint == fingerprint && process?.isRunning == true { return }
        try stopProcess()
        guard if_nametoindex("utun99") == 0 else { throw AppError.message("Интерфейс маршрутов utun99 уже занят") }
        let config = directory + "/routing-core.json"
        try data.write(to:URL(fileURLWithPath:config),options:.atomic); chmod(config,0o600)
        _ = try SystemCommand.checked(executable,["check","-c",config])
        let p = Process(); p.executableURL = URL(fileURLWithPath:executable); p.arguments = ["run","-c",config]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); process = p
        for _ in 0..<50 {
            if !p.isRunning { break }
            if if_nametoindex("utun99") != 0, let route = try? SystemCommand.run("/sbin/route",["-n","get","1.1.1.1"]), route.output.contains("interface: utun99") {
                coreInterface = "utun99"; self.fingerprint = fingerprint
                try protection.setRoutingInterface(coreInterface)
                try installDNS()
                return
            }
            Thread.sleep(forTimeInterval:0.1)
        }
        try stopProcess(); throw AppError.message("Не удалось запустить ядро маршрутизации")
    }
    func stop() throws { try stopProcess(); settings = RoutingSettings() }
    private func stopProcess() throws {
        var dnsError: Error?
        do { try Tunnel.removeDNSKey(dnsKey) } catch { dnsError = error }

        try protection.setRoutingInterface(nil)
        if let p = process, p.isRunning {
            p.terminate(); let deadline = ContinuousTime.now() + 2
            while p.isRunning && ContinuousTime.now() < deadline { Thread.sleep(forTimeInterval:0.025) }
            if p.isRunning { kill(p.processIdentifier,SIGKILL) }
            let end = ContinuousTime.now() + 1; while p.isRunning && ContinuousTime.now() < end { Thread.sleep(forTimeInterval:0.025) }
            guard !p.isRunning else { throw AppError.message("Ядро маршрутов не остановилось") }
        }
        process = nil; coreInterface = nil; fingerprint = ""
        if let error = dnsError { throw error }
    }
}
