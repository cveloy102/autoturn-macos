import Foundation

enum SetupStage: String, CaseIterable { case keychain, profile, location, service, notifications, ready }
enum NotificationAccess { case unknown, notRequested, denied, allowed }
struct SetupReadiness {
    var keychainReady = false
    var profileReady = false
    var locationRequired = true
    var locationChecked = true
    var locationGranted = false
    var serviceReady = false
    var serviceChecked = true
    var serviceInstalling = false
    var serviceMessage = ""
    var notifications = NotificationAccess.unknown
    var notificationsSkipped = false
    var pendingImports = 0
    var stage: SetupStage {
        if !keychainReady { return .keychain }
        if !profileReady { return .profile }
        if locationRequired && (!locationChecked || !locationGranted) { return .location }
        if !serviceReady || !serviceChecked || serviceInstalling { return .service }
        if notifications != .allowed && !notificationsSkipped { return .notifications }
        return .ready
    }
    var signature: String { "\(stage.rawValue):\(keychainReady):\(profileReady):\(locationRequired):\(locationGranted):\(locationChecked):\(serviceReady):\(serviceChecked):\(serviceInstalling):\(serviceMessage):\(notifications):\(notificationsSkipped):\(pendingImports)" }
}
