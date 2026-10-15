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
    var changed: ((NetworkObservation) -> Void)?
    override init() { super.init(); location.delegate = self; monitor.pathUpdateHandler = { [weak self] _ in DispatchQueue.main.async { self?.report() } }; monitor.start(queue: DispatchQueue(label: "ru.hl100.autoturn.network")); timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.report() }; RunLoop.main.add(timer!,forMode:.common) }
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
        return !CLLocationManager.locationServicesEnabled() || (status != .authorizedAlways && status != .authorized)
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
    func report() { changed?(snapshot()) }
    func snapshot() -> NetworkObservation {
        let sampledAt = Date()
        guard let store = SCDynamicStoreCreate(nil, "AutoTurnUI" as CFString, nil, nil), let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any], let iface = global["PrimaryInterface"] as? String, !iface.hasPrefix("utun") else { return NetworkObservation(available: false, interface: nil, ssid: nil, gateway: nil, sampledAt:sampledAt) }
        let wireless = CWWiFiClient.shared().interface(withName: iface)
        return NetworkObservation(available: true, interface: iface, ssid: wireless?.ssid(), gateway: global["Router"] as? String, sampledAt:sampledAt)
    }
}
