import Foundation

enum SetupAutomaticAction: Equatable { case location, service, notifications }

// Mode is deliberately absent: Off controls the tunnel, not installation or
// permission readiness. Each native prompt is started at most once per launch;
// cancelling never creates a timer-driven prompt loop. Buttons allow retries.
struct SetupAutomation {
    var deferred = false
    private(set) var requestedLocation = false
    private(set) var requestedService = false
    private(set) var requestedNotifications = false
    mutating func noteServiceRequest() { requestedService = true }
    mutating func next(_ state: SetupReadiness, busy: Bool, modal: Bool, canRequestLocation: Bool) -> SetupAutomaticAction? {
        guard !deferred, !busy, !modal, !state.serviceInstalling, state.keychainReady, state.profileReady else { return nil }
        switch state.stage {
        case .location:
            guard state.locationChecked, canRequestLocation, !requestedLocation else { return nil }
            requestedLocation = true; return .location
        case .service:
            guard state.serviceChecked, !state.serviceReady, !requestedService else { return nil }
            requestedService = true; return .service
        case .notifications:
            guard state.notifications == .notRequested, !state.notificationsSkipped, !requestedNotifications else { return nil }
            requestedNotifications = true; return .notifications
        default: return nil
        }
    }
}
