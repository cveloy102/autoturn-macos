import Foundation

enum ProfileSelectionDecision: Equatable {
    case wait, unchanged, confirm
    static func evaluate(target: String, current: String?, busy: Bool, pending: Bool, phase: Phase) -> Self {
        if busy || pending || phase == .connecting || phase == .recovering { return .wait }
        return target == current ? .unchanged : .confirm
    }
}
