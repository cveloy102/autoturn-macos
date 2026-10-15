import Foundation
import Darwin

enum OwnedProcessRecovery {
    // Only root-owned processes with our exact executable and argument list qualify.
    static func candidates(_ output: String) -> [Int32:String] {
        var result: [Int32:String] = [:]
        let commands = [support + "/amneziawg-go -f utun",support + "/routing-core run -c " + support + "/routing-core.json"]
        for line in output.components(separatedBy:.newlines) {
            let parts = line.split(maxSplits:2,omittingEmptySubsequences:true,whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count == 3, parts[1] == "0", let pid = Int32(parts[0]), commands.contains(String(parts[2])) { result[pid] = String(parts[2]) }
        }
        return result
    }
    static func current() throws -> [Int32:String] { candidates(try SystemCommand.checked("/bin/ps",["-axo","pid=,uid=,command="])) }
    static func stop() throws {
        let owned = try current()
        for (pid,command) in owned where try current()[pid] == command { kill(pid,SIGTERM) }
        let deadline = ContinuousTime.now() + 2
        while ContinuousTime.now() < deadline { if try current().isEmpty { return }; Thread.sleep(forTimeInterval:0.05) }
        for (pid,command) in owned where try current()[pid] == command { kill(pid,SIGKILL) }
        let end = ContinuousTime.now() + 2
        while ContinuousTime.now() < end { if try current().isEmpty { return }; Thread.sleep(forTimeInterval:0.05) }
        guard try current().isEmpty else { throw AppError.message("Не удалось остановить оставшиеся процессы AutoTurn") }
    }
}

enum EmergencyNetworkRecovery {
    static func run() throws {
        guard getuid() == 0 else { throw AppError.message("Восстановление требует прав администратора") }
        _ = try? SystemCommand.run("/bin/launchctl",["bootout","system/ru.hl100.autoturn.helper"])
        defer { _ = try? SystemCommand.run("/bin/launchctl",["bootstrap","system","/Library/LaunchDaemons/ru.hl100.autoturn.helper.plist"]) }
        try OwnedProcessRecovery.stop()
        let guardManager = TrafficGuard()
        if let data = try? Data(contentsOf:URL(fileURLWithPath:support + "/guard.json")), let saved = try? JSONDecoder().decode(SavedGuard.self,from:data) { guardManager.restoreToken(saved.token) }
        try guardManager.remove()
        try RoutingCoreManager(protection:guardManager).recoverJournal(); try Tunnel().recoverJournal()
        try JSONEncoder().encode(SavedGuard(required:false,token:nil)).write(to:URL(fileURLWithPath:support + "/guard.json"),options:.atomic)
        chmod(support + "/guard.json",0o600)
        guard if_nametoindex("utun99") == 0 else { throw AppError.message("Интерфейс маршрутов ещё занят; восстановление не подтверждено") }
    }
}
