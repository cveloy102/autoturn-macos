import AppKit

enum MenuAppearance: String, CaseIterable {
    case calm, instrument, card
    var title:String { switch self { case .calm:return "A · Спокойный"; case .instrument:return "B · Инструмент"; case .card:return "C · Карточка" } }
}
final class ClosureMenuItem: NSMenuItem {
    let callback: () -> Void
    init(_ title:String,action:@escaping () -> Void) {
        callback = action
        super.init(title:title,action:#selector(invoke),keyEquivalent:"")
        target = self
    }
    required init(coder:NSCoder) { fatalError() }
    @objc func invoke() { callback() }
}

enum ConsoleAppearance: String, CaseIterable {
    case console, workspace, contrast
    var title:String { switch self { case .console:return "1 · Консоль"; case .workspace:return "2 · Рабочее место"; case .contrast:return "3 · Контраст" } }
}
