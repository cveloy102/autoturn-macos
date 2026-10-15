import Foundation
import Network
import Darwin

struct DNSPacket {
    struct Answer { var name: String; var type: UInt16; var ttl: UInt32; var ip: String?; var cname: String? }
    let bytes: [UInt8]
    init(_ data: Data) { bytes = Array(data) }
    func word(_ i: Int) throws -> UInt16 { guard i >= 0, i+1 < bytes.count else { throw AppError.message("Обрезанный DNS-пакет") }; return UInt16(bytes[i])<<8 | UInt16(bytes[i+1]) }
    func name(_ offset: inout Int) throws -> String {
        var cursor = offset, seen = Set<Int>(), labels: [String] = [], consumed: Int?
        for _ in 0..<128 {
            guard cursor < bytes.count, seen.insert(cursor).inserted else { throw AppError.message("Некорректное DNS-имя") }
            let length = Int(bytes[cursor]); cursor += 1
            if length == 0 { offset = consumed ?? cursor; let value = labels.joined(separator:".").lowercased(); guard value.utf8.count <= 253 else { throw AppError.message("DNS-имя слишком длинное") }; return value }
            if length & 0xc0 == 0xc0 { guard cursor < bytes.count else { throw AppError.message("Обрезанный DNS-указатель") }; consumed = consumed ?? cursor+1; cursor = ((length & 0x3f)<<8) | Int(bytes[cursor]); continue }
            guard length <= 63, cursor+length <= bytes.count, let label = String(bytes:bytes[cursor..<cursor+length],encoding:.ascii), !label.contains(".") else { throw AppError.message("Некорректная DNS-метка") }
            labels.append(label); cursor += length
        }
        throw AppError.message("Слишком много DNS-указателей")
    }
    func question() throws -> (String, UInt16, Int) {
        guard bytes.count >= 12, try word(4) == 1, try word(2) & 0x7800 == 0 else { throw AppError.message("Неподдерживаемый DNS-запрос") }
        var offset = 12; let n = try name(&offset), type = try word(offset)
        guard try word(offset+2) == 1 else { throw AppError.message("Неподдерживаемый DNS-класс") }; return (n,type,offset+4)
    }
    func answers(matching query: Data) throws -> [Answer] {
        let q = DNSPacket(query), expected = try q.question(), actual = try question()
        guard try word(0) == q.word(0), try word(2) & 0x8000 != 0, expected.0 == actual.0, expected.1 == actual.1 else { throw AppError.message("Ответ DNS не соответствует запросу") }
        if try word(2) & 0x020f != 0 { return [] }
        var offset = actual.2, result: [Answer] = []
        let count = Int(try word(6)); guard count <= 512 else { throw AppError.message("Слишком много DNS-ответов") }
        for _ in 0..<count {
            let owner = try name(&offset), type = try word(offset), cls = try word(offset+2)
            let ttl = UInt32(try word(offset+4))<<16 | UInt32(try word(offset+6)); let length = Int(try word(offset+8)); offset += 10
            guard offset+length <= bytes.count else { throw AppError.message("Обрезанный DNS-ответ") }
            var ip: String?, cname: String?
            if cls == 1 && (type == 1 && length == 4 || type == 28 && length == 16) {
                var buffer = [CChar](repeating:0,count:Int(INET6_ADDRSTRLEN))
                let data = Array(bytes[offset..<offset+length]); data.withUnsafeBytes { raw in _ = inet_ntop(type == 1 ? AF_INET : AF_INET6,raw.baseAddress,&buffer,socklen_t(buffer.count)) }; ip = String(cString:buffer)
            }
            if cls == 1 && type == 5 { var at = offset; cname = try name(&at); guard at <= offset+length else { throw AppError.message("Некорректный CNAME") } }
            result.append(Answer(name:owner,type:type,ttl:ttl,ip:ip,cname:cname)); offset += length
        }
        var names: Set<String> = [expected.0]
        for _ in 0..<32 { let old = names.count; for a in result where names.contains(a.name) { if let target = a.cname { names.insert(target) } }; if old == names.count { break } }
        return result.filter { names.contains($0.name) }
    }
    static func failure(_ query: Data, code: UInt8 = 2) -> Data {
        guard let question = try? DNSPacket(query).question() else { return Data() }
        var result = Array(query.prefix(question.2)); result[2] = (result[2] & 1) | 0x80; result[3] = 0x80 | code
        for i in 6..<12 { result[i] = 0 }; return Data(result)
    }
}

