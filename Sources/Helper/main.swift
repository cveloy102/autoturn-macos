import Foundation
import Darwin
import Security
import Network

func verifyClient(_ fd: Int32, installation: Installation) -> Bool {
    var uid: uid_t = 0, gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, uid == installation.uid else { return false }
    var pid: pid_t = 0, length = socklen_t(MemoryLayout<pid_t>.size)
    guard getsockopt(fd, 0, 0x002, &pid, &length) == 0, pid > 0 else { return false }
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [], &code) == errSecSuccess, let guest = code else { return false }
    guard SecCodeCheckValidity(guest, [], nil) == errSecSuccess else { return false }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(guest, [], &staticCode) == errSecSuccess, let staticGuest = staticCode else { return false }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticGuest, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess, let details = info as? [String: Any], details[kSecCodeInfoIdentifier as String] as? String == "ru.hl100.autoturn", let hash = details[kSecCodeInfoUnique as String] as? Data else { return false }
    return installation.cdhashes.contains(hash.map { String(format:"%02x", $0) }.joined())
}

if CommandLine.arguments.contains("--self-check") {
    let physical = PhysicalNetwork.read()
    print("AutoTurn helper protocol 1; primary=\(physical.interface ?? "none"); networkAvailable=\(physical.available); no networking changes performed")
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of:"--ipc-test-server"), index+2 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index+1], hash = CommandLine.arguments[index+2]
    guard path.utf8.count < 104, !FileManager.default.fileExists(atPath:path) else { exit(1) }
    let fd = socket(AF_UNIX,SOCK_STREAM,0); var address = IPC.unixAddress(path)
    let bound = withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard bound == 0, listen(fd,1) == 0 else { exit(1) }; chmod(path,0o600)
    let client = accept(fd,nil,nil)
    let allowed = client >= 0 && verifyClient(client,installation:Installation(uid:getuid(),cdhashes:[hash],engine:"unused"))
    if client >= 0 { try? IPC.write(Data((allowed ? "allowed\n" : "denied\n").utf8),fd:client); close(client) }
    close(fd); unlink(path); print(allowed ? "Signed app client authenticated" : "Unapproved client rejected"); exit(allowed ? 0 : 2)
}
guard getuid() == 0 else { fputs("Helper must run as the installed launchd service.\n", stderr); exit(1) }
do {
    let installation = try JSONDecoder().decode(Installation.self, from: Data(contentsOf: URL(fileURLWithPath: support + "/installation.json")))
    guard !installation.cdhashes.isEmpty, installation.cdhashes.allSatisfy({ $0.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil }), installation.engine == support + "/amneziawg-go" else { throw AppError.message("Invalid installation manifest") }
    try FileManager.default.createDirectory(atPath: IPC.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    unlink(IPC.socketPath)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { throw AppError.message("Socket failed") }
    var address = IPC.unixAddress(IPC.socketPath)
    let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard result == 0, listen(fd, 8) == 0 else { throw AppError.message("Listen failed") }
    chown(IPC.socketPath, installation.uid, 0); chmod(IPC.socketPath, 0o600)
    let service = Service(installation), slots = DispatchSemaphore(value: 8)
    while true {
        let client = accept(fd, nil, nil); if client < 0 { continue }
        if slots.wait(timeout: .now()) != .success { close(client); continue }
        DispatchQueue.global().async {
            defer { close(client); slots.signal() }
            var timeout = timeval(tv_sec: 20, tv_usec: 0); setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)); setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1; setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, 4)
            guard verifyClient(client, installation: installation), let data = try? IPC.readLine(fd: client), let request = try? JSONDecoder().decode(RPCRequest.self, from: data) else { return }
            let response = service.queue.sync { service.handle(request) }
            if var data = try? JSONEncoder().encode(response) { data.append(10); try? IPC.write(data, fd: client) }
        }
    }
} catch { fputs("AutoTurn helper startup failed.\n", stderr); exit(1) }
