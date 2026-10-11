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
    let physicalRead: () -> PhysicalNetwork
    let healthCheck: (String) -> Bool
    let stateDirectory: String
    var settings = Settings(), status = ServiceStatus()
    var observation = NetworkObservation(available: false, interface: nil, ssid: nil, gateway: nil)
    var observedAt = Date.distantPast, observedPhysical = PhysicalNetwork()
    var index = 0, failures = 0, attempted = 0, round = 0
    var nextCheck = Date.distantPast
    var guardRequired = false
    var pendingTunnelReset = false
    let installation: Installation
    let timer: DispatchSourceTimer
    let monitor = NWPathMonitor()
    init(_ installation: Installation, protection: TrafficProtection = TrafficGuard(), managedTunnel: ManagedTunnel = Tunnel(), physical: @escaping () -> PhysicalNetwork = PhysicalNetwork.read, health: @escaping (String) -> Bool = HealthProbe.check, stateDirectory: String = support, monitoring: Bool = true) {
        self.installation = installation; guardManager = protection; tunnel = managedTunnel; physicalRead = physical; healthCheck = health; self.stateDirectory = stateDirectory
        observedPhysical = physical()
        timer = DispatchSource.makeTimerSource(queue: queue)
        if let saved = try? JSONDecoder().decode(SavedGuard.self, from: Data(contentsOf: URL(fileURLWithPath: stateDirectory + "/guard.json"))) {
            guardRequired = saved.required; guardManager.restoreToken(saved.token)
        }
        if guardRequired { do { try guardManager.apply(tunnel:nil,profile:nil); saveGuard() } catch { status.phase = .error; status.message = "Не удалось восстановить блокировку после перезапуска" } }
        tunnel.recoverJournal()
        timer.schedule(deadline: monitoring ? .now() : .now() + 3600, repeating: monitoring ? 5 : 3600)
        timer.setEventHandler { [weak self] in self?.tick() }; timer.resume()
        monitor.pathUpdateHandler = { [weak self] _ in guard let self = self else { return }; self.queue.async { self.physicalNetworkChanged() } }
        if monitoring { monitor.start(queue: DispatchQueue(label: "ru.hl100.autoturn.path")) }
    }
    func physicalNetworkChanged() {
        // VPN route/DNS changes also trigger NWPathMonitor. Only an actual physical
        // interface or gateway change may invalidate the app's SSID observation.
        nextCheck = .distantPast; tick()
    }
    func recordNetwork(_ value: NetworkObservation) {
        observation = value; observedAt = Date()
    }
    func event(_ text: String) { let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"; status.events.append("\(formatter.string(from: Date()))  \(text)"); status.events = Array(status.events.suffix(100)) }
    func saveGuard() { if let data = try? JSONEncoder().encode(SavedGuard(required: guardRequired, token: guardManager.token)) { try? data.write(to: URL(fileURLWithPath: stateDirectory + "/guard.json"), options: .atomic); chmod(stateDirectory + "/guard.json", 0o600) } }
    func handle(_ request: RPCRequest) -> RPCResponse {
        do {
            switch request.command {
            case "status": break
            case "configure":
                guard var value = request.settings, value.profiles.count <= 32, value.homeSSIDs.count <= 32, value.homeSSIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32 }) else { throw AppError.message("Некорректные настройки") }
                value.profiles = try value.profiles.map { try $0.validated() }
                guard Set(value.profiles.map { $0.id }).count == value.profiles.count else { throw AppError.message("Повторные профили") }
                if value.mode != .off && value.profiles.isEmpty { throw AppError.message("Сначала импортируй профиль") }
                let changed = value.profiles != settings.profiles || value.selectedID != settings.selectedID
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
                if settings.mode != .off { try guardManager.apply(tunnel: nil, profile: nil); guardRequired = true; saveGuard(); try tunnel.stop() }
                index = Policy.next(index: index, count: settings.profiles.count); attempted = 0; failures = 0; nextCheck = .distantPast; tick()
            case "stop": settings.mode = .off; tick()
            default: throw AppError.message("Команда не поддерживается")
            }
            return RPCResponse(ok: true, status: status, error: nil)
        } catch {
            status.phase = .error; status.message = error.localizedDescription; status.guardActive = guardManager.active
            event(status.message); return RPCResponse(ok: false, status: status, error: status.message)
        }
    }
    func tick() {
        let physical = physicalRead()
        let changed = physical.interface != observedPhysical.interface || physical.gateway != observedPhysical.gateway
        if changed { if observation.interface != physical.interface || observation.gateway != physical.gateway { observedAt = .distantPast }; nextCheck = .distantPast }
        observedPhysical = physical
        var network = NetworkObservation(available: physical.available, interface: physical.interface, ssid: nil, gateway: physical.gateway)
        // SSID lease is only accepted for the current physical interface, never a stale home Wi-Fi.
        if Date().timeIntervalSince(observedAt) < 20 && observation.interface == physical.interface && observation.gateway == physical.gateway { network.ssid = observation.ssid }
        status.network = network.ssid ?? (network.available ? "\(network.interface ?? "") · сеть не подтверждена" : "Нет подключения")
        status.mode = settings.mode
        let wanted = settings.mode == .off ? false : settings.profiles.isEmpty ? guardRequired : Policy.wantsVPN(mode: settings.mode, network: network, homes: settings.homeSSIDs)
        do {
            if !wanted {
                pendingTunnelReset = false
                var cleanupError: Error?
                if tunnel.running || guardManager.active || guardRequired || guardManager.token != nil {
                    // Once direct Internet is requested, release PF before stopping
                    // the engine so a slow process exit cannot leave the user blocked.
                    do { try guardManager.remove() } catch { cleanupError = error }
                    do { try tunnel.stop() } catch { if cleanupError == nil { cleanupError = error } }
                    guardRequired = guardManager.active; saveGuard(); event("Наш VPN отключён")
                }
                status.phase = cleanupError == nil ? (settings.mode == .off ? .off : .home) : .error
                status.message = cleanupError?.localizedDescription ?? (settings.mode == .off ? "Выключено вручную · прямое подключение разрешено" : "Домашняя сеть · через роутер")
                status.guardActive = guardManager.active; status.verifiedAt = nil; status.tunnel = nil; status.profileID = nil; status.profileName = nil
                if let error = cleanupError { event(error.localizedDescription) }
                return
            }
            guardRequired = true; saveGuard()
            if (changed || pendingTunnelReset) && tunnel.running { try guardManager.apply(tunnel: nil, profile: nil); try tunnel.stop(); event("Пересоздаём туннель после изменения сети или профиля") }
            pendingTunnelReset = false
            if !network.available || settings.profiles.isEmpty {
                try guardManager.apply(tunnel: tunnel.running ? tunnel.interface : nil, profile: nil); saveGuard()
                status.phase = .waiting; status.message = settings.profiles.isEmpty ? "Ожидаем профили от приложения. Прямой доступ закрыт." : "Ждём сеть. Режим VPN сохранён."; status.guardActive = guardManager.active; status.verifiedAt = nil; return
            }
            let profile = settings.profiles[index % settings.profiles.count]
            status.profileID = profile.id; status.profileName = profile.name
            if tunnel.running { try guardManager.apply(tunnel: tunnel.interface, profile: profile); saveGuard() }
            if Date() < nextCheck { status.guardActive = guardManager.active; return }
            if !tunnel.running {
                status.phase = .connecting; status.message = "Создаём туннель и проверяем трафик"
                try guardManager.apply(tunnel: nil, profile: profile); saveGuard()
                do { try tunnel.start(profile, physical: physical, engine: installation.engine); try guardManager.apply(tunnel: tunnel.interface, profile: profile); saveGuard(); event("Туннель \(profile.name) создан") }
                catch { event(error.localizedDescription); try tunnel.stop(); try guardManager.apply(tunnel: nil, profile: profile); connectionFailed(immediate: true); return }
            }
            status.tunnel = tunnel.interface; status.guardActive = guardManager.active
            if let iface = tunnel.interface, healthCheck(iface) {
                let wasConnected = status.phase == .connected
                status.phase = .connected; status.message = "VPN подключён · трафик проверен"; status.verifiedAt = Date()
                failures = 0; attempted = 0; round = 0; nextCheck = Date().addingTimeInterval(30)
                if !wasConnected { event("\(profile.name): доступ через VPN подтверждён") }
            } else { connectionFailed(immediate: false) }
        } catch {
            status.phase = .error; status.message = error.localizedDescription; status.guardActive = guardManager.active; status.verifiedAt = nil
            nextCheck = Date().addingTimeInterval(30); event(status.message)
        }
    }
    private func connectionFailed(immediate: Bool) {
        failures += immediate ? 3 : 1
        status.phase = .recovering; status.verifiedAt = nil; status.message = "Связь не подтверждена. Прямой доступ закрыт."
        status.guardActive = guardManager.active
        guard failures >= 3 else { nextCheck = Date().addingTimeInterval(10); return }
        failures = 0; attempted += 1
        event("\(status.profileName ?? "Профиль"): повторные проверки не прошли")
        if attempted >= settings.profiles.count {
            attempted = 0; nextCheck = Date().addingTimeInterval(Policy.retryDelay(round: round)); round += 1
            status.message = "Все профили не отвечают. Держим VPN и повторяем попытки."; return
        }
        do { try guardManager.apply(tunnel: nil, profile: nil); saveGuard(); try tunnel.stop(); index = Policy.next(index: index, count: settings.profiles.count); nextCheck = .distantPast; event("Переходим на резервный профиль") }
        catch { status.phase = .error; status.message = error.localizedDescription; nextCheck = Date().addingTimeInterval(30) }
    }
}

