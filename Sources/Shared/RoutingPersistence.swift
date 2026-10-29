import Foundation
import Darwin

struct RoutingPersistenceConflict: LocalizedError {
    let current: RoutingSettings
    var errorDescription: String? { "Правила изменены другим экземпляром AutoTurn. Загружена актуальная копия; проверь список и повтори своё изменение." }
}
struct RoutingPersistenceFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// No VPN keys or profiles are stored here. The current export is authoritative
// across app replacements and writes made by older apps to the shared Keychain.
final class RoutingPersistence {
    let directory: URL
    var currentURL: URL { directory.appendingPathComponent("current.json") }
    var previousURL: URL { directory.appendingPathComponent("previous.json") }
    private let localLock = NSLock()
    init(directory: URL) { self.directory = directory }
    func load(fallback: RoutingSettings) throws -> RoutingSettings {
        try locked { try readOrMigrate(fallback:fallback) }
    }
    func save(_ proposed: RoutingSettings, expected: RoutingSettings) throws -> RoutingSettings {
        try locked {
            let current = try readOrMigrate(fallback:expected)
            let incoming = try proposed.validated()
            let value: RoutingSettings
            if current != expected && incoming != expected && incoming != current {
                throw RoutingPersistenceConflict(current:current)
            }
            value = incoming == expected ? current : incoming
            if value != current {
                try write(current,to:previousURL)
                try write(value,to:currentURL)
            }
            return value
        }
    }
    private func readOrMigrate(fallback: RoutingSettings) throws -> RoutingSettings {
        let files = FileManager.default
        let exists = files.fileExists(atPath:currentURL.path)
        if exists, let current = try? read(currentURL) { return current }
        if files.fileExists(atPath:previousURL.path), let previous = try? read(previousURL) {
            // Preserve a damaged current file for investigation before repair.
            if exists { try files.moveItem(at:currentURL,to:directory.appendingPathComponent("damaged-\(UUID().uuidString).json")) }
            try write(previous,to:currentURL)
            return previous
        }
        guard !exists && !files.fileExists(atPath:previousURL.path) else {
            throw RoutingPersistenceFailure(message:"Не удалось прочитать обе копии маршрутов. Файлы сохранены; пустой список поверх них не записан.")
        }
        let initial = try fallback.validated()
        try write(initial,to:previousURL)
        try write(initial,to:currentURL)
        return initial
    }
    private func read(_ file: URL) throws -> RoutingSettings {
        let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
        guard size <= 800000 else { throw RoutingPersistenceFailure(message:"Копия маршрутов превышает допустимый размер") }
        return try RoutingExport.read(Data(contentsOf:file))
    }
    private func write(_ value: RoutingSettings, to file: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(RoutingExport(routing:value)).write(to:file,options:.atomic)
        guard chmod(file.path,0o600) == 0 else { throw RoutingPersistenceFailure(message:"Не удалось защитить файл маршрутов") }
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        localLock.lock(); defer { localLock.unlock() }
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let fd = open(directory.appendingPathComponent("settings.lock").path,O_CREAT | O_RDWR | O_NOFOLLOW,0o600)
            guard fd >= 0 else { throw RoutingPersistenceFailure(message:"Не удалось открыть блокировку сохранения маршрутов") }
            defer { close(fd) }
            guard flock(fd,LOCK_EX) == 0 else { throw RoutingPersistenceFailure(message:"Не удалось заблокировать сохранение маршрутов") }
            defer { _ = flock(fd,LOCK_UN) }
            return try action()
        } catch let error as RoutingPersistenceConflict { throw error }
        catch let error as RoutingPersistenceFailure { throw error }
        catch { throw RoutingPersistenceFailure(message:"Не удалось сохранить или прочитать копию маршрутов: " + error.localizedDescription) }
    }
}
