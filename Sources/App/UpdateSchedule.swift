import Foundation

// Dates and notification history are non-secret; VPN profiles remain in Keychain.
final class UpdateHistory {
    static let interval: TimeInterval = 60 * 60
    static let retryInterval: TimeInterval = 60 * 60
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func isDue(at now: Date = Date()) -> Bool {
        Self.isDue(now:now,lastSuccess:defaults.object(forKey:"updates.lastSuccess") as? Date,lastAttempt:defaults.object(forKey:"updates.lastAttempt") as? Date)
    }
    static func isDue(now:Date,lastSuccess:Date?,lastAttempt:Date?) -> Bool {
        if let success = lastSuccess, success <= now, now.timeIntervalSince(success) < interval { return false }
        if let attempt = lastAttempt, attempt <= now, now.timeIntervalSince(attempt) < retryInterval { return false }
        return true
    }
    func attempted(at now:Date = Date()) { defaults.set(now,forKey:"updates.lastAttempt") }
    func succeeded(at now:Date = Date()) { defaults.set(now,forKey:"updates.lastSuccess") }
    func shouldNotify(_ build:Int) -> Bool { build > defaults.integer(forKey:"updates.lastNotifiedBuild") }
    func shouldNotify(version:String,build:Int) -> Bool {
        let versions = defaults.stringArray(forKey:"updates.notifiedVersions") ?? []
        return !versions.contains(version) && shouldNotify(build)
    }
    func notified(version:String,build:Int) {
        var versions = defaults.stringArray(forKey:"updates.notifiedVersions") ?? []
        if !versions.contains(version) { versions.append(version) }
        defaults.set(versions,forKey:"updates.notifiedVersions"); notified(build)
    }
    func notified(_ build:Int) { defaults.set(build,forKey:"updates.lastNotifiedBuild") }
}
