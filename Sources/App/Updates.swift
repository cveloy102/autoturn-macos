import Foundation
import CryptoKit

struct MacRelease: Codable {
    var version: String
    var build: Int
    var minimumOS: String
    var archiveURL: String
    var sha256: String
    var signature: String
    var notes: String
}
struct SignedRelease: Codable { var payload: String; var signature: String }

final class Updater {
    // A separate platform feed avoids confusing Android and macOS release numbers.
    let feed = "https://api.github.com/repos/cveloy102/autoturn-macos/releases?per_page=100"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept":"application/vnd.github+json", "User-Agent":"AutoTurn-macOS"]
        return URLSession(configuration:config)
    }()
    var candidate: MacRelease?
    var archive: URL?
    private var publicKey: Data? { (Bundle.main.object(forInfoDictionaryKey: "ATUpdatePublicKey") as? String).flatMap { Data(base64Encoded: $0) }.flatMap { $0.count == 32 ? $0 : nil } }
    // Persist only the signed public release envelope, never profiles or VPN keys.
    // Validate again against this installed build before restoring the indicator.
    func restoreCandidate() {
        guard let key = publicKey, let data = UserDefaults.standard.data(forKey:"updates.signedCandidate"), data.count <= 128*1024 else { return }
        let build = Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "0") ?? 0
        candidate = try? Self.validateMetadata(data,publicKey:key,installedBuild:build)
        if candidate == nil { UserDefaults.standard.removeObject(forKey:"updates.signedCandidate") }
    }
    func check(installedBuildOverride:Int? = nil, completion: @escaping (Result<MacRelease?, Error>) -> Void) {
        guard let publicKey = publicKey else { completion(.failure(AppError.message("Обновления подготовлены, но ключ подписи релизов ещё не настроен. Сейчас доступна только эта тестовая сборка."))); return }
        session.dataTask(with: URL(string:feed)!) { data, response, error in
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data = data, data.count <= 4*1024*1024, let releases = (try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]] else { DispatchQueue.main.async { completion(.failure(AppError.message("Не удалось проверить GitHub. Повтори позже."))) }; return }
            let release = releases.first { item in (item["draft"] as? Bool) == false && (item["prerelease"] as? Bool) == false && (item["tag_name"] as? String)?.hasPrefix("macos-v") == true }
            guard let item = release, let assets = item["assets"] as? [[String:Any]], let asset = assets.first(where: { $0["name"] as? String == "macos-update.json" }), let address = asset["browser_download_url"] as? String, let url = URL(string:address), url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/cveloy102/autoturn-macos/releases/download/macos-v") else { DispatchQueue.main.async { self.candidate = nil; UserDefaults.standard.removeObject(forKey:"updates.signedCandidate"); completion(.success(nil)) }; return }
            self.checkMetadata(url: url, publicKey:publicKey, installedBuildOverride:installedBuildOverride, completion:completion)
        }.resume()
    }
    private func checkMetadata(url: URL, publicKey: Data, installedBuildOverride:Int?, completion: @escaping (Result<MacRelease?, Error>) -> Void) {
        let task = session.dataTask(with: url) { data, response, error in
            let result: Result<MacRelease?, Error> = Result {
                if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
                guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data, data.count <= 128*1024 else { throw AppError.message("Не удалось проверить GitHub. Повтори позже.") }
                let installedBuild = installedBuildOverride ?? (Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "0") ?? 0)
                return try Self.validateMetadata(data, publicKey:publicKey, installedBuild:installedBuild)
            }
            DispatchQueue.main.async {
                if case .success(let release) = result {
                    self.candidate = release
                    if release != nil, let data = data { UserDefaults.standard.set(data,forKey:"updates.signedCandidate") }
                    else { UserDefaults.standard.removeObject(forKey:"updates.signedCandidate") }
                }
                completion(result)
            }
        }; task.resume()
    }
    static func validateMetadata(_ data: Data, publicKey: Data, installedBuild: Int) throws -> MacRelease? {
        let envelope = try JSONDecoder().decode(SignedRelease.self, from:data)
        guard let payload = Data(base64Encoded:envelope.payload), let signature = Data(base64Encoded:envelope.signature), try Curve25519.Signing.PublicKey(rawRepresentation:publicKey).isValidSignature(signature,for:payload) else { throw AppError.message("Подпись сведений о релизе не прошла проверку") }
        let release = try JSONDecoder().decode(MacRelease.self,from:payload)
        guard let url = URL(string:release.archiveURL), url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/cveloy102/autoturn-macos/releases/download/"), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, release.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { throw AppError.message("Некорректные сведения о релизе") }
        guard release.version.range(of:"^[0-9]+\\.[0-9]+\\.[0-9]+$",options:.regularExpression) != nil, release.build > 0 else { throw AppError.message("Некорректная версия релиза") }
        let parts = release.minimumOS.split(separator:".",omittingEmptySubsequences:false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && Int($0) != nil }), let major = Int(parts[0]), major >= 10 else { throw AppError.message("Некорректная версия macOS") }
        let required = parts.map { Int($0)! }
        let minimum = OperatingSystemVersion(majorVersion:major,minorVersion:required.count > 1 ? required[1] : 0,patchVersion:required.count > 2 ? required[2] : 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(minimum) else { throw AppError.message("Новая версия требует macOS \(release.minimumOS)") }
        return release.build > installedBuild ? release : nil
    }
    static func validateArchive(_ data:Data, release:MacRelease, publicKey:Data) throws {
        guard !data.isEmpty, data.count <= 150*1024*1024,
              SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == release.sha256,
              let signature = Data(base64Encoded:release.signature),
              try Curve25519.Signing.PublicKey(rawRepresentation:publicKey).isValidSignature(signature,for:data) else {
            throw AppError.message("Пакет обновления не прошёл проверку")
        }
    }
    static func validateBundle(_ app:URL, release:MacRelease) throws {
        guard let bundle = Bundle(url:app), bundle.bundleIdentifier == "ru.hl100.autoturn",
              bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String == release.version,
              bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String == String(release.build),
              bundle.url(forResource:"install-service",withExtension:"sh") != nil else { throw AppError.message("В пакете другая версия приложения") }
        func verify(_ executable:String,_ arguments:[String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw AppError.message("Пакет не прошёл проверку подписи или совместимости Intel/Apple Silicon") }
        }
        try verify("/usr/bin/codesign",["--verify","--deep","--strict",app.path])
        for component in ["Contents/MacOS/AutoTurn","Contents/Library/LaunchServices/AutoTurnHelper","Contents/Resources/amneziawg-go","Contents/Resources/routing-core"] {
            try verify("/usr/bin/lipo",[app.appendingPathComponent(component).path,"-verify_arch","x86_64","arm64"])
        }
    }
    func download(_ release: MacRelease, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let publicKey = publicKey, let url = URL(string: release.archiveURL) else { completion(.failure(AppError.message("Обновления не настроены"))); return }
        session.downloadTask(with: url) { temporary, response, error in
            let result: Result<URL, Error> = Result {
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let temporary = temporary else { throw AppError.message("Не удалось скачать обновление") }
                let attrs = try FileManager.default.attributesOfItem(atPath: temporary.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0 && size <= 150*1024*1024 else { throw AppError.message("Пакет слишком большой") }
                let data = try Data(contentsOf: temporary, options:.mappedIfSafe)
                try Self.validateArchive(data,release:release,publicKey:publicKey)
                let dir = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("ru.hl100.autoturn/updates")
                try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
                let target = dir.appendingPathComponent("AutoTurn-\(release.build).zip")
                if FileManager.default.fileExists(atPath:target.path) { try FileManager.default.removeItem(at:target) }; try FileManager.default.moveItem(at:temporary,to:target)
                return target
            }
            DispatchQueue.main.async { if case .success(let file) = result { self.archive = file }; completion(result) }
        }.resume()
    }
}
