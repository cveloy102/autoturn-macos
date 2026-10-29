import Foundation

// Installation is complete only when the signed application's authenticated
// status request succeeds, regardless of the installer's final exit status.
enum ServiceVerification {
    typealias Reply = Result<RPCResponse, Error>
    static func wait(attempts: Int = 20,
                     request: @escaping (@escaping (Reply) -> Void) -> Void,
                     schedule: @escaping (@escaping () -> Void) -> Void,
                     completion: @escaping (Reply) -> Void) {
        request { result in
            if case .success(let reply) = result, reply.ok { completion(result); return }
            guard attempts > 1 else { completion(result); return }
            schedule { wait(attempts:attempts-1,request:request,schedule:schedule,completion:completion) }
        }
    }
}
