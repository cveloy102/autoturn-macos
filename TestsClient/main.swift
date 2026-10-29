import Foundation

let entered = DispatchSemaphore(value:0), release = DispatchSemaphore(value:0)
var received: [String] = []
var completions = 0
let client = ServiceClient(transport: { request in
    received.append(request.command == "network" ? request.network!.ssid! : request.command)
    if received.count == 1 {
        entered.signal()
        guard release.wait(timeout:.now()+5) == .success else { fatalError("Test transport timed out") }
    }
    return RPCResponse(ok:true,status:ServiceStatus(),error:nil)
})
func sample(_ value:String) -> RPCRequest {
    RPCRequest(command:"network",settings:nil,network:NetworkObservation(available:true,interface:"en0",ssid:value,gateway:"192.168.1.1",sampledAt:Date()))
}
client.send(sample("first")) { _ in completions += 1 }
guard entered.wait(timeout:.now()+5) == .success else { fatalError("Transport did not start") }
for index in 0..<1000 { client.send(sample("pending-\(index)")) { _ in completions += 1 } }
client.send(RPCRequest(command:"stop",settings:nil,network:nil)) { _ in completions += 1 }
release.signal()
let deadline = Date().addingTimeInterval(5)
while completions < 3 && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
guard completions == 3, received == ["first","stop","pending-999"] else { fatalError("Network backlog delayed Stop or dropped the newest sample: \(received)") }
print("Client regression passed: 1000 queued observations coalesced, Stop precedes newest observation")

let switchEntered = DispatchSemaphore(value:0), switchRelease = DispatchSemaphore(value:0)
var selections: [String] = [], switchCompletions = 0
let switchingClient = ServiceClient(transport: { request in
    selections.append(request.command == "configure" ? request.settings!.selectedID! : request.command)
    if selections.count == 1 { switchEntered.signal(); _ = switchRelease.wait(timeout:.now()+5) }
    return RPCResponse(ok:true,status:ServiceStatus(),error:nil)
})
func choose(_ name: String) {
    var settings = Settings(); settings.selectedID = name
    switchingClient.send(RPCRequest(command:"configure",settings:settings,network:nil)) { _ in switchCompletions += 1 }
}
choose("in-flight")
guard switchEntered.wait(timeout:.now()+5) == .success else { fatalError("No in-flight selection") }
for index in 0..<1000 { choose("profile-\(index)") }
switchingClient.send(RPCRequest(command:"stop",settings:nil,network:nil)) { _ in switchCompletions += 1 }
choose("after-stop")
switchRelease.signal()
let switchDeadline = Date().addingTimeInterval(5)
while switchCompletions < 1003 && Date() < switchDeadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
guard switchCompletions == 1003, selections == ["in-flight","profile-999","stop","after-stop"] else { fatalError("Profile storm was not collapsed or crossed Stop: \(selections)") }
print("Client profile-switch regression passed: 1000 clicks collapse to last choice; callbacks complete and Stop remains an ordering barrier")

var verificationAttempts = 0, scheduledRetries = 0, verified = false
ServiceVerification.wait(attempts:4,request:{ done in
 verificationAttempts += 1
 if verificationAttempts < 3 { done(.failure(AppError.message("launching"))) }
 else { done(.success(RPCResponse(ok:true,status:ServiceStatus(),error:nil))) }
},schedule:{ retry in scheduledRetries += 1; retry() },completion:{ result in
 if case .success(let reply) = result { verified = reply.ok }
})
guard verified && verificationAttempts == 3 && scheduledRetries == 2 else { fatalError("Installed service was rejected before launch finished") }
verificationAttempts = 0; verified = true
ServiceVerification.wait(attempts:3,request:{ done in
 verificationAttempts += 1; done(.success(RPCResponse(ok:false,status:ServiceStatus(),error:"not ready")))
},schedule:{ $0() },completion:{ result in if case .success(let reply) = result { verified = reply.ok } })
guard !verified && verificationAttempts == 3 else { fatalError("Unavailable service was accepted or retry bound ignored") }
verificationAttempts = 0
ServiceVerification.wait(request:{ done in verificationAttempts += 1; done(.success(RPCResponse(ok:true,status:ServiceStatus(),error:nil))) },schedule:{ _ in fatalError("Already-ready service was retried") },completion:{ _ in })
guard verificationAttempts == 1 else { fatalError("Already-ready service did not skip redundant installation waiting") }
print("Service readiness checks passed: already installed, delayed launch and bounded failed installation")
