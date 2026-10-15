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
    let healthCheck: ((String) -> Bool)?
    let stateDirectory: String
    var settings = Settings(), status = ServiceStatus()
    var observation = NetworkObservation(available: false, interface: nil, ssid: nil, gateway: nil)
    var observedAt = Date.distantPast, observedPhysical = PhysicalNetwork()
    var confirmedNetwork: NetworkObservation?
    var confirmedAt = Date.distantPast
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
    init(_ installation: Installation, protection: TrafficProtection = TrafficGuard(), managedTunnel: ManagedTunnel = Tunnel(), routing: DomainRouting? = nil, physical: @escaping () -> PhysicalNetwork = PhysicalNetwork.read, health: ((String) -> Bool)? = nil, stateDirectory: String = support, monitoring: Bool = true, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.installation = installation; domainRoutes = routing ?? RoutingCoreManager(protection:protection,directory:stateDirectory); guardManager = protection; tunnel = managedTunnel; physicalRead = physical; healthCheck = health; self.stateDirectory = stateDirectory
        let historyURL = URL(fileURLWithPath:stateDirectory + "/events.json")
        if let size = try? historyURL.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 128 * 1024,
           let data = try? Data(contentsOf:historyURL), let history = try? JSONDecoder().decode([String].self,from:data) {
            status.events = Array(history.suffix(100))
        }
        observedPhysical = physical()
        timer = DispatchSource.makeTimerSource(queue: queue)
        if let saved = try? JSONDecoder().decode(SavedGuard.self, from: Data(contentsOf: URL(fileURLWithPath: stateDirectory + "/guard.json"))) {
            guardRequired = saved.required; guardManager.restoreToken(saved.token)
        }
        if guardRequired { do { try guardManager.apply(tunnel:nil,profile:nil); saveGuard() } catch { status.phase = .error; status.message = "Не удалось восстановить блокировку после перезапуска" } }
        if monitoring && stateDirectory == support {
            do { try OwnedProcessRecovery.stop() } catch { startupRecoveryError = error; status.phase = .error; status.message = error.localizedDescription }
        }
        domainRoutes.recoverJournal(); tunnel.recoverJournal()
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
    func recordNetwork(_ value: NetworkObservation) {
        let receivedAt = now(), sampledAt = value.sampledAt ?? receivedAt
        // Ignore queued/out-of-order observations, including samples from before
        // sleep. A future timestamp must not extend the trust window.
        guard sampledAt <= receivedAt.addingTimeInterval(2), receivedAt.timeIntervalSince(sampledAt) < 20,
              sampledAt >= observedAt else { return }
        if !value.available || value.interface != observation.interface || value.gateway != observation.gateway ||
            (value.ssid != nil && value.ssid != confirmedNetwork?.ssid) {
            confirmedNetwork = nil; confirmedAt = .distantPast
        }
        observation = value; observedAt = min(sampledAt,receivedAt)
        if value.available, value.ssid != nil {
            confirmedNetwork = value; confirmedAt = observedAt
        }
    }
    func event(_ text: String) {
        guard text != lastEventText else { return }; lastEventText = text
        let timestamp = ISO8601DateFormatter().string(from:now())
        status.events.append("\(timestamp)  \(text)"); status.events = Array(status.events.suffix(100))
        let path = stateDirectory + "/events.json"
        if let data = try? JSONEncoder().encode(status.events) {
            do { try data.write(to:URL(fileURLWithPath:path),options:.atomic); chmod(path,0o600) }
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
                guard Set(value.profiles.map { $0.id }).count == value.profiles.count else { throw AppError.message("Повторные профили") }
                if value.mode != .off && value.profiles.isEmpty { throw AppError.message("Сначала импортируй профиль") }
                let changed = value.profiles != settings.profiles || value.selectedID != settings.selectedID || value.routing.mode != settings.routing.mode || (value.routing.mode == .rules && value.routing.rules != settings.routing.rules)
                settings = value
                if let network = request.network { recordNetwork(network) }
                if changed { index = value.profiles.firstIndex { $0.id == value.selectedID } ?? 0; pendingTunnelReset = true }
                failures = 0; attempted = 0; round = 0; nextCheck = .distantPast
                event("Настройки применены"); tick()
            case "network":
                guard let value = request.network else { throw AppError.message("Нет состояния сети") }
                let changed = value.ssid != observation.ssid || value.interface != observation.interface || value.available != observation.available
                recordNetwork(value)
                if changed { nextCheck = .distantPast }; tick()
            case "check": nextCheck = .distantPast; tick()
            case "next":
                guard settings.profiles.count > 1 else { throw AppError.message("Нет резервного профиля") }
                if settings.mode != .off { try stopProtectedTunnel(physical: physicalRead()) }
                index = Policy.next(index: index, count: settings.profiles.count); attempted = 0; failures = 0; nextCheck = .distantPast; tick()
            case "recover":
                settings.mode = .off; pendingTunnelReset = false
                var errors: [String] = []
                do { try guardManager.remove() } catch { errors.append(error.localizedDescription) }
                do { try domainRoutes.stop() } catch { errors.append(error.localizedDescription) }
                do { try tunnel.stop() } catch { errors.append(error.localizedDescription) }
                if stateDirectory == support { do { try OwnedProcessRecovery.stop() } catch { errors.append(error.localizedDescription) } }
                domainRoutes.recoverJournal(); tunnel.recoverJournal()
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
        let physical = physicalRead()
        let changed = physical.interface != observedPhysical.interface || physical.gateway != observedPhysical.gateway
        if changed {
            if observation.interface != physical.interface || observation.gateway != physical.gateway { observedAt = .distantPast }
            if confirmedNetwork?.interface != physical.interface || confirmedNetwork?.gateway != physical.gateway { confirmedNetwork = nil; confirmedAt = .distantPast }
            nextCheck = .distantPast
        }
        observedPhysical = physical
        var network = NetworkObservation(available: physical.available, interface: physical.interface, ssid: nil, gateway: physical.gateway)
        // SSID lease is only accepted for the current physical interface, never a stale home Wi-Fi.
        if now().timeIntervalSince(observedAt) < 20 && observation.interface == physical.interface && observation.gateway == physical.gateway { network.ssid = observation.ssid }
        // A single nil SSID read must not immediately turn a confirmed home into
        // an external network. Do not renew this bounded lease on nil samples.
        if network.ssid == nil, network.available, now().timeIntervalSince(confirmedAt) < 20,
           let confirmed = confirmedNetwork, confirmed.interface == physical.interface, confirmed.gateway == physical.gateway {
            network.ssid = confirmed.ssid
        }
        status.network = network.ssid ?? (network.available ? "\(network.interface ?? "") · сеть не подтверждена" : "Нет подключения")
        status.mode = settings.mode
        let wanted = settings.mode == .off ? false : settings.profiles.isEmpty ? guardRequired : Policy.wantsVPN(mode: settings.mode, network: network, homes: settings.homeSSIDs)
        defer {
            let decision = "mode=\(settings.mode.rawValue) phase=\(status.phase.rawValue) guard=\(guardManager.active) available=\(network.available) ssidKnown=\(network.ssid != nil) home=\(network.ssid.map { settings.homeSSIDs.contains($0) } ?? false) interface=\(physical.interface ?? "none")"
            if decision != lastDecision {
                lastDecision = decision
                let age = Int(max(0,min(86400,now().timeIntervalSince(observedAt))))
                event(decision + " observationAge=\(age)s")
            }
        }
        do {
            if !wanted {
                pendingTunnelReset = false; retryTunnelAfterBackoff = false
                var cleanupError: Error?
                if cleanupPending || tunnel.running || tunnel.interface != nil || guardManager.active || guardRequired || guardManager.token != nil {
                    // Once direct Internet is requested, release PF before stopping
                    // the engine so a slow process exit cannot leave the user blocked.
                    do { try guardManager.remove() } catch { cleanupError = error }
                    do { try domainRoutes.stop() } catch { if cleanupError == nil { cleanupError = error } }
                    do { try tunnel.stop() } catch { if cleanupError == nil { cleanupError = error } }
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
            if ((changed || pendingTunnelReset || (retryTunnelAfterBackoff && now() >= nextCheck)) && tunnel.running) || (!tunnel.running && tunnel.interface != nil) {
                try stopProtectedTunnel(physical: physical)
                retryTunnelAfterBackoff = false
                nextCheck = .distantPast
                event("Пересоздаём туннель после изменения сети, профиля или остановки движка")
            }
            pendingTunnelReset = false
            if !network.available || settings.profiles.isEmpty {
                try guardManager.apply(tunnel: tunnel.running ? tunnel.interface : nil, profile: nil); saveGuard()
                status.phase = .waiting; status.message = settings.profiles.isEmpty ? "Ожидаем профили от приложения. Прямой доступ закрыт." : "Ждём сеть. Режим VPN сохранён."; status.guardActive = guardManager.active; status.verifiedAt = nil; return
            }
            let profile = settings.profiles[index % settings.profiles.count]
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
            if let iface = tunnel.interface, (healthCheck?(iface) ?? HealthProbe.check(tunnel:iface,dns:settings.routing.mode == .rules ? profile.dns : nil)) {
                let wasConnected = status.phase == .connected
                status.phase = .connected; status.message = settings.routing.mode == .rules ? "VPN подключён · маршруты по доменам" : "VPN подключён · трафик проверен"; status.verifiedAt = now()
                failures = 0; attempted = 0; round = 0; retryTunnelAfterBackoff = false; nextCheck = now().addingTimeInterval(30)
                if !wasConnected { event("\(profile.name): доступ через VPN подтверждён") }
            } else { connectionFailed(immediate: false) }
        } catch {
            if settings.routing.mode == .rules { try? guardManager.configureRouting(RoutingSettings(),physical:physical); try? guardManager.apply(tunnel:tunnel.interface,profile:settings.profiles.isEmpty ? nil : settings.profiles[index % settings.profiles.count]); saveGuard() }
            status.phase = .error; status.message = error.localizedDescription; status.guardActive = guardManager.active; status.verifiedAt = nil
            nextCheck = now().addingTimeInterval(30); event(status.message)
        }
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
        // Tighten PF before removing the core's physical sockets and old tunnel.
        try guardManager.configureRouting(RoutingSettings(), physical: physical)
        try guardManager.apply(tunnel: nil, profile: nil)
        guardRequired = true; saveGuard()
        try domainRoutes.stop()
        try tunnel.stop()
    }
}

