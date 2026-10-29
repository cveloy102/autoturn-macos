import Foundation
import Darwin
import Network

let support = "/Library/Application Support/AutoTurn"
struct Installation: Codable { var uid: UInt32; var cdhashes: [String]; var engine: String }
struct SavedGuard: Codable { var required: Bool; var token: String? }

final class Service {
    let queue = DispatchQueue(label: "ru.hl100.autoturn.service")
    let guardManager: TrafficProtection
    let tunnel: ManagedTunnel
    let domainRoutes: DomainRouting
    let physicalRead: () -> PhysicalNetwork
    let resolveEndpoint: (String, PhysicalNetwork) throws -> String
    private var tunnelEndpoint: (id:String, host:String, ip:String)?
    private var endpointCache: [String:(ip:String,expires:TimeInterval)] = [:]
    let healthCheck: ((String) -> Bool)?
    let asyncHealth: ((String, [String]?, @escaping (Bool) -> Void) -> Void)?
    private var healthProbeToken: UUID?
    private var healthProbeStarted: TimeInterval = 0
    let recoverProcesses: () throws -> Void
    let stateDirectory: String
    var settings = Settings(), status = ServiceStatus()
    var observation = NetworkObservation(available: false, interface: nil, ssid: nil, gateway: nil)
    var observedAt = Date.distantPast, observedPhysical = PhysicalNetwork()
    var confirmedNetwork: NetworkObservation?
    var confirmedAt = Date.distantPast
    var observedContinuousAt = -Double.infinity, confirmedContinuousAt = -Double.infinity
    private var previousWallTime: Date?
    private var previousTickContinuous: TimeInterval?
    private var wakeGraceUntil: TimeInterval = -Double.infinity
    let continuousNow: () -> TimeInterval
    let now: () -> Date
    var cleanupPending = false
    var retryTunnelAfterBackoff = false
    private var lastDecision = "", lastEventText = ""
    var index = 0, failures = 0, attempted = 0, round = 0
    var nextCheck = Date.distantPast
    var guardRequired = false
    var pendingTunnelReset = false
    var startupRecoveryError: Error?
    let installation: Installation
    let timer: DispatchSourceTimer
    let monitor = NWPathMonitor()
    init(_ installation: Installation, protection: TrafficProtection = TrafficGuard(), managedTunnel: ManagedTunnel = Tunnel(), routing: DomainRouting? = nil, physical: @escaping () -> PhysicalNetwork = PhysicalNetwork.read, health: ((String) -> Bool)? = nil, asyncHealth: ((String, [String]?, @escaping (Bool) -> Void) -> Void)? = nil, stateDirectory: String = support, monitoring: Bool = true, now: @escaping () -> Date = Date.init, continuousNow: @escaping () -> TimeInterval = ContinuousTime.now, recoverProcesses: @escaping () throws -> Void = OwnedProcessRecovery.stop, resolveEndpoint: @escaping (String, PhysicalNetwork) throws -> String = { try EndpointResolver.resolve($0,physical:$1) }) {
        self.resolveEndpoint = resolveEndpoint
        self.now = now; self.continuousNow = continuousNow; self.asyncHealth = asyncHealth
        self.recoverProcesses = recoverProcesses
        self.installation = installation; domainRoutes = routing ?? RoutingCoreManager(protection:protection,directory:stateDirectory); guardManager = protection; tunnel = managedTunnel; physicalRead = physical; healthCheck = health; self.stateDirectory = stateDirectory
        let historyURL = URL(fileURLWithPath:stateDirectory + "/events.json")
        if let size = try? historyURL.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 128 * 1024,
           let data = try? Data(contentsOf:historyURL), let history = try? JSONDecoder().decode([String].self,from:data) {
            status.events = Array(history.suffix(100))
        }
        status.serviceInstance = UUID().uuidString
        observedPhysical = physical()
        timer = DispatchSource.makeTimerSource(queue: queue)
        if let saved = try? JSONDecoder().decode(SavedGuard.self, from: Data(contentsOf: URL(fileURLWithPath: stateDirectory + "/guard.json"))) {
            guardRequired = saved.required; guardManager.restoreToken(saved.token)
        }
        if guardRequired { do { try guardManager.apply(tunnel:nil,profile:nil); saveGuard() } catch { status.phase = .error; status.message = "Не удалось восстановить блокировку после перезапуска" } }
        if monitoring && stateDirectory == support {
            do { try recoverProcesses() } catch { startupRecoveryError = error; status.phase = .error; status.message = error.localizedDescription }
        }
        do { try domainRoutes.recoverJournal() } catch { startupRecoveryError = error }
        do { try tunnel.recoverJournal() } catch { startupRecoveryError = error }
        if let error = startupRecoveryError { status.phase = .error; status.message = error.localizedDescription; cleanupPending = true }
        timer.schedule(deadline: monitoring ? .now() : .now() + 3600, repeating: monitoring ? 5 : 3600)
        timer.setEventHandler { [weak self] in self?.tick() }; timer.resume()
        monitor.pathUpdateHandler = { [weak self] _ in guard let self = self else { return }; self.queue.async { self.physicalNetworkChanged() } }
        if monitoring { monitor.start(queue: DispatchQueue(label: "ru.hl100.autoturn.path")) }
        event("Служба запущена; сохранённая блокировка=\(guardRequired)")
    }
    func physicalNetworkChanged() {
        // VPN route/DNS changes also trigger NWPathMonitor. Only an actual physical
        // interface or gateway change may invalidate the app's SSID observation.
        // tick() compares the physical interface/gateway itself. VPN-generated
        // path changes must not defeat health-check backoff or force rebuilds.
        tick()
    }
    @discardableResult func recordNetwork(_ value: NetworkObservation) -> Bool {
        let receivedAt = now(), sampledAt = value.sampledAt ?? receivedAt
        let receivedContinuous = continuousNow()
        let wallAge = receivedAt.timeIntervalSince(sampledAt)
        let sampleContinuous = value.sampledContinuouslyAt ?? (receivedContinuous - max(0,wallAge))
        // Ignore queued/out-of-order observations, including samples from before
        // sleep. A future timestamp must not extend the trust window.
        guard sampledAt <= receivedAt.addingTimeInterval(2), receivedAt.timeIntervalSince(sampledAt) < 20,
              wallAge >= -2, sampleContinuous.isFinite,
              sampleContinuous <= receivedContinuous + 2, receivedContinuous - sampleContinuous < 20,
              sampleContinuous >= observedContinuousAt else { return false }
        if !value.available || value.interface != observation.interface || value.gateway != observation.gateway ||
            (value.ssid != nil && value.ssid != confirmedNetwork?.ssid) {
            confirmedNetwork = nil; confirmedAt = .distantPast; confirmedContinuousAt = -Double.infinity
        }
        observation = value; observedAt = min(sampledAt,receivedAt)
        observedContinuousAt = min(sampleContinuous,receivedContinuous)
        if value.available, value.ssid != nil {
            confirmedNetwork = value; confirmedAt = observedAt; confirmedContinuousAt = observedContinuousAt
        }
        return true
    }
    func event(_ text: String) {
        guard text != lastEventText else { return }; lastEventText = text
        let timestamp = ISO8601DateFormatter().string(from:now())
        status.events.append("\(timestamp)  \(text)"); status.events = Array(status.events.suffix(100))
        let path = stateDirectory + "/events.json"
        if let data = try? JSONEncoder().encode(status.events) {
            do { try data.write(to:URL(fileURLWithPath:path),options:.atomic); chmod(path,0o600); status.eventLogError = nil }
            catch { status.eventLogError = "Не удалось сохранить журнал событий" }
        }
    }
    func saveGuard() { if let data = try? JSONEncoder().encode(SavedGuard(required: guardRequired, token: guardManager.token)) { try? data.write(to: URL(fileURLWithPath: stateDirectory + "/guard.json"), options: .atomic); chmod(stateDirectory + "/guard.json", 0o600) } }
    func handle(_ request: RPCRequest) -> RPCResponse {
        do {
            switch request.command {
            case "status": break
            case "configure":
                guard var value = request.settings, value.profiles.count <= 32, value.homeSSIDs.count <= 32, value.homeSSIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32 }) else { throw AppError.message("Некорректные настройки") }
                value.routing = try value.routing.validated()
                guard (try JSONEncoder().encode(value)).count < 900000 else { throw AppError.message("Настройки слишком большие") }
                value.profiles = try value.profiles.map { try $0.validated() }
                value.primaryID = value.primaryProfileID
                value.profiles = value.connectionOrder
                guard Set(value.profiles.map { $0.id }).count == value.profiles.count else { throw AppError.message("Повторные профили") }
                if value.mode != .off && value.profiles.isEmpty { throw AppError.message("Сначала импортируй профиль") }
                let changed = value.profiles != settings.profiles || value.selectedID != settings.selectedID || value.routing.mode != settings.routing.mode || (value.routing.mode == .rules && value.routing.rules != settings.routing.rules)
                let modeChanged = value.mode != settings.mode
                let freshCycle = settings.mode == .off || [.home,.off,.setup].contains(status.phase)
                let manualSelection = value.selectedID != settings.selectedID && !freshCycle
                if changed || modeChanged || freshCycle { cancelHealthProbe() }
                settings = value
                if let network = request.network { recordNetwork(network) }
                if changed || freshCycle { index = manualSelection ? (value.profiles.firstIndex { $0.id == value.selectedID } ?? 0) : 0 }
                if changed { pendingTunnelReset = true }
                if changed || modeChanged || freshCycle {
                    failures = 0; attempted = 0; round = 0; nextCheck = .distantPast
                }
                event("Настройки применены"); tick()
            case "network":
                guard let value = request.network else { throw AppError.message("Нет состояния сети") }
                let changed = (value.ssid != nil && value.ssid != confirmedNetwork?.ssid) || value.interface != observation.interface || value.gateway != observation.gateway || value.available != observation.available
                if recordNetwork(value) && changed { nextCheck = .distantPast }; tick()
            case "check":
                // A manual check starts/joins a probe. Its immediate RPC reply
                // must not reuse a success from an already completed probe.
                status.verifiedAt = nil
                if status.phase == .connected {
                    status.phase = .connecting; status.message = "Проверяем доступ через VPN"
                }
                nextCheck = .distantPast; tick()
            case "next":
                guard settings.profiles.count > 1 else { throw AppError.message("Нет резервного профиля") }
                if settings.mode != .off { try stopProtectedTunnel(physical: physicalRead()) }
                index = Policy.next(index: index, count: settings.profiles.count); attempted = 0; failures = 0; nextCheck = .distantPast; tick()
            case "recover":
                cancelHealthProbe()
                settings.mode = .off; pendingTunnelReset = false
                var errors: [String] = []
                do { try guardManager.remove() } catch { errors.append(error.localizedDescription) }
                do { try domainRoutes.stop() } catch { errors.append(error.localizedDescription) }
                do { try tunnel.stop() } catch { errors.append(error.localizedDescription) }
                if stateDirectory == support { do { try recoverProcesses() } catch { errors.append(error.localizedDescription) } }
                do { try domainRoutes.recoverJournal() } catch { errors.append(error.localizedDescription) }
                do { try tunnel.recoverJournal() } catch { errors.append(error.localizedDescription) }
                guardRequired = guardManager.active; saveGuard()
                cleanupPending = !errors.isEmpty
                guard errors.isEmpty else { throw AppError.message(errors.joined(separator:". ")) }
                startupRecoveryError = nil; tick(); event("Обычный интернет восстановлен. Автоматика выключена.")
            case "stop": settings.mode = .off; tick()
            default: throw AppError.message("Команда не поддерживается")
            }
            let failed = request.command != "status" && status.phase == .error
            return RPCResponse(ok: !failed, status: status, error: failed ? status.message : nil)
        } catch {
            status.phase = .error; status.message = error.localizedDescription; status.guardActive = guardManager.active
            event(status.message); return RPCResponse(ok: false, status: status, error: status.message)
        }
    }
    func tick() {
        let wallTime = now(), continuousTime = continuousNow()
        if let previous = previousTickContinuous, continuousTime - previous > 20 {
            // Protect immediately, but let the app deliver a fresh post-wake SSID
            // before expensive tunnel construction occupies this queue.
            cancelHealthProbe(); wakeGraceUntil = continuousTime + 3; nextCheck = .distantPast
        }
        previousTickContinuous = continuousTime
        // Older clients only stamp wall time. Invalidate their leases on a
        // backwards adjustment; new continuous timestamps remain ordered.
        if let previous = previousWallTime, wallTime < previous {
            observedAt = .distantPast; confirmedAt = .distantPast
            observedContinuousAt = -Double.infinity; confirmedContinuousAt = -Double.infinity
            confirmedNetwork = nil; nextCheck = .distantPast
        }
        previousWallTime = wallTime
        let physical = physicalRead()
        if physical.dnsServers != observedPhysical.dnsServers || physical.service != observedPhysical.service {
            endpointCache.removeAll()
            cancelHealthProbe(); status.verifiedAt = nil; nextCheck = .distantPast
        }
        let changed = physical.interface != observedPhysical.interface || physical.gateway != observedPhysical.gateway
        if changed {
            endpointCache.removeAll()
            cancelHealthProbe()
            index = 0; failures = 0; attempted = 0; round = 0
            if observation.interface != physical.interface || observation.gateway != physical.gateway { observedAt = .distantPast; observedContinuousAt = -Double.infinity }
            if confirmedNetwork?.interface != physical.interface || confirmedNetwork?.gateway != physical.gateway { confirmedNetwork = nil; confirmedAt = .distantPast; confirmedContinuousAt = -Double.infinity }
            nextCheck = .distantPast
        }
        observedPhysical = physical
        var network = NetworkObservation(available: physical.available, interface: physical.interface, ssid: nil, gateway: physical.gateway)
        // SSID lease is only accepted for the current physical interface, never a stale home Wi-Fi.
        if (0..<20).contains(continuousNow() - observedContinuousAt) && observation.interface == physical.interface && observation.gateway == physical.gateway { network.ssid = observation.ssid }
        // A single nil SSID read must not immediately turn a confirmed home into
        // an external network. Do not renew this bounded lease on nil samples.
        if network.ssid == nil, network.available, (0..<20).contains(continuousNow() - confirmedContinuousAt),
           let confirmed = confirmedNetwork, confirmed.interface == physical.interface, confirmed.gateway == physical.gateway {
            network.ssid = confirmed.ssid
        }
        status.network = network.ssid ?? (network.available ? "\(network.interface ?? "") · сеть не подтверждена" : "Нет подключения")
        status.mode = settings.mode
        let wanted = settings.mode == .off ? false : settings.profiles.isEmpty ? guardRequired : Policy.wantsVPN(mode: settings.mode, network: network, homes: settings.homeSSIDs)
        defer {
            let decision = "mode=\(settings.mode.rawValue) phase=\(status.phase.rawValue) guard=\(guardManager.active) available=\(network.available) ssidKnown=\(network.ssid != nil) home=\(network.ssid.map { settings.homeSSIDs.contains($0) } ?? false) interface=\(physical.interface ?? "none") routing=\(settings.routing.mode.rawValue) physicalDNSKnown=\(!physical.dnsServers.isEmpty) dnsMatchesGateway=\(physical.dnsServers.first != nil && physical.dnsServers.first == physical.gateway)"
            if decision != lastDecision {
                lastDecision = decision
                let age = Int(max(0,min(86400,now().timeIntervalSince(observedAt))))
                event(decision + " observationAge=\(age)s")
            }
        }
        var activeProfile: Profile?
        do {
            if !wanted {
                endpointCache.removeAll()
                index = 0
                cancelHealthProbe()
                pendingTunnelReset = false; retryTunnelAfterBackoff = false
                failures = 0; attempted = 0; round = 0; nextCheck = .distantPast
                var cleanupError: Error?
                if cleanupPending || startupRecoveryError != nil || tunnel.running || tunnel.interface != nil || guardManager.active || guardRequired || guardManager.token != nil {
                    // Once direct Internet is requested, release PF before stopping
                    // the engine so a slow process exit cannot leave the user blocked.
                    do { try guardManager.remove() } catch { cleanupError = error }
                    do { try domainRoutes.stop() } catch { if cleanupError == nil { cleanupError = error } }
                    do { try tunnel.stop() } catch { if cleanupError == nil { cleanupError = error } }
                    if startupRecoveryError != nil {
                        do { try recoverProcesses(); try domainRoutes.recoverJournal(); try tunnel.recoverJournal(); startupRecoveryError = nil }
                        catch { if cleanupError == nil { cleanupError = error } }
                    }
                    guardRequired = guardManager.active; saveGuard(); event("Наш VPN отключён")
                }
                cleanupPending = cleanupError != nil
                status.phase = cleanupError == nil ? (settings.mode == .off ? .off : settings.profiles.isEmpty ? .setup : .home) : .error
                status.message = cleanupError?.localizedDescription ?? (settings.mode == .off ? "Выключено вручную · прямое подключение разрешено" : settings.profiles.isEmpty ? "Импортируй профиль AmneziaWG" : "Домашняя сеть · через роутер")
                status.guardActive = guardManager.active; status.verifiedAt = nil; status.tunnel = nil; status.profileID = nil; status.profileName = nil
                if let error = cleanupError { event(error.localizedDescription) }
                return
            }
            if let error = startupRecoveryError { throw error }
            guardRequired = true; saveGuard()
            if settings.mode == .auto && network.ssid == nil && continuousTime < wakeGraceUntil {
                try guardManager.configureRouting(RoutingSettings(),physical:physical)
                try guardManager.apply(tunnel:tunnel.running ? tunnel.interface : nil,profile:nil); saveGuard()
                status.phase = .waiting; status.guardActive = guardManager.active; status.verifiedAt = nil
                status.message = "Проверяем домашнюю сеть после сна. Защита включена."
                return
            }
            if retryTunnelAfterBackoff && now() >= nextCheck { index = 0 }
            if ((changed || pendingTunnelReset || (retryTunnelAfterBackoff && now() >= nextCheck)) && tunnel.running) || (!tunnel.running && tunnel.interface != nil) {
                try stopProtectedTunnel(physical: physical)
                retryTunnelAfterBackoff = false
                nextCheck = .distantPast
                event("Пересоздаём туннель после изменения сети, профиля или остановки движка")
            }
            pendingTunnelReset = false
            if !network.available || settings.profiles.isEmpty {
                cancelHealthProbe()
                try guardManager.apply(tunnel: tunnel.running ? tunnel.interface : nil, profile: nil); saveGuard()
                status.phase = .waiting; status.message = settings.profiles.isEmpty ? "Ожидаем профили от приложения. Прямой доступ закрыт." : "Ждём сеть. Режим VPN сохранён."; status.guardActive = guardManager.active; status.verifiedAt = nil; return
            }
            var profile = settings.profiles[index % settings.profiles.count]
            // A cached UI/system DNS result can be one of our own fake IPs.
            // Resolve hostnames afresh on each connection, outside the fake DNS.
            if Profile.isIP(profile.endpointHost) {
                profile.resolvedIP = try EndpointResolver.resolve(profile.endpointHost,physical:physical)
            } else if tunnel.running, let endpoint = tunnelEndpoint, endpoint.id == profile.id, endpoint.host == profile.endpointHost {
                profile.resolvedIP = endpoint.ip
            } else {
                profile.resolvedIP = nil
                if !tunnel.running && now() >= nextCheck {
                    do { profile = try prepareEndpoint(profile,physical:physical) }
                    catch {
                        status.profileID = profile.id; status.profileName = profile.name
                        event(error.localizedDescription)
                        connectionFailed(immediate:true)
                        return
                    }
                }
            }
            activeProfile = profile
            if !tunnel.running { try guardManager.configureRouting(RoutingSettings(),physical:physical); try guardManager.apply(tunnel:nil,profile:profile); saveGuard() }
            try domainRoutes.configure(settings.routing,physical:physical)
            try guardManager.configureRouting(settings.routing,physical:physical)
            tunnel.setRoutingMode(settings.routing.mode)
            status.profileID = profile.id; status.profileName = profile.name
            if tunnel.running { try guardManager.apply(tunnel: tunnel.interface, profile: profile); saveGuard() }
            if now() < nextCheck {
                // Core liveness must not wait for the VPN health/backoff timer.
                // Keep PF active while a crashed routing process is recreated.
                if tunnel.running {
                    try domainRoutes.setTunnel(tunnel.interface,dns:profile.dns,supportsIPv6:profile.hasIPv6)
                    try guardManager.apply(tunnel:tunnel.interface,profile:profile)
                }
                status.guardActive = guardManager.active; return
            }
            if !tunnel.running {
                status.phase = .connecting; status.message = "Создаём туннель и проверяем трафик"
                try guardManager.apply(tunnel: nil, profile: profile); saveGuard()
                do { try tunnel.start(profile, physical: physical, engine: installation.engine); try guardManager.apply(tunnel: tunnel.interface, profile: profile); saveGuard(); event("Туннель \(profile.name) создан") }
                catch { event(error.localizedDescription); try tunnel.stop(); try guardManager.apply(tunnel: nil, profile: profile); connectionFailed(immediate: true); return }
            }
            try domainRoutes.setTunnel(tunnel.interface,dns:profile.dns,supportsIPv6:profile.hasIPv6)
            try guardManager.apply(tunnel:tunnel.interface,profile:profile)
            status.tunnel = tunnel.interface; status.guardActive = guardManager.active
            if let iface = tunnel.interface {
                probeHealth(interface:iface,dns:settings.routing.mode == .rules ? profile.dns : nil)
            } else { connectionFailed(immediate:false) }
        } catch {
            cancelHealthProbe()
            if settings.routing.mode == .rules { try? guardManager.configureRouting(RoutingSettings(),physical:physical); try? guardManager.apply(tunnel:tunnel.interface,profile:activeProfile); saveGuard() }
            status.phase = .error; status.message = error.localizedDescription; status.guardActive = guardManager.active; status.verifiedAt = nil
            nextCheck = now().addingTimeInterval(30); event(status.message)
        }
    }
    private func cancelHealthProbe() { healthProbeToken = nil }
    private func prepareEndpoint(_ original: Profile, physical: PhysicalNetwork) throws -> Profile {
        // Repeated profile clicks must not hammer the router's DNS. This cache
        // contains only validated physical-DNS answers and expires after a minute;
        // Off/Home and changes to the physical network/DNS clear it immediately.
        if let cached = endpointCache[original.endpointHost], continuousNow() < cached.expires {
            var profile = original; profile.resolvedIP = cached.ip
            tunnelEndpoint = (profile.id,profile.endpointHost,cached.ip)
            return profile
        }
        let servers = Array(physical.dnsServers.filter { !$0.contains(":") && !Profile.isRoutingFakeIP($0) }.prefix(3))
        // Only the root resolver may send DNS to these physical servers. All
        // ordinary traffic stays blocked; remove the exception on every result.
        let resolution = Result { () throws -> String in
            try guardManager.configureRouting(RoutingSettings(),physical:physical)
            try guardManager.configureEndpointDNS(servers,physical:physical)
            try guardManager.apply(tunnel:nil,profile:nil); saveGuard()
            return try resolveEndpoint(original.endpointHost,physical)
        }
        try guardManager.configureEndpointDNS([],physical:physical)
        try guardManager.apply(tunnel:nil,profile:nil); saveGuard()
        let address = try resolution.get()
        guard Profile.isIP(address), !address.contains(":"), !Profile.isRoutingFakeIP(address) else { throw AppError.message("DNS VPN-сервера вернул служебный или неподдерживаемый адрес") }
        var profile = original; profile.resolvedIP = address
        tunnelEndpoint = (profile.id,profile.endpointHost,address)
        endpointCache[original.endpointHost] = (address,continuousNow()+60)
        if original.resolvedIP.map(Profile.isRoutingFakeIP) == true { event("Исправлен сохранённый служебный адрес VPN-сервера") }
        return profile
    }
    private func probeHealth(interface: String, dns: [String]?) {
        if let health = healthCheck, asyncHealth == nil { completeHealthProbe(health(interface)); return }
        if healthProbeToken != nil {
            if continuousNow() - healthProbeStarted >= 30 {
                cancelHealthProbe(); connectionFailed(immediate:false)
            }
            return
        }
        let token = UUID(); healthProbeToken = token; healthProbeStarted = continuousNow()
        let completion: (Bool) -> Void = { [weak self] healthy in
            guard let self = self else { return }
            self.queue.async {
                // A slow pre-wake/old-profile result must not revive VPN after
                // Home, Off, recovery, a disconnect or tunnel replacement.
                guard self.healthProbeToken == token, self.tunnel.interface == interface else { return }
                self.healthProbeToken = nil
                self.completeHealthProbe(healthy)
            }
        }
        if let check = asyncHealth { check(interface,dns,completion) }
        else { DispatchQueue.global(qos:.utility).async { completion(HealthProbe.check(tunnel:interface,dns:dns)) } }
    }
    private func completeHealthProbe(_ healthy: Bool) {
        guard healthy else { connectionFailed(immediate:false); return }
        let wasConnected = status.phase == .connected
        status.phase = .connected
        status.message = settings.routing.mode == .rules ? "VPN подключён · маршруты по доменам" : "VPN подключён · трафик проверен"
        status.verifiedAt = now(); failures = 0; attempted = 0; round = 0
        settings.selectedID = status.profileID
        retryTunnelAfterBackoff = false; nextCheck = now().addingTimeInterval(30)
        if !wasConnected { event("\(status.profileName ?? "Профиль"): доступ через VPN подтверждён") }
    }
    private func connectionFailed(immediate: Bool) {
        failures += immediate ? 3 : 1
        status.phase = .recovering; status.verifiedAt = nil; status.message = settings.routing.mode == .rules ? "VPN восстанавливается. Выбранные сервисы закрыты; прямые работают." : "Связь не подтверждена. Прямой доступ закрыт."
        status.guardActive = guardManager.active
        guard failures >= 3 else { nextCheck = now().addingTimeInterval(10); return }
        failures = 0; attempted += 1
        event("\(status.profileName ?? "Профиль"): повторные проверки не прошли")
        if attempted >= settings.profiles.count {
            attempted = 0; nextCheck = now().addingTimeInterval(Policy.retryDelay(round: round)); round += 1
            retryTunnelAfterBackoff = true
            status.message = "Все профили не отвечают. Держим VPN и повторяем попытки."; return
        }
        do { try stopProtectedTunnel(physical: observedPhysical); index = Policy.next(index: index, count: settings.profiles.count); nextCheck = .distantPast; event("Переходим на резервный профиль") }
        catch { status.phase = .error; status.message = error.localizedDescription; nextCheck = now().addingTimeInterval(30) }
    }
    private func stopProtectedTunnel(physical: PhysicalNetwork) throws {
        cancelHealthProbe()
        // Tighten PF before removing the core's physical sockets and old tunnel.
        try guardManager.configureRouting(RoutingSettings(), physical: physical)
        try guardManager.apply(tunnel: nil, profile: nil)
        guardRequired = true; saveGuard()
        try domainRoutes.stop()
        try tunnel.stop()
    }
}

