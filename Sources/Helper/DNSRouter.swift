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
    // TTL offsets include authority/additional records; OPT's TTL-shaped flags
    // are deliberately excluded. Signed messages are not rewritten or cached.
    func cacheTTLFields() throws -> [(offset: Int, ttl: UInt32)] {
        var offset = try question().2
        let count = Int(try word(6)) + Int(try word(8)) + Int(try word(10))
        guard count <= 2048 else { throw AppError.message("Слишком много DNS-записей") }
        var result: [(Int,UInt32)] = []
        for _ in 0..<count {
            _ = try name(&offset)
            let type = try word(offset), length = Int(try word(offset+8))
            guard type != 250 && type != 24 else { return [] }
            let ttl = UInt32(try word(offset+4)) << 16 | UInt32(try word(offset+6))
            if type != 41 { result.append((offset+4,ttl)) }
            offset += 10 + length
            guard offset <= bytes.count else { throw AppError.message("Обрезанная DNS-запись") }
        }
        return result
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
    let listenPort: UInt16
    init(listenPort: UInt16 = RoutingDNSProxy.port) { self.listenPort = listenPort }
    let queue = DispatchQueue(label:"ru.hl100.autoturn.dns")
    let workers = DispatchQueue(label:"ru.hl100.autoturn.dns.workers",attributes:.concurrent)
    let slots = DispatchSemaphore(value:32)
    var listeners: [NWListener] = []
    var connections: [UUID:NWConnection] = [:]
    var upstream: String = "", iface: String = ""
    var answer: ((String,[DNSPacket.Answer]) throws -> Void)?
    var resolver: ((String,Data,Bool) throws -> Data)?
    private let runningLock = NSLock()
    private var isRunning = false
    var running: Bool {
        get { runningLock.lock(); defer { runningLock.unlock() }; return isRunning }
        set { runningLock.lock(); isRunning = newValue; runningLock.unlock() }
    }
    func start(upstream: String, interface: String, answer: @escaping (String,[DNSPacket.Answer]) throws -> Void) throws {
        guard resolver != nil || (Profile.isIP(upstream) && !upstream.contains(":") && !upstream.hasPrefix("127.") && interface.range(of:"^(en|bridge|eth)[0-9]+$",options:.regularExpression) != nil) else { throw AppError.message("Нет внешнего DNS для маршрутизации") }
        self.upstream = upstream; iface = interface; self.answer = answer
        for tcp in [false,true] {
            let parameters = tcp ? NWParameters.tcp : NWParameters.udp
            parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:listenPort)!)
            let listener = try NWListener(using:parameters)
            let ready = DispatchSemaphore(value:0); var error: Error?
            listener.stateUpdateHandler = { state in switch state { case .ready:ready.signal(); case .failed(let e):error = e; ready.signal(); default:break } }
            listener.newConnectionHandler = { [weak self] c in self?.accept(c,tcp:tcp) }
            listeners.append(listener); listener.start(queue:queue)
            guard ready.wait(timeout:.now()+3) == .success, error == nil else { stop(); throw error ?? AppError.message("Порт DNS \(listenPort) занят") }
        }
        running = true
    }
    func stop() {
        for l in listeners { l.cancel() }; listeners = []; running = false
        queue.async { [weak self] in guard let self = self else { return }; for c in self.connections.values { c.cancel() }; self.connections.removeAll() }
    }
    private func accept(_ c: NWConnection, tcp: Bool) {
        guard running, connections.count < 64 else { c.cancel(); return }
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

// Each request takes an immutable generation. A profile/network switch revokes
// replies from the old generation; protected names never use physical DNS.
final class SecureDNSManager {
    struct State {
        var routing = RoutingSettings()
        var dns = DNSSettings()
        var physical: String?
        var tunnel: String?
        var profileDNS: [String] = []
        var active = false
        var generation: UInt64 = 0
    }
    private let lock = NSLock()
    private var state = State()
    private var lastFailed = false
    private struct CacheEntry {
        var response: Data
        var created: TimeInterval
        var expires: TimeInterval
        var fields: [(offset: Int, ttl: UInt32)]
    }
    private var cache: [Data:CacheEntry] = [:]
    private let clock: () -> TimeInterval
    var message: String {
        lock.lock(); defer { lock.unlock() }
        if !state.active { return "DNS текущей сети · VPN выключен" }
        if lastFailed { return "Защищённый DNS недоступен" }
        if state.tunnel != nil { return "DNS: только через VPN" }
        return state.routing.mode == .rules ? "Резервный DoH напрямую · VPN-домены ждут VPN" : "DNS ожидает VPN"
    }
    private let proxy = RoutingDNSProxy(listenPort:53)
    private let networking: Bool
    let exchangeHTTPS: (Data,String,String,String) throws -> Data
    init(networking: Bool = true, clock: @escaping () -> TimeInterval = ContinuousTime.now, exchangeHTTPS: @escaping (Data,String,String,String) throws -> Data = SecureDNSManager.https) {
        self.networking = networking; self.clock = clock; self.exchangeHTTPS = exchangeHTTPS
    }
    func configure(routing: RoutingSettings, dns: DNSSettings, physical: String?) {
        lock.lock(); defer { lock.unlock() }
        if state.routing.mode != routing.mode || state.routing.rules != routing.rules || state.dns != dns || state.physical != physical {
            state.generation &+= 1; state.tunnel = nil; state.profileDNS = []; cache.removeAll(); lastFailed = false
        }
        state.routing = routing; state.dns = dns; state.physical = physical
    }
    func setTunnel(_ interface: String?, dns: [String] = []) {
        lock.lock(); defer { lock.unlock() }
        if state.tunnel != interface || state.profileDNS != dns { state.generation &+= 1; cache.removeAll(); lastFailed = false }
        state.tunnel = interface; state.profileDNS = dns
    }
    func start() throws {
        if networking && !proxy.running {
            proxy.resolver = { [weak self] _, query, tcp in
                guard let self = self else { throw AppError.message("DNS остановлен") }
                return try self.resolve(query,tcp:tcp)
            }
            try proxy.start(upstream:"127.0.0.1",interface:"lo0") { _,_ in }
        }
        lock.lock(); state.active = true; lock.unlock()
    }
    func stop() {
        lock.lock(); state.active = false; state.tunnel = nil; state.generation &+= 1; cache.removeAll(); lastFailed = false; lock.unlock()
        if networking { proxy.stop() }
    }
    func resolve(_ query: Data, tcp: Bool = false) throws -> Data {
        lock.lock(); let snapshot = state; lock.unlock()
        guard snapshot.active else { throw AppError.message("DNS не включён") }
        let name = try DNSPacket(query).question().0
        let protected = RoutingPolicy.destination(for:name,settings:snapshot.routing) == .vpn
        guard snapshot.tunnel != nil || !protected else { throw AppError.message("Этот домен ожидает VPN") }
        guard let interface = snapshot.tunnel ?? snapshot.physical else { throw AppError.message("Нет сети для DNS") }
        var cacheKey = query; cacheKey[0] = 0; cacheKey[1] = 0
        let time = clock()
        lock.lock()
        let cached = state.generation == snapshot.generation && state.active ? cache[cacheKey] : nil
        if cached != nil { lastFailed = false }
        lock.unlock()
        if let entry = cached, time < entry.expires {
            var response = entry.response
            response[0] = query[0]; response[1] = query[1]
            let elapsed = UInt32(max(0,min(Double(UInt32.max),time-entry.created)))
            for field in entry.fields {
                let ttl = field.ttl > elapsed ? field.ttl-elapsed : 0
                response[field.offset] = UInt8(ttl >> 24); response[field.offset+1] = UInt8((ttl >> 16) & 255)
                response[field.offset+2] = UInt8((ttl >> 8) & 255); response[field.offset+3] = UInt8(ttl & 255)
            }
            // Re-check after constructing the answer, including a concurrent switch.
            lock.lock(); let valid = state.active && state.generation == snapshot.generation; lock.unlock()
            guard valid else { throw AppError.message("DNS-кэш отменён после смены сети") }
            return response
        }
        var lastError: Error = AppError.message("Защищённый DNS недоступен")
        for provider in snapshot.dns.providers {
            lock.lock(); let stillValid = state.active && state.generation == snapshot.generation; lock.unlock()
            guard stillValid else { throw AppError.message("DNS-запрос отменён после смены сети") }
            do {
                let response: Data
                if provider == .profile {
                    guard snapshot.tunnel != nil else { continue }
                    var answer: Data?
                    for server in snapshot.profileDNS.filter({ !$0.contains(":") && $0 != "127.0.0.1" }).prefix(2) {
                        if let value = try? RoutingDNSProxy.exchange(query,upstream:server,interface:interface,tcp:tcp) { answer = value; break }
                    }
                    guard let value = answer else { continue }; response = value
                } else {
                    let endpoint = provider == .custom ? (snapshot.dns.customURL,snapshot.dns.customIP) : provider.endpoint!
                    response = try exchangeHTTPS(query,endpoint.0,endpoint.1,interface)
                }
                let records = try DNSPacket(response).answers(matching:query)
                let flags = try DNSPacket(response).word(2)
                guard flags & 0x0200 == 0, [0,3].contains(flags & 0xf) else { throw AppError.message("DNS вернул временную ошибку") }
                // A newly discovered protected alias must not be returned via fallback.
                if snapshot.tunnel == nil && records.contains(where: { RoutingPolicy.destination(for:$0.name,settings:snapshot.routing) == .vpn || $0.cname.map { RoutingPolicy.destination(for:$0,settings:snapshot.routing) == .vpn } == true }) {
                    throw AppError.message("DNS-псевдоним ожидает VPN")
                }
                lock.lock(); let valid = state.active && state.generation == snapshot.generation; lock.unlock()
                guard valid else { throw AppError.message("Сеть или VPN изменились во время DNS-запроса") }
                let fields = (try? DNSPacket(response).cacheTTLFields()) ?? []
                let lifetime = min(fields.map { $0.ttl }.min() ?? 0,60)
                lock.lock()
                if state.active && state.generation == snapshot.generation {
                    lastFailed = false
                    if flags & 0xf == 0, !records.isEmpty, lifetime > 0 {
                        if cache.count >= 512 {
                            cache = cache.filter { $0.value.expires > clock() }
                            if cache.count >= 512, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key { cache.removeValue(forKey:oldest) }
                        }
                        cache[cacheKey] = CacheEntry(response:response,created:clock(),expires:clock()+Double(lifetime),fields:fields)
                    }
                }
                lock.unlock()
                return response
            } catch { lastError = error }
        }
        lock.lock(); if state.generation == snapshot.generation { lastFailed = true }; lock.unlock()
        throw lastError
    }
    static func https(_ query: Data, _ url: String, _ ip: String, _ interface: String) throws -> Data {
        guard let host = URL(string:url)?.host, Profile.isIP(ip),
              interface.range(of:"^((en|bridge|eth|utun)[0-9]+|lo0)$",options:.regularExpression) != nil else { throw AppError.message("Некорректный путь DoH") }
        let encoded = query.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        // -q disables ~/.curlrc; pinned IP avoids all bootstrap DNS, HTTPS still
        // validates the URL hostname. No redirects, proxy or unbound retries.
        let response = try SystemCommand.run("/usr/bin/curl",["-q","--silent","--fail","--proxy","","--noproxy","*","--proto","=https","--interface","if!" + interface,"--resolve",host + ":443:" + ip,"--connect-timeout","2","--max-time","3","--max-filesize","65535","--header","Accept: application/dns-message",url + "?dns=" + encoded],timeout:4,outputLimit:65535)
        guard response.code == 0, response.data.count >= 12 else { throw AppError.message("Нет ответа от DoH-сервера") }
        return response.data
    }
    static func endpoint(_ host: String, physical: PhysicalNetwork, dns: DNSSettings) throws -> String {
        if Profile.isIP(host) { return try EndpointResolver.resolve(host,physical:physical) }
        guard Profile.validEndpointHost(host), let interface = physical.interface else { throw AppError.message("Не удалось найти VPN-сервер") }
        var query = Data([0x43,0x23,1,0,0,1,0,0,0,0,0,0])
        for label in host.trimmingCharacters(in:CharacterSet(charactersIn:".")).split(separator:".") { query.append(UInt8(label.utf8.count)); query.append(contentsOf:label.utf8) }
        query.append(contentsOf:[0,0,1,0,1])
        for endpoint in dns.endpoints {
            guard let reply = try? https(query,endpoint.url,endpoint.ip,interface),
                  let records = try? DNSPacket(reply).answers(matching:query),
                  let ip = records.compactMap({ $0.ip }).first(where: { !$0.contains(":") && !Profile.isRoutingFakeIP($0) }) else { continue }
            return ip
        }
        throw AppError.message("Защищённый DNS не смог найти VPN-сервер")
    }
}
