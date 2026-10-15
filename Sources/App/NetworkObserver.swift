import Foundation
import AppKit
import CoreWLAN
import CoreLocation
import SystemConfiguration
import Network

final class NetworkObserver: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    private let monitor = NWPathMonitor()
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private let samplingQueue = DispatchQueue(label:"ru.hl100.autoturn.wifi-read",qos:.userInitiated)
    private let sample: () -> NetworkObservation
    private let monitoring: Bool
    // This mailbox and the cache are main-thread owned. At most one slow native
    // read and one replacement request exist; UI rendering only reads the cache.
    private var reading = false, readAgain = false
    private var latest = NetworkObservation(available:false,interface:nil,ssid:nil,gateway:nil)
    private var servicesEnabled: Bool?
    var changed: ((NetworkObservation) -> Void)?
    override convenience init() { self.init(sampling:NetworkObserver.readSnapshot,monitoring:true) }
    init(sampling: @escaping () -> NetworkObservation, monitoring: Bool) {
        self.sample = sampling; self.monitoring = monitoring
        super.init()
        guard monitoring else { return }
        location.delegate = self
        monitor.pathUpdateHandler = { [weak self] _ in DispatchQueue.main.async { self?.report() } }
        monitor.start(queue:DispatchQueue(label:"ru.hl100.autoturn.network"))
        timer = Timer(timeInterval:3,repeats:true) { [weak self] _ in self?.report() }
        RunLoop.main.add(timer!,forMode:.common)
        report()
    }
    static let locationSettingsURL = URL(string:"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices")!
    func setAutomationActive(_ enabled: Bool) {
        if enabled && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Observe Wi-Fi for automatic VPN switching")
        } else if !enabled, let token = activity {
            ProcessInfo.processInfo.endActivity(token); activity = nil
        }
    }
    deinit {
        timer?.invalidate(); monitor.cancel()
        if let token = activity { ProcessInfo.processInfo.endActivity(token) }
    }
    func requestInitialPermission() {
        if location.authorizationStatus == .notDetermined { location.requestAlwaysAuthorization() }
    }
    var locationPermissionMissing: Bool {
        let status = location.authorizationStatus
        return servicesEnabled == false || (status != .authorizedAlways && status != .authorized)
    }
    func requestPermission() {
        requestInitialPermission()
        // Re-requesting a denied permission does not show another system prompt.
        if !NSWorkspace.shared.open(Self.locationSettingsURL) {
            NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!)
        }
        report()
    }
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) { report() }
    func report() {
        if reading { readAgain = true; return }
        reading = true
        samplingQueue.async { [weak self] in
            guard let self = self else { return }
            let enabled = self.monitoring ? CLLocationManager.locationServicesEnabled() : nil
            let observation = self.sample()
            DispatchQueue.main.async {
                self.reading = false; self.latest = observation; self.servicesEnabled = enabled
                self.changed?(observation)
                if self.readAgain { self.readAgain = false; self.report() }
            }
        }
    }
    func snapshot() -> NetworkObservation {
        var value = latest
        if let sampled = value.sampledContinuouslyAt, !(0..<20).contains(ContinuousTime.now()-sampled) { value.ssid = nil }
        return value
    }
    private static func readSnapshot() -> NetworkObservation {
        let sampledAt = Date()
        let sampledContinuouslyAt = ContinuousTime.now()
        guard let store = SCDynamicStoreCreate(nil, "AutoTurnUI" as CFString, nil, nil), let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any], let iface = global["PrimaryInterface"] as? String, !iface.hasPrefix("utun") else { return NetworkObservation(available: false, interface: nil, ssid: nil, gateway: nil, sampledAt:sampledAt, sampledContinuouslyAt:sampledContinuouslyAt) }
        let wireless = CWWiFiClient.shared().interface(withName: iface)
        return NetworkObservation(available: true, interface: iface, ssid: wireless?.ssid(), gateway: global["Router"] as? String, sampledAt:sampledAt, sampledContinuouslyAt:sampledContinuouslyAt)
    }
}