// A loopback-only UDP/TCP resolver. Routes are installed before an answer is
// returned, so the first connection after resolution uses the chosen path.
final class RoutingDNSProxy {
    static let port: UInt16 = 5354
    let queue = DispatchQueue(label:"ru.hl100.autoturn.dns")
    let workers = DispatchQueue(label:"ru.hl100.autoturn.dns.workers",attributes:.concurrent)
    let slots = DispatchSemaphore(value:32)
    var listeners: [NWListener] = []
    var connections: [UUID:NWConnection] = [:]
    var upstream: String = "", iface: String = ""
    var answer: ((String,[DNSPacket.Answer]) throws -> Void)?
    var resolver: ((String,Data,Bool) throws -> Data)?
    var running = false
    func start(upstream: String, interface: String, answer: @escaping (String,[DNSPacket.Answer]) throws -> Void) throws {
        guard Profile.isIP(upstream), !upstream.contains(":"), !upstream.hasPrefix("127."), interface.range(of:"^(en|bridge|eth)[0-9]+$",options:.regularExpression) != nil else { throw AppError.message("Нет внешнего DNS для маршрутизации") }
        self.upstream = upstream; iface = interface; self.answer = answer
        for tcp in [false,true] {
            let parameters = tcp ? NWParameters.tcp : NWParameters.udp
            parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:Self.port)!)
            let listener = try NWListener(using:parameters)
            let ready = DispatchSemaphore(value:0); var error: Error?
            listener.stateUpdateHandler = { state in switch state { case .ready:ready.signal(); case .failed(let e):error = e; ready.signal(); default:break } }
            listener.newConnectionHandler = { [weak self] c in self?.accept(c,tcp:tcp) }
            listeners.append(listener); listener.start(queue:queue)
            guard ready.wait(timeout:.now()+3) == .success, error == nil else { stop(); throw error ?? AppError.message("Порт DNS 5354 занят") }
        }
        running = true
    }
    func stop() {
        for l in listeners { l.cancel() }; listeners = []; running = false
        queue.async { [weak self] in guard let self = self else { return }; for c in self.connections.values { c.cancel() }; self.connections.removeAll() }
    }
    private func accept(_ c: NWConnection, tcp: Bool) {
        guard connections.count < 64 else { c.cancel(); return }
        let id = UUID(); connections[id] = c; c.start(queue:queue)
        c.stateUpdateHandler = { [weak self] state in if case .failed = state { c.cancel(); self?.connections.removeValue(forKey:id) }; if case .cancelled = state { self?.connections.removeValue(forKey:id) } }
        queue.asyncAfter(deadline:.now()+10) { [weak self] in c.cancel(); self?.connections.removeValue(forKey:id) }
        if tcp { readTCP(c,id:id) } else { c.receiveMessage { [weak self] data,_,_,_ in guard let self = self, let data = data else { c.cancel(); return }; self.process(data,c:c,tcp:false,id:id) } }
    }
    private func readTCP(_ c: NWConnection, id: UUID) {
        exact(c,count:2,buffer:Data()) { [weak self] header in guard let self = self, let header = header else { c.cancel(); return }; let length = Int(header[0])<<8 | Int(header[1]); guard (12...65535).contains(length) else { c.cancel(); return }; self.exact(c,count:length,buffer:Data()) { data in guard let data = data else { c.cancel(); return }; self.process(data,c:c,tcp:true,id:id) } }
    }
    private func exact(_ c: NWConnection, count: Int, buffer: Data, done: @escaping (Data?) -> Void) {
        c.receive(minimumIncompleteLength:1,maximumLength:count-buffer.count) { [weak self] data,_,complete,error in
            var accumulated = buffer; if let data = data { accumulated.append(data) }; if accumulated.count == count { done(accumulated) } else if complete || error != nil { done(nil) } else { self?.exact(c,count:count,buffer:accumulated,done:done) }
        }
    }
    private func process(_ query: Data, c: NWConnection, tcp: Bool, id: UUID) {
        guard slots.wait(timeout:.now()) == .success else { c.cancel(); return }
        let upstream = self.upstream, iface = self.iface, callback = answer, resolver = self.resolver
        workers.async { [weak self] in
            guard let self = self else { return }; defer { self.slots.signal() }
            var response = DNSPacket.failure(query)
            do {
                let question = try DNSPacket(query).question()
                // Firefox's documented network canary disables automatic DoH;
                // manually configured DoH remains conservatively inside the VPN.
                if question.0 == "use-application-dns.net" { response = DNSPacket.failure(query,code:3) }
                else { let data = try resolver?(question.0,query,tcp) ?? Self.exchange(query,upstream:upstream,interface:iface,tcp:tcp); let records = try DNSPacket(data).answers(matching:query); try callback?(question.0,records); response = data }
            } catch { /* SERVFAIL rather than returning an unprotected answer. */ }
            self.queue.async {
                var payload = response
                if tcp { payload = Data([UInt8(response.count>>8),UInt8(response.count & 255)]) + response }
                c.send(content:payload,completion:.contentProcessed { _ in c.cancel(); self.connections.removeValue(forKey:id) })
            }
        }
    }
    static func exchange(_ query: Data, upstream: String, interface: String, tcp: Bool, port: UInt16 = 53) throws -> Data {
        let fd = socket(AF_INET,tcp ? SOCK_STREAM : SOCK_DGRAM,0); guard fd >= 0 else { throw AppError.message("DNS socket") }; defer { close(fd) }
        var timeout = timeval(tv_sec:2,tv_usec:0), noSignal: Int32 = 1, index = if_nametoindex(interface)
        guard index > 0, setsockopt(fd,IPPROTO_IP,25,&index,4) == 0 else { throw AppError.message("DNS interface binding") }
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size)); setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size)); setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,4)
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        upstream.withCString { _ = inet_pton(AF_INET,$0,&address.sin_addr) }
        guard withUnsafePointer(to:&address, { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }) == 0 else { throw AppError.message("DNS connection") }
        if tcp {
            try IPC.write(Data([UInt8(query.count>>8),UInt8(query.count & 255)])+query,fd:fd)
            func read(_ count: Int) throws -> Data { var data = Data(); var buffer = [UInt8](repeating:0,count:count); while data.count < count { let n = Darwin.read(fd,&buffer,count-data.count); guard n > 0 else { throw AppError.message("DNS timeout") }; data.append(contentsOf:buffer.prefix(n)) }; return data }
            let header = try read(2); return try read(Int(header[0])<<8 | Int(header[1]))
        }
        try IPC.write(query,fd:fd)
        var buffer = [UInt8](repeating:0,count:65535); let n = Darwin.read(fd,&buffer,buffer.count); guard n >= 12 else { throw AppError.message("DNS timeout") }
        let response = Data(buffer.prefix(n)); if buffer[2] & 2 != 0 { return try exchange(query,upstream:upstream,interface:interface,tcp:true,port:port) }; return response
    }
}

protocol DomainRouting: AnyObject {
    func configure(_ settings: RoutingSettings, physical: PhysicalNetwork) throws
    func stop() throws
    func recoverJournal() throws
    func setTunnel(_ interface: String?, dns: [String], supportsIPv6: Bool) throws
}
extension DomainRouting { func setTunnel(_ interface: String?, dns: [String], supportsIPv6: Bool) throws {} }
