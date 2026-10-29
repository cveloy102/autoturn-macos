import Foundation

final class ProfileImportBatch {
    let urls: [URL]
    private let scoped: [URL]
    init(_ urls: [URL]) { self.urls = urls; scoped = urls.filter { $0.startAccessingSecurityScopedResource() } }
    deinit { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
}

// Holds a user's file access until a busy connect/install has finished.
final class ProfileImportQueue {
    private var batches: [ProfileImportBatch] = []
    var count: Int { batches.reduce(0) { $0 + $1.urls.count } }
    func enqueue(_ urls: [URL]) -> Bool {
        let valid = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "conf" }
        guard !valid.isEmpty else { return false }
        var paths = Set(batches.flatMap(\.urls).map { $0.standardizedFileURL.path })
        let fresh = valid.filter { paths.insert($0.standardizedFileURL.path).inserted }
        guard count + fresh.count <= 32 else { return false }
        if !fresh.isEmpty { batches.append(ProfileImportBatch(fresh)) }
        return true
    }
    func takeIfIdle(_ idle: Bool) -> ProfileImportBatch? {
        guard idle, !batches.isEmpty else { return nil }
        return batches.removeFirst()
    }
}
