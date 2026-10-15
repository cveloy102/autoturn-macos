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
