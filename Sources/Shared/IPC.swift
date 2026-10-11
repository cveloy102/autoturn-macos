import Foundation
import Darwin

enum IPC {
    static let directory = "/var/run/autoturn"
    static let socketPath = directory + "/control.sock"
    static func connect(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AppError.message("Не удалось создать сокет") }
        var timeout = timeval(tv_sec: 40, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, 4)
        var address = unixAddress(path)
        let rc = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard rc == 0 else { close(fd); throw AppError.message("Служба AutoTurn недоступна") }
        return fd
    }
    static func unixAddress(_ path: String) -> sockaddr_un {
        precondition(path.utf8.count < 104)
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in bytes.initializeMemory(as: UInt8.self, repeating: 0); for (i, byte) in path.utf8.enumerated() { bytes[i] = byte } }
        return address
    }
    static func write(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < data.count { let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset); if n <= 0 { throw AppError.message("Не удалось передать команду службе") }; offset += n }
        }
    }
    static func readLine(fd: Int32, limit: Int = 1024 * 1024) throws -> Data {
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while result.count < limit {
            let n = Darwin.read(fd, &buffer, buffer.count)
            guard n > 0 else { throw AppError.message("Служба не ответила") }
            if let end = buffer.prefix(n).firstIndex(of: 10) { result.append(contentsOf: buffer[0..<end]); return result }
            result.append(contentsOf: buffer[0..<n])
        }
        throw AppError.message("Команда превышает допустимый размер")
    }
    static func request(_ request: RPCRequest) throws -> RPCResponse {
        let fd = try connect(socketPath); defer { close(fd) }
        var data = try JSONEncoder().encode(request); data.append(10); try write(data, fd: fd)
        return try JSONDecoder().decode(RPCResponse.self, from: readLine(fd: fd))
    }
    static func uapi(path: String, message: String) throws -> String {
        let fd = try connect(path); defer { close(fd) }; try write(Data(message.utf8), fd: fd)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 65536 { let n = Darwin.read(fd, &buffer, buffer.count); guard n > 0 else { break }; data.append(contentsOf: buffer.prefix(n)); if data.suffix(2) == Data([10,10]) { break } }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard text.contains("errno=0\n") else { throw AppError.message("AmneziaWG отклонил параметры конфигурации") }
        return text
    }
}
