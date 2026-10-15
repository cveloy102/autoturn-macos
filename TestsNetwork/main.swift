import Foundation

var checks = 0
func check(_ value:Bool,_ message:String) { guard value else { fatalError(message) }; checks += 1 }
let entered = DispatchSemaphore(value:0), release = DispatchSemaphore(value:0)
var count = 0
let observer = NetworkObserver(sampling:{
    check(!Thread.isMainThread,"Native network reads must not occupy the main thread")
    count += 1
    if count == 1 {
        entered.signal()
        guard release.wait(timeout:.now()+5) == .success else { fatalError("Blocked read timed out") }
    }
    return NetworkObservation(available:true,interface:"en0",ssid:count == 1 ? "home" : "external",gateway:"192.168.1.1",sampledAt:Date(),sampledContinuouslyAt:ContinuousTime.now())
},monitoring:false)
var results: [NetworkObservation] = []
observer.changed = { value in
    check(Thread.isMainThread,"Network callback must return on the main thread")
    results.append(value)
}
observer.report()
guard entered.wait(timeout:.now()+5) == .success else { fatalError("Read did not start") }
let began = ContinuousTime.now()
for _ in 0..<1000 { observer.report(); _ = observer.snapshot() }
check(ContinuousTime.now()-began < 0.2,"A slow native Wi-Fi read blocked UI snapshots")
check(!observer.snapshot().available,"Unfinished native read published a fabricated home")
release.signal()
let deadline = Date().addingTimeInterval(5)
while results.count < 2 && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
check(results.map(\.ssid) == ["home","external"],"Pending native reads were not coalesced into one newest read")
let timestamp = observer.snapshot().sampledContinuouslyAt
for _ in 0..<1000 { _ = observer.snapshot() }
check(observer.snapshot().sampledContinuouslyAt == timestamp,"UI snapshot reads renewed the trusted network lease")
let stale = NetworkObserver(sampling:{ NetworkObservation(available:true,interface:"en0",ssid:"home",gateway:"192.168.1.1",sampledAt:Date().addingTimeInterval(-60),sampledContinuouslyAt:ContinuousTime.now()-60) },monitoring:false)
var staleDelivered = false
stale.changed = { _ in staleDelivered = true }
stale.report()
while !staleDelivered && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
check(staleDelivered && stale.snapshot().ssid == nil,"A stale cached SSID was presented as fresh")
print("\(checks) network observer checks passed: background reads, nonblocking cache, 1000 coalesced reports and unchanged timestamps")
