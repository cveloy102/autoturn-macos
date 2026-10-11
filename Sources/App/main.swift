import AppKit
import Foundation
import CoreLocation
import UniformTypeIdentifiers
import UserNotifications
import CryptoKit

enum Palette {
    static let bg = NSColor(calibratedRed:16/255, green:16/255, blue:16/255, alpha:1)
    static let panel = NSColor(calibratedRed:24/255, green:24/255, blue:24/255, alpha:1)
    static let ink = NSColor(calibratedRed:232/255, green:228/255, blue:217/255, alpha:1)
    static let dim = NSColor(calibratedRed:170/255, green:167/255, blue:159/255, alpha:1)
    static let red = NSColor(calibratedRed:240/255, green:68/255, blue:62/255, alpha:1)
    static let green = NSColor(calibratedRed:140/255, green:219/255, blue:173/255, alpha:1)
    static let line = NSColor(calibratedWhite:0.21, alpha:1)
}
func label(_ text: String, size: CGFloat = 12, color: NSColor = Palette.ink) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString:text); field.font = NSFont.monospacedSystemFont(ofSize:size,weight:.regular); field.textColor = color; field.isSelectable = false; return field
}
func stack(_ views: [NSView] = [], vertical: Bool = true, spacing: CGFloat = 12) -> NSStackView {
    let s = NSStackView(views:views); s.orientation = vertical ? .vertical : .horizontal; s.alignment = vertical ? .leading : .centerY; s.spacing = spacing; s.distribution = .fill; s.translatesAutoresizingMaskIntoConstraints = false; s.setContentHuggingPriority(.init(1),for:.horizontal); s.setContentHuggingPriority(.init(1),for:.vertical); return s
}
func line() -> NSView { let view = NSView(); view.wantsLayer = true; view.layer?.backgroundColor = Palette.line.cgColor; view.heightAnchor.constraint(equalToConstant:1).isActive = true; return view }
func fill(_ view: NSView, color: NSColor = Palette.bg) { view.wantsLayer = true; view.layer?.backgroundColor = color.cgColor }
func pin(_ view: NSView, inside parent: NSView, inset: CGFloat = 24) { parent.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:inset),view.trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-inset),view.topAnchor.constraint(equalTo:parent.topAnchor,constant:inset),view.bottomAnchor.constraint(equalTo:parent.bottomAnchor,constant:-inset)]) }
final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    var primary: Bool
    var tabStyle = false
    var rowStyle = false
    var menuStyle = false
    var cornerRadius: CGFloat = 0
    var creamPrimary = false
    var menuIcon: String?
    var profileSubtitle: String?
    var profileState: String?
    var profileMark = ""
    init(_ text: String, primary: Bool = false, action: @escaping () -> Void) {
        self.primary = primary
        super.init(frame:.zero); title = text; actionBlock = action; target = self; self.action = #selector(invokeAction)
        isBordered = false; font = NSFont.monospacedSystemFont(ofSize:12,weight:.regular)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh,for:.horizontal)
        setContentCompressionResistancePriority(.required,for:.horizontal)
        setContentCompressionResistancePriority(.required,for:.vertical)
    }
    override var intrinsicContentSize: NSSize { NSSize(width:ceil((title as NSString).size(withAttributes:[.font:font!]).width)+28,height:menuStyle ? 30 : 38) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx:0.5,dy:0.5)
        if tabStyle {
            if primary { Palette.red.setFill(); NSRect(x:0,y:bounds.height-2,width:bounds.width,height:2).fill() }
        } else if rowStyle {
            (primary ? Palette.panel : Palette.bg).setFill(); rect.fill()
            if primary { Palette.red.setFill(); NSRect(x:0,y:0,width:2,height:bounds.height).fill() }
            Palette.line.setFill(); NSRect(x:0,y:bounds.height-1,width:bounds.width,height:1).fill()
        } else if menuStyle {
            Palette.bg.setFill(); rect.fill()
        } else {
            (primary ? (creamPrimary ? Palette.ink : Palette.red) : Palette.panel).setFill()
            let shape = NSBezierPath(roundedRect:rect,xRadius:cornerRadius,yRadius:cornerRadius); shape.fill()
            (primary ? (creamPrimary ? Palette.ink : Palette.red) : Palette.line).setStroke(); shape.stroke()
        }
        let textColor = !isEnabled ? Palette.dim : rowStyle || menuStyle ? Palette.ink : tabStyle ? (primary ? Palette.ink : Palette.dim) : primary ? Palette.bg : Palette.ink
        let attributes: [NSAttributedString.Key:Any] = [.font:font!, .foregroundColor:textColor]
        let size = (title as NSString).size(withAttributes:attributes)
        if let subtitle = profileSubtitle {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            let state = profileState ?? "резерв"
            let stateAttributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:11,weight:.regular),.foregroundColor:primary ? Palette.green : Palette.dim]
            let stateWidth = (state as NSString).size(withAttributes:stateAttributes).width
            (profileMark as NSString).draw(at:NSPoint(x:8,y:18),withAttributes:attributes)
            (title as NSString).draw(in:NSRect(x:32,y:9,width:max(20,bounds.width-48-stateWidth),height:18),withAttributes:[.font:font!,.foregroundColor:Palette.ink,.paragraphStyle:paragraph])
            (subtitle as NSString).draw(at:NSPoint(x:32,y:28),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:11,weight:.regular),.foregroundColor:Palette.dim])
            (state as NSString).draw(at:NSPoint(x:bounds.width-8-stateWidth,y:19),withAttributes:stateAttributes)
        } else {
            var x = rowStyle ? 12 : menuStyle ? 5 : (bounds.width-size.width)/2
            if let name = menuIcon, let image = NSImage(systemSymbolName:name,accessibilityDescription:nil) {
                let icon = NSImage(size:NSSize(width:14,height:14),flipped:false) { r in
                    image.draw(in:r); Palette.ink.setFill(); r.fill(using:.sourceAtop); return true
                }
                icon.draw(in:NSRect(x:5,y:(bounds.height-14)/2,width:14,height:14)); x = 28
            }
            (title as NSString).draw(at:NSPoint(x:x,y:(bounds.height-size.height)/2),withAttributes:attributes)
        }
        if window?.firstResponder === self { Palette.ink.setStroke(); NSBezierPath(rect:bounds.insetBy(dx:3,dy:3)).stroke() }
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func invokeAction() { actionBlock?() }
}
final class PixelMark: NSView {
    override func draw(_ dirtyRect:NSRect) {
        Palette.red.setFill()
        for row in 0..<3 { for column in 0..<3 where row != 1 || column != 1 {
            NSRect(x:CGFloat(column)*9,y:CGFloat(row)*9,width:7,height:7).fill()
        } }
    }
}
final class FlippedDocument: NSView { override var isFlipped: Bool { true } }
final class StackScroll: NSScrollView {
    let items: NSStackView
    init(_ items:NSStackView) {
        self.items = items
        super.init(frame:.zero)
        hasVerticalScroller = true; scrollsDynamically = true; usesPredominantAxisScrolling = true; drawsBackground = false; borderType = .noBorder
        let document = FlippedDocument(frame:.zero); documentView = document
        items.translatesAutoresizingMaskIntoConstraints = true; document.addSubview(items)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        guard let document = documentView else { return }
        let width = contentView.bounds.width
        items.frame.size.width = width
        items.layoutSubtreeIfNeeded()
        let height = max(1,ceil(items.fittingSize.height))
        document.frame = NSRect(x:0,y:0,width:width,height:max(contentView.bounds.height,height))
        items.frame = NSRect(x:0,y:0,width:width,height:height)
    }
}
func heading(_ text:String) -> NSTextField { let field = label(text,size:27); paintHeading(field,text); return field }
func paintHeading(_ field:NSTextField,_ text:String) {
    let attributed = NSMutableAttributedString(string:text,attributes:[.font:field.font!, .foregroundColor:Palette.ink])
    if text.hasSuffix("_") { attributed.addAttribute(.foregroundColor,value:Palette.red,range:NSRange(location:(text as NSString).length-1,length:1)) }
    field.attributedStringValue = attributed
}
final class ConsoleSurface: NSView {
    let header = NSView(), navigation = NSView(), content = NSView(), bottom = NSView()
    var sidebarAppearance = false
    var dropped: (([URL]) -> Void)?
    override var isFlipped: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        autoresizingMask = [.width,.height]
        for child in [header,navigation,content,bottom] { addSubview(child) }
        registerForDraggedTypes([.fileURL])
        fill(self)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        header.frame = NSRect(x:24,y:0,width:bounds.width-48,height:90)
        if sidebarAppearance {
            navigation.frame = NSRect(x:18,y:110,width:158,height:bounds.height-170)
            content.frame = NSRect(x:204,y:112,width:bounds.width-228,height:max(400,bounds.height-182))
        } else {
            navigation.frame = NSRect(x:24,y:90,width:bounds.width-48,height:48)
            content.frame = NSRect(x:24,y:162,width:bounds.width-48,height:max(400,bounds.height-232))
        }
        bottom.frame = NSRect(x:24,y:bounds.height-46,width:bounds.width-48,height:46)
    }
    override func draw(_ dirtyRect:NSRect) {
        Palette.line.setFill()
        for y in [CGFloat(90),bounds.height-46] { NSRect(x:0,y:y,width:bounds.width,height:1).fill() }
        if sidebarAppearance { NSRect(x:186,y:90,width:1,height:bounds.height-136).fill() }
        else { NSRect(x:0,y:138,width:bounds.width,height:1).fill() }
    }
    func files(_ sender:NSDraggingInfo) -> [URL] { files(sender.draggingPasteboard) }
    func files(_ pasteboard:NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []).filter { $0.pathExtension.lowercased() == "conf" }
    }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? [] : .copy }
    override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func prepareForDragOperation(_ sender:NSDraggingInfo) -> Bool { !files(sender).isEmpty }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool { let urls = files(sender); guard !urls.isEmpty else { return false }; dropped?(urls); return true }
}

final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var settings = Settings(), status = ServiceStatus()
    var serviceAvailable = false, busy = false, checkingConnection = false, checkingUpdate = false, polling = false
    var window: NSWindow!, body = NSView(), page = NSStackView(), footer: NSTextField!
    var tab = "Соединение"
    let routingDatabase = RoutingDatabase()
    var routingSelectedID: String?, routingQuery = "", routingFeedback = ""
    var routingBusy = false
    var routingTimer: Timer?
    var routingList: NSStackView?
    var routingSearch: NSSearchField?
    var routingStatusLabel: NSTextField?
    var testRoutingAppearance: RoutingAppearance?
    var routingAppearance: RoutingAppearance { testRoutingAppearance ?? RoutingAppearance(rawValue:UserDefaults.standard.string(forKey:"appearance.routing") ?? "") ?? .console }
    var testConsoleAppearance: ConsoleAppearance?
    var consoleAppearance: ConsoleAppearance { testConsoleAppearance ?? ConsoleAppearance(rawValue:UserDefaults.standard.string(forKey:"appearance.console") ?? "") ?? .console }
    var testMenuAppearance: MenuAppearance?
    var menuAppearance: MenuAppearance { testMenuAppearance ?? MenuAppearance(rawValue:UserDefaults.standard.string(forKey:"appearance.menu") ?? "") ?? .instrument }
    weak var pendingHomeField: NSTextField?
    var homeNetworkLabel:NSTextField?
    var navigation: NSStackView?
    var statusItem: NSStatusItem!, popover = StableMenuPanel()
    var localClickMonitor: Any?, globalClickMonitor: Any?, resignObserver: NSObjectProtocol?
    var renderedMenuRevision = "", observedRevision = "", renderedStatusRevision = ""
    var lastStatusRefresh = Date.distantPast
    let observeLiveNetwork = CommandLine.arguments.contains("--observe-live-network")
    let client = ServiceClient(), observer = NetworkObserver(), updater = Updater()
    let updateHistory = UpdateHistory()
    var updateTimer: Timer?
    var consoleProfileButtons: [(Profile,ActionButton)] = []
    var consoleEventsField:NSTextField?
    var connectionCheckField:NSTextField?
    var notifyingVersions = Set<String>()
    var timer: Timer?, connectionTitle: NSTextField?, connectionMessage: NSTextField?, connectionNetwork: NSTextField?, connectionProfile: NSTextField?, connectionGuard: NSTextField?
    let liveNetworkTest = CommandLine.arguments.contains("--live-network-test")
    var testExitCode: Int32 = 0
    var testTimer: Timer?
    let preview = CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--ui-self-check")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let icon = ApplicationArtwork.icon { NSApp.applicationIconImage = icon }
        if !preview {
            do { settings = try Storage.load() }
            catch { showError(error); NSApp.terminate(nil); return }
            do { try Storage.restoreLaunchAtLogin(&settings) } catch { showError(error) }
            updater.restoreCandidate()
        }
        buildWindow(); buildStatusItem()
        if CommandLine.arguments.contains("--ui-self-check") { checkInterface(); return }; if preview { renderPreview(); return }
        observer.changed = { [weak self] network in guard let self = self else { return }; self.updateHomeNetwork(network); guard self.serviceAvailable else { return }; self.client.send(RPCRequest(command:"network",settings:nil,network:network)) { self.accept($0,quiet:true) } }
        if settings.mode == .auto && !settings.homeSSIDs.isEmpty { observer.requestInitialPermission() }
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
        refresh()
        timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in
            guard let self = self else { return }
            if self.popover.isShown || self.observeLiveNetwork || Date().timeIntervalSince(self.lastStatusRefresh) >= 5 { self.refresh() }
        }
        RunLoop.main.add(timer!,forMode:.common)
        if !CommandLine.arguments.contains("--background") { openWindow() }
        if liveNetworkTest { beginLiveNetworkTest() }
        else { setupAutomaticUpdates(); setupRoutingUpdates() }
    }
    func buildWindow() {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:700),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "AutoTurn / Пульт"; window.contentMinSize = NSSize(width:700,height:700); window.delegate = self; window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named:.darkAqua); window.backgroundColor = Palette.bg
        let container = ConsoleSurface(frame:NSRect(x:0,y:0,width:760,height:700)); window.contentView = container
        container.dropped = { [weak self] files in self?.importProfiles(files) }
        let mark = NSImageView(frame:.zero); mark.image = ApplicationArtwork.icon; mark.imageScaling = .scaleProportionallyUpOrDown; mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant:33).isActive = true; mark.heightAnchor.constraint(equalToConstant:33).isActive = true
        let word = label("AUTOTURN_",size:23)
        let wordText = NSMutableAttributedString(string:"AUTOTURN",attributes:[.font:NSFont.monospacedSystemFont(ofSize:20,weight:.medium),.foregroundColor:Palette.ink])
        wordText.append(NSAttributedString(string:"_",attributes:[.font:NSFont.monospacedSystemFont(ofSize:20,weight:.medium),.foregroundColor:Palette.red])); word.attributedStringValue = wordText
        let identity = stack([word,label("HL100 / VPN CLIENT",size:11,color:Palette.dim)],spacing:4)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1),for:.horizontal)
        let edition = label("AMNEZIAWG 3.1\nINTEL + APPLE SILICON",size:11,color:Palette.dim); edition.alignment = .right
        let brand = stack([mark,identity,spacer,edition],vertical:false,spacing:14); pin(brand,inside:container.header,inset:0)
        navigation = stack(vertical:false,spacing:10); pin(navigation!,inside:container.navigation,inset:0)
        body = container.content
        let credit = stack([label("powered by",size:11,color:Palette.dim),label("LENCHA_",size:11,color:Palette.red)],vertical:false,spacing:7)
        footer = label("ПОДГОТОВКА",size:11,color:Palette.dim)
        let foot = stack([credit,NSView(),footer],vertical:false); pin(foot,inside:container.bottom,inset:0)
        buildPage(); window.center()
    }
    func buildNavigation() {
        guard let nav = navigation else { return }
        let sidebar = consoleAppearance == .workspace
        (window.contentView as? ConsoleSurface)?.sidebarAppearance = sidebar
        window.contentView?.needsLayout = true
        nav.orientation = sidebar ? .vertical : .horizontal
        nav.alignment = sidebar ? .leading : .centerY
        nav.arrangedSubviews.forEach { nav.removeArrangedSubview($0); $0.removeFromSuperview() }
        for name in ["Соединение","Профили","Маршруты","Домашняя сеть","События","Настройки"] {
            let button = ActionButton(name == "Профили" ? "Профили \(settings.profiles.count)" : name == "Домашняя сеть" ? "Дом" : name,primary:tab == name) { [weak self] in self?.selectTab(name) }
            button.tabStyle = true; if sidebar { button.widthAnchor.constraint(equalToConstant:158).isActive = true }; button.font = NSFont.monospacedSystemFont(ofSize:10,weight:.regular); nav.addArrangedSubview(button)
        }
        nav.addArrangedSubview(NSView())
        if let release = updater.candidate {
            let update = ActionButton("● Обновить",primary:true) { [weak self] in self?.activateUpdate() }
            update.toolTip = "Доступна версия " + release.version; nav.addArrangedSubview(update)
        }
    }
    func selectTab(_ name:String) {
        tab = name; buildPage()
        guard !preview, window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        body.alphaValue = 0.65
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            body.animator().alphaValue = 1
        }
    }
    func buildPage() {
        renderedStatusRevision = ""
        buildNavigation()
        body.subviews.forEach { $0.removeFromSuperview() }; page = stack(spacing:10); let scroll = StackScroll(page); pin(scroll,inside:body,inset:0)
        consoleProfileButtons = []; consoleEventsField = nil; connectionCheckField = nil
        connectionTitle = nil; connectionMessage = nil; connectionNetwork = nil; connectionProfile = nil; connectionGuard = nil
        switch tab {
        case "Маршруты": routingPage()
        case "Профили": profilesPage()
        case "Домашняя сеть": homePage()
        case "События": eventsPage()
        case "Настройки": settingsPage()
        default: connectionPage()
        }
        for view in page.arrangedSubviews where !(view is ActionButton) { view.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true }
        page.addArrangedSubview(NSView())
    }
    func connectionPage() {
        let appearance = consoleAppearance
        let left = stack(spacing:12), right = stack(spacing:10)
        let rightCard = NSView(); fill(rightCard,color:Palette.panel); rightCard.layer?.cornerRadius = 4; pin(right,inside:rightCard,inset:18)
        let panels = stack([left,rightCard],vertical:false,spacing:28); panels.alignment = .top
        let narrow = appearance == .workspace
        if !narrow { rightCard.widthAnchor.constraint(equalToConstant:258).isActive = true }
        left.setContentHuggingPriority(.init(1),for:.horizontal)
        let hero = stack(spacing:9)
        hero.addArrangedSubview(label("CONNECTION / AMNEZIAWG",size:10,color:appearance == .contrast ? Palette.panel : Palette.dim))
        connectionTitle = heading(titleForStatus()); connectionTitle?.font = NSFont.monospacedSystemFont(ofSize:32,weight:.medium); paintHeading(connectionTitle!,titleForStatus()); connectionMessage = label(connectionDescription(),size:11,color:Palette.dim)
        if appearance == .contrast {
            connectionTitle?.font = NSFont.systemFont(ofSize:29,weight:.semibold)
            connectionTitle?.textColor = Palette.bg; connectionMessage?.textColor = Palette.panel
        }
        hero.addArrangedSubview(connectionTitle!); hero.addArrangedSubview(connectionMessage!); let mode = modeButtons(); mode.widthAnchor.constraint(equalToConstant:276).isActive = true; hero.addArrangedSubview(mode)
        if appearance == .contrast {
            let card = NSView(); fill(card,color:Palette.ink); card.layer?.cornerRadius = 10
            pin(hero,inside:card,inset:18); left.addArrangedSubview(card); card.widthAnchor.constraint(equalTo:left.widthAnchor).isActive = true
        } else { left.addArrangedSubview(hero); hero.widthAnchor.constraint(equalTo:left.widthAnchor).isActive = true }
        connectionNetwork = label(status.network,size:11); connectionProfile = label(status.profileName ?? selectedProfile()?.name ?? "не выбран",size:11)
        connectionGuard = label(status.guardActive ? (settings.routing.mode == .rules ? "По правилам" : "Заблокирован") : "Разрешён",size:11,color:Palette.dim)
        connectionCheckField = label(verificationDescription(),size:11)
        let facts = stack(spacing:18)
        func cell(_ name:String,_ value:NSTextField) -> NSStackView {
            let cell = stack([label(name,size:9,color:Palette.dim),value],spacing:8)
            cell.setContentHuggingPriority(.init(1),for:.horizontal); return cell
        }
        for pair in [[cell("СЕТЬ",connectionNetwork!),cell("ПРОФИЛЬ",connectionProfile!)],[cell("ПРОВЕРКА",connectionCheckField!),cell("ПРЯМОЙ ДОСТУП",connectionGuard!)]] {
            let row = stack(pair,vertical:false,spacing:18); row.distribution = .fillEqually; row.alignment = .top
            facts.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:facts.widthAnchor).isActive = true
        }
        left.addArrangedSubview(facts); facts.widthAnchor.constraint(equalTo:left.widthAnchor).isActive = true
        let check = ActionButton(checkingConnection ? "Проверяем HTTPS…" : "Проверить связь",primary:true) { [weak self] in self?.command("check") }; check.isEnabled = serviceAvailable && !checkingConnection
        let next = ActionButton("Следующий профиль ↗") { [weak self] in self?.command("next") }; next.isEnabled = serviceAvailable && settings.profiles.count > 1
        check.font = NSFont.monospacedSystemFont(ofSize:11,weight:.regular); next.font = check.font
        let actions = narrow ? stack([check,next],spacing:8) : stack([check,next],vertical:false,spacing:8)
        left.addArrangedSubview(actions)
        if !serviceAvailable { left.addArrangedSubview(ActionButton("Установить VPN-службу…") { [weak self] in self?.installService() }) }
        left.addArrangedSubview(label("При сбое — резерв по порядку. Прямой доступ закрыт до восстановления.",size:10,color:Palette.dim))
        right.addArrangedSubview(label("ПРОФИЛИ / ПО ПОРЯДКУ",size:10,color:Palette.dim))
        for profile in settings.profiles.prefix(3) {
            let current = profile.id == (status.profileID ?? settings.selectedID)
            let button = ActionButton(String(profile.name.prefix(19)),primary:current) { [weak self] in self?.settings.selectedID = profile.id; self?.persistAndConfigure() }
            button.rowStyle = true; button.profileSubtitle = "AmneziaWG"; button.profileState = current ? "выбран" : "резерв"; button.profileMark = current ? "✓" : "·"; button.font = NSFont.monospacedSystemFont(ofSize:11,weight:.regular); button.toolTip = profile.name
            right.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant:50).isActive = true; button.widthAnchor.constraint(equalTo:right.widthAnchor).isActive = true
            consoleProfileButtons.append((profile,button))
        }
        let add = ActionButton("+ Добавить профиль",primary:settings.profiles.isEmpty) { [weak self] in self?.importProfile() }; right.addArrangedSubview(add)
        right.addArrangedSubview(line()); right.addArrangedSubview(label("ПОСЛЕДНИЕ СОБЫТИЯ",size:10,color:Palette.dim))
        consoleEventsField = label(status.events.suffix(2).joined(separator:"\n"),size:10,color:Palette.dim); right.addArrangedSubview(consoleEventsField!)
        if appearance == .contrast {
            left.removeArrangedSubview(left.arrangedSubviews.first!); let card = left.subviews.first { $0.subviews.contains(hero) }!
            left.constraints.filter { $0.firstItem === card || $0.secondItem === card }.forEach { $0.isActive = false }; card.removeFromSuperview(); page.addArrangedSubview(card); card.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true
            page.addArrangedSubview(panels)
        } else if narrow {
            page.addArrangedSubview(left)
            page.addArrangedSubview(rightCard)
        } else { page.addArrangedSubview(panels) }
    }
    func modeButtons() -> NSStackView {
        let modes = stack(vertical:false,spacing:0)
        for (mode,title) in [(Mode.auto,"Авто"),(.on,"Включить"),(.off,"Выключить")] { modes.addArrangedSubview(ActionButton(title,primary:settings.mode == mode) { [weak self] in self?.setMode(mode) }) }
        modes.distribution = .fillEqually
        return modes
    }
    func profilesPage() {
        page.addArrangedSubview(label("[ 02 / PROFILES ]",size:11,color:Palette.red)); page.addArrangedSubview(heading("Свои сети_")); page.addArrangedSubview(label("Проверяем по порядку. Одновременно работает один VPN.",color:Palette.dim))
        page.addArrangedSubview(ActionButton("+ Добавить профиль",primary:true) { [weak self] in self?.importProfile() })
        page.addArrangedSubview(label("Выбери .conf или перетащи файлы в окно. Можно добавить несколько.",size:11,color:Palette.dim))
        let list = stack(spacing:8)
        let scroll = StackScroll(list)
        if settings.profiles.isEmpty { list.addArrangedSubview(label("Профилей пока нет. Добавь конфигурацию AmneziaWG.",color:Palette.dim)) }
        for (index,profile) in settings.profiles.enumerated() {
            let row = stack(vertical:false,spacing:6)
            let active = profile.id == (status.profileID ?? settings.selectedID)
            let select = ActionButton("\(active ? "✓" : String(index+1))  \(String(profile.name.prefix(consoleAppearance == .workspace ? 14 : 28)))",primary:active) { [weak self] in self?.settings.selectedID = profile.id; self?.persistAndConfigure() }
            select.rowStyle = true; select.setContentHuggingPriority(.init(1),for:.horizontal); row.addArrangedSubview(select)
            let protocolLabel = label("AWG 3.1",size:11,color:Palette.dim); protocolLabel.widthAnchor.constraint(equalToConstant:68).isActive = true; row.addArrangedSubview(protocolLabel)
            row.addArrangedSubview(ActionButton("↑") { [weak self] in guard let self = self, index > 0 else { return }; self.settings.profiles.swapAt(index,index-1); self.persistAndConfigure() })
            row.addArrangedSubview(ActionButton("↓") { [weak self] in guard let self = self, index+1 < self.settings.profiles.count else { return }; self.settings.profiles.swapAt(index,index+1); self.persistAndConfigure() })
            row.addArrangedSubview(ActionButton("Удалить") { [weak self] in self?.removeProfile(profile) })
            list.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:list.widthAnchor).isActive = true
        }
        scroll.heightAnchor.constraint(equalToConstant:210).isActive = true; page.addArrangedSubview(scroll)
        page.addArrangedSubview(label("В первой версии весь интернет идёт через VPN. Правила AllowedIPs из файла заменяются полным туннелем; скрипты не выполняются.",size:11,color:Palette.dim))
    }
    func homePage() {
        page.addArrangedSubview(label("[ 03 / TRUSTED NETWORKS ]",size:11,color:Palette.red)); page.addArrangedSubview(heading("Дома — без VPN_")); page.addArrangedSubview(label("Маршруты уже настроены на роутере.",color:Palette.dim))
        let current = observer.snapshot()
        homeNetworkLabel = label("Текущий Wi-Fi: \(current.ssid ?? "название недоступно")"); page.addArrangedSubview(homeNetworkLabel!)
        page.addArrangedSubview(ActionButton("Открыть настройки геолокации…") { [weak self] in self?.observer.requestPermission() })
        let field = NSTextField(string:settings.homeSSIDs.joined(separator:"\n")); field.font = NSFont.monospacedSystemFont(ofSize:13,weight:.regular); field.textColor = Palette.ink; field.backgroundColor = Palette.panel; field.placeholderString = "Home_5G, Home_2G"; field.heightAnchor.constraint(equalToConstant:65).isActive = true; page.addArrangedSubview(field)
        let row = stack(vertical:false)
        row.addArrangedSubview(ActionButton("Добавить текущую") { [weak self, weak field] in
            guard let self = self, let field = field else { return }
            guard let ssid = self.observer.snapshot().ssid else {
                self.pendingHomeField = field; self.observer.requestPermission(); return
            }
            self.addHomeSSID(ssid,to:field)
        })
        row.addArrangedSubview(ActionButton("Сохранить сети",primary:true) { [weak self] in guard let self = self else { return }; let homes = field.stringValue.components(separatedBy:CharacterSet(charactersIn:",\n")).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }; guard homes.count <= 32, homes.allSatisfy({$0.utf8.count <= 32}) else { self.showError(AppError.message("Слишком длинное название сети")); return }; self.settings.homeSSIDs = Array(NSOrderedSet(array:homes)) as? [String] ?? homes; self.persistAndConfigure() })
        row.addArrangedSubview(NSView()); page.addArrangedSubview(row)
        let login = NSButton(checkboxWithTitle:"Запускать AutoTurn при входе",target:self,action:#selector(toggleLogin(_:))); login.state = settings.launchAtLogin ? .on : .off; page.addArrangedSubview(login)
        page.addArrangedSubview(label("В настройках геолокации включи службы геолокации и разреши AutoTurn. После разрешения текущая сеть появится здесь; нажми «Сохранить сети». Ethernet считаем внешней сетью.",size:11,color:Palette.dim))
    }
    func settingsPage() {
        page.addArrangedSubview(label("[ 05 / PREFERENCES ]",size:11,color:Palette.red))
        page.addArrangedSubview(heading("Настройки_"))
        page.addArrangedSubview(label("ОФОРМЛЕНИЕ ШТОРКИ",size:11,color:Palette.dim))
        let options = stack(vertical:false,spacing:8)
        for style in MenuAppearance.allCases {
            options.addArrangedSubview(ActionButton(style.title,primary:menuAppearance == style) { [weak self] in
                UserDefaults.standard.set(style.rawValue,forKey:"appearance.menu")
                self?.buildPage(); self?.refreshOpenMenu()
            })
        }
        page.addArrangedSubview(options)
        page.addArrangedSubview(label("Оформление меняется сразу. Режим VPN и профили сохраняются.",size:11,color:Palette.dim))
        page.addArrangedSubview(label("ОФОРМЛЕНИЕ ПУЛЬТА",size:11,color:Palette.dim))
        let consoles = stack(vertical:consoleAppearance == .workspace,spacing:8)
        for style in ConsoleAppearance.allCases {
            consoles.addArrangedSubview(ActionButton(style.title,primary:consoleAppearance == style) { [weak self] in
                UserDefaults.standard.set(style.rawValue,forKey:"appearance.console"); self?.buildPage()
            })
        }
        page.addArrangedSubview(consoles)
        page.addArrangedSubview(label("ОФОРМЛЕНИЕ МАРШРУТОВ",size:11,color:Palette.dim))
        let routeThemes = stack(vertical:consoleAppearance == .workspace,spacing:8)
        for style in RoutingAppearance.allCases {
            routeThemes.addArrangedSubview(ActionButton(style.title,primary:routingAppearance == style) { [weak self] in UserDefaults.standard.set(style.rawValue,forKey:"appearance.routing"); self?.buildPage() })
        }
        page.addArrangedSubview(routeThemes)
        page.addArrangedSubview(line())
        page.addArrangedSubview(label("ОБНОВЛЕНИЯ / GITHUB",size:11,color:Palette.dim))
        page.addArrangedSubview(label("Проверяем раз в час, пока AutoTurn запущен. После сна — при пробуждении. Уведомление приходит только для новой версии.",color:Palette.dim))
        page.addArrangedSubview(ActionButton(updater.candidate.map { "● Обновить до \($0.version)" } ?? "Проверить обновления",primary:updater.candidate != nil) { [weak self] in self?.activateUpdate() })
        page.addArrangedSubview(ActionButton("Настройки уведомлений macOS…") {
            NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        })
        let login = NSButton(checkboxWithTitle:"Запускать AutoTurn при входе",target:self,action:#selector(toggleLogin(_:)))
        login.state = settings.launchAtLogin ? .on : .off; page.addArrangedSubview(login)
    }
    func activateUpdate() {
        guard !checkingUpdate else { return }
        popover.performClose(nil)
        if let release = updater.candidate { presentUpdate(release) } else { checkUpdates() }
    }
    func showMoreMenu() {
        let menu = NSMenu()
        func add(_ title:String,_ action:@escaping () -> Void) { menu.addItem(ClosureMenuItem(title,action:action)) }
        add("Маршруты…") { [weak self] in self?.tab = "Маршруты"; self?.openWindow() }
        add("Настройки…") { [weak self] in self?.tab = "Настройки"; self?.openWindow() }
        add("Домашние сети…") { [weak self] in self?.tab = "Домашняя сеть"; self?.openWindow() }
        add("+ Добавить профиль…") { [weak self] in self?.openWindow(); self?.importProfile() }
        add("Диагностика…") { [weak self] in self?.tab = "События"; self?.openWindow() }
        add("Проверить обновления…") { [weak self] in self?.checkUpdates() }
        menu.addItem(.separator())
        add("Завершить…") { [weak self] in self?.quit() }
        if let view = popover.contentViewController?.view { menu.popUp(positioning:nil,at:NSPoint(x:170,y:view.bounds.height-58),in:view) }
    }
    func addHomeSSID(_ ssid:String,to field:NSTextField) {
        var homes = field.stringValue.components(separatedBy:CharacterSet(charactersIn:",\n")).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }
        if !homes.contains(ssid) { homes.append(ssid) }
        field.stringValue = homes.joined(separator:", ")
    }
    func updateHomeNetwork(_ network:NetworkObservation) {
        guard tab == "Домашняя сеть" else { pendingHomeField = nil; return }
        homeNetworkLabel?.stringValue = "Текущий Wi-Fi: \(network.ssid ?? "название недоступно")"
        if let field = pendingHomeField, field.window === window, let ssid = network.ssid {
            addHomeSSID(ssid,to:field); pendingHomeField = nil
        }
    }
    func eventsPage() {
        page.addArrangedSubview(label("[ 04 / EVENT LOG ]",size:11,color:Palette.red))
        page.addArrangedSubview(heading("Что произошло_"))
        let log = stack(spacing:12)
        for event in status.events.isEmpty ? ["Событий пока нет."] : status.events {
            let entry = label(event,size:11,color:Palette.dim); entry.isSelectable = true; log.addArrangedSubview(entry); entry.widthAnchor.constraint(equalTo:log.widthAnchor).isActive = true; log.addArrangedSubview(line())
        }
        let scroll = StackScroll(log); scroll.heightAnchor.constraint(equalToConstant:260).isActive = true; page.addArrangedSubview(scroll)
        page.addArrangedSubview(ActionButton("Экспорт диагностики") { [weak self] in self?.exportDiagnostics() })
    }
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.unknown.image; statusItem.button?.title = ""
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.toolTip = "AutoTurn · powered by LENCHA"
        popover.onClose = { [weak self] in self?.stopPopoverMonitoring() }
    }
    func menuView() -> NSView {
        let style = menuAppearance, width:CGFloat = 332, inset:CGFloat = 20, inner:CGFloat = 292
        let view = FlippedDocument(frame:NSRect(x:0,y:0,width:width,height:600)); fill(view)
        view.layer?.cornerRadius = style == .instrument ? 4 : 14
        var y:CGFloat = 18
        func place(_ child:NSView,_ height:CGFloat,_ x:CGFloat = 20,_ w:CGFloat = 292) {
            child.translatesAutoresizingMaskIntoConstraints = true
            child.frame = NSRect(x:x,y:y,width:w,height:height); view.addSubview(child)
        }
        func rule() { place(line(),1); y += 16 }
        func row(_ title:String,_ height:CGFloat = 34,_ action:@escaping () -> Void) {
            let button = ActionButton(title,action:action); button.menuStyle = true; place(button,height); y += height
        }
        let brand = label("AUTOTURN_",size:15); paintHeading(brand,"AUTOTURN_"); place(brand,22,20,220)
        place(label("HL100",size:10,color:Palette.dim),18,268,44); y += 38
        if style == .instrument { rule() }
        let stateTitle:String
        if needsLocationPermission() { stateTitle = "Нужен доступ к Wi-Fi" }
        else { switch status.phase {
            case .home: stateTitle = "Дома"
            case .connected: stateTitle = "Под защитой"
            case .connecting: stateTitle = "Проверяем связь"
            case .recovering: stateTitle = "Восстановление"
            case .waiting: stateTitle = "Ждём сеть"
            case .off: stateTitle = "Выключено"
            case .setup: stateTitle = "Добавь профиль"
            case .error: stateTitle = "Нужно внимание"
        } }
        let cardTop = y
        if style == .card {
            let card = NSView(); fill(card,color:Palette.ink); card.layer?.cornerRadius = 10
            place(card,110); y += 12
        } else if style == .instrument {
            let accent = NSView(); fill(accent,color:Palette.red); place(accent,83,20,3)
        }
        let heroX:CGFloat = style == .instrument ? 35 : style == .card ? 32 : 20
        let heroWidth = width-heroX-32
        let title = label(stateTitle + (style == .instrument ? "_" : ""),size:style == .card ? 26 : 23,color:style == .card ? Palette.bg : Palette.ink)
        if style == .instrument { paintHeading(title,title.stringValue) }
        else { title.font = NSFont.systemFont(ofSize:26,weight:.semibold) }
        place(title,32,heroX,heroWidth); y += 38
        let network = label(needsLocationPermission() ? "Название Wi-Fi недоступно" : status.network,size:11,color:style == .card ? Palette.panel : Palette.dim)
        network.maximumNumberOfLines = 1; network.lineBreakMode = .byTruncatingTail
        place(network,18,heroX,heroWidth); y += 24
        let detail = label(status.phase == .home ? "Интернет через роутер" : status.phase == .connected ? "Интернет через VPN" : status.phase == .off ? "Автоматика приостановлена" : status.phase == .recovering ? "Прямой доступ закрыт" : "Состояние соединения",size:11,color:style == .card ? Palette.panel : status.phase == .connected ? Palette.green : Palette.dim)
        place(detail,18,heroX,heroWidth); y = max(y+34,cardTop+(style == .card ? 124 : 0))
        for (index,mode) in [Mode.auto,.on,.off].enumerated() {
            let button = ActionButton(["Авто","Вкл.","Выкл."][index],primary:settings.mode == mode) { [weak self] in self?.setMode(mode) }
            button.cornerRadius = style == .instrument ? 2 : 6; button.creamPrimary = style != .instrument
            place(button,34,inset+CGFloat(index)*inner/3,inner/3)
        }
        y += 52
        if style == .instrument {
            rule()
            let check = status.verifiedAt.map { date -> String in let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"; return "HTTPS · " + formatter.string(from:date) } ?? (status.phase == .home ? "VPN не требуется" : "Не подтверждена")
            place(label("Проверка",size:10,color:Palette.dim),18,20,92); place(label(check,size:10),18,115,197); y += 27
            place(label("Прямой доступ",size:10,color:Palette.dim),18,20,118)
            place(label(status.guardActive ? "закрыт" : "разрешён",size:10),18,180,132); y += 31; rule()
        }
        place(label("ПРОФИЛИ / \(String(format:"%02d",settings.profiles.count))",size:10,color:Palette.dim),16); y += 22
        let currentID = status.profileID ?? settings.selectedID ?? settings.profiles.first?.id
        let shown = style == .card ? settings.profiles.filter { $0.id == currentID } : Array(settings.profiles.prefix(3))
        for profile in shown {
            let index = settings.profiles.firstIndex { $0.id == profile.id } ?? 0
            let selected = profile.id == currentID
            let button = ActionButton(profile.name,primary:selected) { [weak self] in self?.settings.selectedID = profile.id; self?.persistAndConfigure() }
            button.rowStyle = true; button.profileSubtitle = "AmneziaWG"; button.profileMark = selected ? "✓" : String(format:"%02d",index+1)
            button.profileState = selected ? (status.phase == .connected ? "активен" : status.phase == .home || status.phase == .off ? "готов" : "проверка") : "резерв"
            button.toolTip = profile.name; place(button,50); y += 50
        }
        if settings.profiles.isEmpty { row("+ Добавить профиль…") { [weak self] in self?.importProfile() } }
        else if style == .card || settings.profiles.count > 3 { row("Все профили…") { [weak self] in self?.tab = "Профили"; self?.openWindow() } }
        y += 12
        let check = ActionButton(checkingConnection ? "Проверяем HTTPS…" : "Проверить связь",primary:style == .calm) { [weak self] in self?.command("check") }
        check.cornerRadius = style == .instrument ? 2 : 7; check.isEnabled = serviceAvailable && !checkingConnection; place(check,36,20,246)
        let next = ActionButton("→") { [weak self] in self?.command("next") }; next.toolTip = "Следующий профиль"; next.isEnabled = serviceAvailable && settings.profiles.count > 1; next.cornerRadius = check.cornerRadius; place(next,36,274,38); y += 50
        if needsLocationPermission() { row("Разрешить определение Wi-Fi…") { [weak self] in self?.observer.requestPermission() } }
        if let release = updater.candidate {
            let update = ActionButton("● Обновить до \(release.version)",primary:true) { [weak self] in self?.activateUpdate() }
            update.cornerRadius = check.cornerRadius; place(update,36); y += 48
        }
        rule()
        let console = ActionButton("Открыть пульт ↗") { [weak self] in self?.openWindow() }; console.menuStyle = true; place(console,28,20,214)
        let more = ActionButton("Ещё ···") { [weak self] in self?.showMoreMenu() }; more.menuStyle = true; place(more,28,240,72); y += 40
        let credit = label("powered by LENCHA_",size:10,color:Palette.dim)
        let signature = NSMutableAttributedString(string:credit.stringValue,attributes:[.font:credit.font!,.foregroundColor:Palette.dim])
        signature.addAttribute(.foregroundColor,value:Palette.red,range:(credit.stringValue as NSString).range(of:"LENCHA_")); credit.attributedStringValue = signature
        place(credit,18); y += 30
        view.frame.size.height = y; return view
    }
    func menuRevision() -> String {
        ([settings.mode.rawValue,settings.routing.mode.rawValue,status.phase.rawValue,connectionDescription(),status.network,status.profileID ?? "",settings.selectedID ?? "",String(status.guardActive),String(serviceAvailable),String(checkingConnection),String(updater.candidate?.build ?? 0),menuAppearance.rawValue,status.verifiedAt.map { String($0.timeIntervalSince1970) } ?? ""] + settings.profiles.map { $0.id + $0.name }).joined(separator:"\u{1f}")
    }
    func refreshOpenMenu() {
        guard popover.isShown, renderedMenuRevision != menuRevision() else { return }
        let updated = menuView()
        popover.contentViewController?.view = updated
        popover.contentSize = updated.frame.size
        renderedMenuRevision = menuRevision()
    }
    func handlePopoverClick(_ event:NSEvent) {
        guard popover.isShown else { return }
        if event.window === popover.contentViewController?.view.window || event.window === statusItem.button?.window { return }
        popover.performClose(nil)
    }
    func stopPopoverMonitoring() {
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor); localClickMonitor = nil }
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor); globalClickMonitor = nil }
        if let observer = resignObserver { NotificationCenter.default.removeObserver(observer); resignObserver = nil }
    }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        let controller = NSViewController(); controller.view = menuView()
        popover.contentViewController = controller; popover.contentSize = controller.view.frame.size
        renderedMenuRevision = menuRevision()
        guard let button = statusItem.button else { return }
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        controller.view.window?.makeKey()
        stopPopoverMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown,.rightMouseDown,.otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching:clicks) { [weak self] event in self?.handlePopoverClick(event); return event }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching:clicks) { [weak self] _ in self?.popover.performClose(nil) }
        resignObserver = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:NSApp,queue:.main) { [weak self] _ in self?.popover.performClose(nil) }
        if !preview { refresh() }
    }
    func openWindow() { popover.performClose(nil); buildPage(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    func needsLocationPermission() -> Bool {
        guard !preview, settings.mode == .auto, !settings.homeSSIDs.isEmpty, observer.locationPermissionMissing else { return false }
        let network = observer.snapshot()
        return network.available && network.ssid == nil
    }
    func connectionDescription() -> String {
        needsLocationPermission() ? "Разреши геолокацию для определения домашнего Wi-Fi. Пока сеть не определена, VPN остаётся включён." : status.message
    }
    func titleForStatus() -> String { switch status.phase { case .setup:return "Начнём с профиля_"; case .home:return "Ты дома_"; case .connecting:return "Проверяем связь_"; case .connected:return "Под защитой_"; case .waiting:return "Ждём сеть_"; case .recovering:return "Восстанавливаем_"; case .off:return "Выключено вручную_"; case .error:return "Нужно внимание_" } }
    func verificationDescription() -> String {
        if checkingConnection { return "Проверяем HTTPS через VPN…" }
        if status.phase == .home { return "VPN не требуется" }
        if let date = status.verifiedAt {
            let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
            return "HTTPS · " + formatter.string(from:date)
        }
        return "Не подтверждена"
    }
    func guardDescription() -> String { if !serviceAvailable { return FileManager.default.fileExists(atPath:"/Library/LaunchDaemons/ru.hl100.autoturn.helper.plist") ? "Состояние службы и блокировки не подтверждено" : "VPN-служба ещё не установлена; интернет не изменён" }; return status.guardActive && settings.routing.mode == .rules ? "Прямой доступ по правилам; выбранные сервисы защищены" : status.guardActive ? "Прямой трафик заблокирован" : "Блокировка прямого доступа выключена" }
    func selectedProfile() -> Profile? { settings.profiles.first { $0.id == settings.selectedID } ?? settings.profiles.first }
    func updateStatus() {
        let revision = menuRevision() + consoleAppearance.rawValue + (status.profileName ?? "") + status.events.suffix(2).joined(separator:"\n")
        guard renderedStatusRevision != revision else { return }
        renderedStatusRevision = revision
        if let title = connectionTitle { paintHeading(title,titleForStatus()); if consoleAppearance == .contrast { title.textColor = Palette.bg; title.attributedStringValue = NSAttributedString(string:titleForStatus(),attributes:[.font:title.font!,.foregroundColor:Palette.bg]) } }; connectionMessage?.stringValue = connectionDescription(); connectionNetwork?.stringValue = status.network; connectionProfile?.stringValue = status.profileName ?? selectedProfile()?.name ?? "не выбран"; connectionGuard?.stringValue = status.guardActive ? (settings.routing.mode == .rules ? "По правилам" : "Заблокирован") : "Разрешён"; connectionCheckField?.stringValue = verificationDescription(); connectionGuard?.textColor = status.guardActive ? Palette.green : Palette.dim
        for (profile,button) in consoleProfileButtons {
            button.primary = profile.id == (status.profileID ?? settings.selectedID)
            button.profileState = button.primary ? (status.phase == .connected ? "активен" : status.phase == .home || status.phase == .off ? "готов" : "проверка") : "резерв"
            button.needsDisplay = true
        }
        consoleEventsField?.stringValue = status.events.suffix(2).joined(separator:"\n")
        let modeName = settings.mode == .auto ? "АВТО" : settings.mode == .on ? "ВРУЧНУЮ" : "ВЫКЛЮЧЕНО"
        let phaseNames: [Phase:String] = [.setup:"НАСТРОЙКА",.home:"ДОМА",.connecting:"ПОДКЛЮЧЕНИЕ",.connected:"ПРОВЕРЕНО",.waiting:"ОЖИДАНИЕ",.recovering:"РЕЗЕРВ",.off:"ПАУЗА",.error:"ОШИБКА"]
        footer?.stringValue = "\(modeName) / \(phaseNames[status.phase] ?? "")"
        let icon = StatusIcon.state(status.phase,missingLocation:needsLocationPermission()).image
        if statusItem.button?.image !== icon { statusItem.button?.image = icon }
        statusItem.button?.title = ""; statusItem.button?.toolTip = "AutoTurn · \(connectionDescription())"
        refreshOpenMenu()
        if observeLiveNetwork && observedRevision != menuRevision() {
            observedRevision = menuRevision()
            let network = observer.snapshot()
            let home = network.ssid.map { settings.homeSSIDs.contains($0) } ?? false
            print("OBSERVE \(ISO8601DateFormatter().string(from:Date())) mode=\(settings.mode.rawValue) phase=\(status.phase.rawValue) guard=\(status.guardActive) physicalAvailable=\(network.available) ssidKnown=\(network.ssid != nil) home=\(home) menuOpen=\(popover.isShown)")
            fflush(stdout)
        }
    }
    func refresh() { guard !busy && !polling else { return }; lastStatusRefresh = Date(); polling = true; client.send(RPCRequest(command:"status",settings:nil,network:nil)) { [weak self] result in guard let self = self else { return }; self.polling = false; let was = self.serviceAvailable; self.accept(result,quiet:true); if self.serviceAvailable && !was && !self.settings.profiles.isEmpty { self.persistAndConfigure() }; if was != self.serviceAvailable { self.buildPage() } } }
    func accept(_ result: Result<RPCResponse,Error>, quiet: Bool = false) {
        switch result { case .success(let response):serviceAvailable = true; status = response.status; if !response.ok && !quiet { showError(AppError.message(response.error ?? "Ошибка службы")) }; case .failure(let error):serviceAvailable = false; status.phase = .setup; status.message = FileManager.default.fileExists(atPath:"/Library/LaunchDaemons/ru.hl100.autoturn.helper.plist") ? "Служба недоступна. Её состояние и блокировку сейчас подтвердить нельзя." : "Импортируй AmneziaWG .conf и установи VPN-службу"; if !quiet { showError(error) } }
        updateStatus()
    }
    func command(_ command: String) {
        guard !busy else { return }
        guard serviceAvailable else { showError(AppError.message("Сначала импортируй профиль и установи VPN-службу")); return }
        if command == "check" {
            if status.phase == .home || status.phase == .off {
                info(status.phase == .home ? "Ты в домашней сети: VPN не используется. Эта кнопка проверяет доступ в интернет через VPN; домашнее подключение она сейчас не проверяет." : "VPN выключен вручную. Эта кнопка проверяет доступ в интернет через VPN; прямое подключение она сейчас не проверяет.")
                return
            }
            checkingConnection = true
        }
        busy = true
        if command == "check" { buildPage(); refreshOpenMenu() }
        let startedAt = Date()
        client.send(RPCRequest(command:command,settings:nil,network:nil)) { [weak self] result in
            guard let self = self else { return }
            self.busy = false; self.checkingConnection = false; self.accept(result)
            if command == "check" {
                self.buildPage(); self.refreshOpenMenu()
                if case .success(let response) = result, response.ok {
                    if response.status.phase == .connected, let verified = response.status.verifiedAt, verified >= startedAt {
                        self.info("Доступ в интернет через VPN подтверждён HTTPS-запросом. " + self.verificationDescription())
                    } else {
                        self.info("Проверка завершена: " + response.status.message)
                    }
                }
            }
        }
    }
    func persistAndConfigure() {
        do { try Storage.save(settings) } catch { showError(error); return }
        buildPage()
        guard serviceAvailable else { return }; busy = true
        client.send(RPCRequest(command:"configure",settings:settings,network:observer.snapshot())) { [weak self] result in self?.busy = false; self?.accept(result); self?.observer.report() }
    }
    func setMode(_ mode: Mode) {
        if mode == .off && !liveNetworkTest && !confirm("Отключить VPN?",detail:"Вне дома интернет сможет идти напрямую. Автоматика будет выключена до возврата в Авто.") { return }
        guard mode == .off || !settings.profiles.isEmpty else { tab = "Профили"; openWindow(); return }
        settings.mode = mode
        if mode == .auto && !settings.homeSSIDs.isEmpty { observer.requestInitialPermission() }
        buildPage(); refreshOpenMenu()
        let snapshot = settings
        // Apply the user's network action before Keychain persistence. In particular,
        // Off must not depend on reading/validating profiles or an unlocked Keychain.
        busy = true
        let request = mode == .off ? RPCRequest(command:"stop",settings:nil,network:nil) : RPCRequest(command:"configure",settings:snapshot,network:observer.snapshot())
        client.send(request) { [weak self] result in
            guard let self = self else { return }
            self.accept(result); self.observer.report()
            do { try Storage.save(self.settings) } catch { self.info("Режим применён к службе, но настройки не сохранены: " + error.localizedDescription) }
            self.busy = false
        }
    }
    func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension:"conf") ?? .plainText]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.title = "Добавить профиль AmneziaWG"; panel.prompt = "Добавить"
        guard panel.runModal() == .OK else { return }; importProfiles(panel.urls)
    }
    func importProfiles(_ files:[URL]) {
        guard !busy, !files.isEmpty else { return }
        guard files.allSatisfy({ $0.isFileURL && $0.pathExtension.lowercased() == "conf" }) else { showError(AppError.message("Нужен файл AmneziaWG с расширением .conf")); return }
        busy = true
        DispatchQueue.global().async { let result = Result { try files.map { file -> Profile in var profile = try Profile.parse(String(contentsOf:file,encoding:.utf8),name:file.deletingPathExtension().lastPathComponent); profile.resolvedIP = try Storage.resolve(profile.endpointHost); return profile } }; DispatchQueue.main.async { self.busy = false; switch result { case .success(let profiles): guard self.settings.profiles.count + profiles.count <= 32 else { self.showError(AppError.message("Максимум 32 профиля")); return }; self.tab = "Профили"; self.settings.profiles += profiles; if self.settings.selectedID == nil { self.settings.selectedID = profiles.first?.id }; self.persistAndConfigure(); case .failure(let error):self.showError(error) } } }
    }
    func removeProfile(_ profile: Profile) { guard confirm("Удалить \(profile.name)?",detail:"Профиль будет удалён из Keychain приложения.") else { return }; settings.profiles.removeAll { $0.id == profile.id }; if settings.selectedID == profile.id { settings.selectedID = settings.profiles.first?.id }; if settings.profiles.isEmpty { settings.mode = .off }; persistAndConfigure() }
    @objc func toggleLogin(_ sender: NSButton) { do { try Storage.setLaunchAtLogin(sender.state == .on); settings.launchAtLogin = sender.state == .on; try Storage.save(settings) } catch { sender.state = settings.launchAtLogin ? .on : .off; showError(error) } }
    @objc func woke() { observer.report(); refresh(); checkAutomaticUpdates(); checkRoutingUpdates() }
    func installService() {
        guard !settings.profiles.isEmpty else { tab = "Профили"; openWindow(); return }
        guard confirm("Установить VPN-службу AutoTurn?",detail:"Служба получит права администратора для нашего туннеля, DNS и блокировки прямого трафика. После установки начнёт работать выбранный режим. Это тестовая сборка: подготовь возможность отключить VPN через меню.") else { return }
        guard let script = Bundle.main.url(forResource:"install-service",withExtension:"sh") else { showError(AppError.message("Установщик не найден")); return }
        runInstaller(script:script, app:Bundle.main.bundleURL) { result in switch result { case .success: self.serviceAvailable = true; self.persistAndConfigure(); case .failure(let error):self.showError(error) } }
    }
    func runInstaller(script: URL, app: URL, completion: @escaping (Result<Void,Error>) -> Void) {
        busy = true
        let shell = "/bin/sh " + quote(script.path) + " " + quote(app.path) + " " + String(getuid())
        let apple = "do shell script " + appleString(shell) + " with administrator privileges"
        DispatchQueue.global().async { var error: NSDictionary?; let result = NSAppleScript(source:apple)?.executeAndReturnError(&error); DispatchQueue.main.async { self.busy = false; completion(error == nil && result != nil ? .success(()) : .failure(AppError.message("Установка отменена или не выполнена. Текущие настройки сохранены."))) } }
    }
    func setupAutomaticUpdates() {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined { center.requestAuthorization(options:[.alert]) { _,_ in } }
        }
        updateTimer = Timer(timeInterval:60,repeats:true) { [weak self] _ in self?.checkAutomaticUpdates() }
        RunLoop.main.add(updateTimer!,forMode:.common)
        checkAutomaticUpdates()
    }
    func checkAutomaticUpdates() {
        guard !checkingUpdate, !busy, updateHistory.isDue() else { return }
        performUpdateCheck(manual:false)
    }
    func checkUpdates() {
        guard !checkingUpdate else { return }
        performUpdateCheck(manual:true)
    }
    func performUpdateCheck(manual:Bool) {
        checkingUpdate = true; updateHistory.attempted()
        updater.check { [weak self] result in
            guard let self = self else { return }; self.checkingUpdate = false
            switch result {
            case .failure(let error): if manual { self.showError(error) }
            case .success(let release):
                self.updateHistory.succeeded(); self.buildNavigation(); self.refreshOpenMenu()
                if self.tab == "Настройки" { self.buildPage() }
                if let release = release {
                    if manual { self.presentUpdate(release) }
                    else if self.updateHistory.shouldNotify(version:release.version,build:release.build) { self.notifyUpdate(release) }
                } else if manual { self.info("Установлена актуальная версия AutoTurn.") }
            }
        }
    }
    func presentUpdate(_ release:MacRelease) {
        guard confirm("Доступен AutoTurn \(release.version)",detail:release.notes + "\n\nПрофили и настройки сохранятся. Скачать обновление?") else { return }
        checkingUpdate = true
        updater.download(release) { [weak self] result in
            guard let self = self else { return }; self.checkingUpdate = false
            switch result { case .failure(let error):self.showError(error); case .success(let url):self.offerInstallation(url,release:release) }
        }
    }
    func notifyUpdate(_ release:MacRelease) {
        guard updateHistory.shouldNotify(version:release.version,build:release.build), !notifyingVersions.contains(release.version) else { return }
        notifyingVersions.insert(release.version)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized else { DispatchQueue.main.async { self?.notifyingVersions.remove(release.version) }; return }
            let content = UNMutableNotificationContent()
            content.title = "Доступен AutoTurn \(release.version)"
            content.body = "Нажми, чтобы открыть обновление. Профили и настройки сохранятся."
            let request = UNNotificationRequest(identifier:"autoturn-update-\(release.build)",content:content,trigger:nil)
            center.add(request) { error in DispatchQueue.main.async { self?.notifyingVersions.remove(release.version); if error == nil { self?.updateHistory.notified(version:release.version,build:release.build) } } }
        }
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner,.list]) }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping () -> Void) {
        DispatchQueue.main.async { self.openWindow(); self.activateUpdate() }; completionHandler()
    }
    func offerInstallation(_ archive: URL, release: MacRelease) {
        guard confirm("Обновление проверено",detail:"Установить и перезапустить AutoTurn? Профили сохранятся. Для обновления VPN-службы macOS запросит права администратора.") else { return }
        let directory = archive.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto"); process.arguments = ["-x","-k",archive.path,directory.path]; try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw AppError.message("Не удалось распаковать пакет") }
            let app = directory.appendingPathComponent("AutoTurn.app")
            try Updater.validateBundle(app,release:release)
            guard let bundle = Bundle(url:app), bundle.bundleIdentifier == "ru.hl100.autoturn", bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String == String(release.build), let script = bundle.url(forResource:"install-service",withExtension:"sh") else { throw AppError.message("В пакете другая версия приложения") }
            runInstaller(script:script,app:app) { result in switch result { case .failure(let error):self.showError(error); case .success: let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/open"); process.arguments = ["-n","/Applications/AutoTurn.app"]; try? process.run(); NSApp.terminate(nil) } }
        } catch { showError(error) }
    }
    func exportDiagnostics() { let panel = NSSavePanel(); panel.nameFieldStringValue = "AutoTurn-diagnostics.txt"; guard panel.runModal() == .OK, let url = panel.url else { return }; let text = "AutoTurn \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "0.1.0")\nAWG 3.1\nphase=\(status.phase.rawValue) mode=\(settings.mode.rawValue) guard=\(status.guardActive)\n" + status.events.joined(separator:"\n"); do { try text.write(to:url,atomically:true,encoding:.utf8) } catch { showError(error) } }
    func quit() { guard confirm("Отключить VPN и завершить?",detail:"Вне дома будет разрешён прямой интернет. Закрытие одного пульта не отключает VPN.") else { return }; if serviceAvailable { busy = true; client.send(RPCRequest(command:"stop",settings:nil,network:nil)) { result in self.busy = false; switch result { case .success(let response) where response.ok: NSApp.terminate(nil); default:self.accept(result); self.info("Не удалось подтвердить остановку службы. AutoTurn остаётся открыт.") } } } else { NSApp.terminate(nil) } }
    func windowShouldClose(_ sender:NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func confirm(_ title:String,detail:String) -> Bool { popover.performClose(nil); NSApp.activate(ignoringOtherApps:true); let alert = ApplicationArtwork.alert(title:title,detail:detail); alert.addButton(withTitle:"Продолжить"); alert.addButton(withTitle:"Отмена"); return alert.runModal() == .alertFirstButtonReturn }
    func showError(_ error:Error) { info(error.localizedDescription) }
    func info(_ text:String) { popover.performClose(nil); NSApp.activate(ignoringOtherApps:true); let alert = ApplicationArtwork.alert(title:"AutoTurn",detail:text); alert.addButton(withTitle:"OK"); alert.runModal() }
    private func quote(_ text:String) -> String { "'" + text.replacingOccurrences(of:"'",with:"'\\''") + "'" }
    private func appleString(_ text:String) -> String { "\"" + text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"") + "\"" }
    func beginLiveNetworkTest() {
        func report(_ text:String) { print(text); fflush(stdout) }
        let started = Date()
        if observer.snapshot().ssid == nil { observer.requestPermission() }
        testTimer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(started) > 35 { self.finishLiveNetworkTest("Home Wi-Fi or service not available; check location permission"); return }
            guard self.serviceAvailable, !self.busy, !self.polling, let ssid = self.observer.snapshot().ssid else { return }
            self.testTimer?.invalidate()
            if !self.settings.homeSSIDs.contains(ssid) { self.settings.homeSSIDs.append(ssid); report("Added current Wi-Fi to home networks for the requested home test") }
            if self.settings.profiles.isEmpty, let index = CommandLine.arguments.firstIndex(of:"--live-network-test"), index+1 < CommandLine.arguments.count {
                do { var profile = try Profile.parse(String(contentsOfFile:CommandLine.arguments[index+1],encoding:.utf8),name:"MacBook"); profile.resolvedIP = try Storage.resolve(profile.endpointHost); self.settings.profiles = [profile]; self.settings.selectedID = profile.id } catch { self.finishLiveNetworkTest(error.localizedDescription); return }
            }
            guard !self.settings.profiles.isEmpty else { self.finishLiveNetworkTest("No VPN profiles"); return }
            report("Live test starts: current Wi-Fi is identified; home profile configured; no keys printed")
            self.runLiveStep(0)
        }
    }
    func runLiveStep(_ index:Int) {
        let steps: [(Mode,Phase)] = [(.on,.connected),(.auto,.home),(.on,.connected),(.off,.off),(.auto,.home)]
        guard index < steps.count else { finishLiveNetworkTest(nil); return }
        let (mode,expected) = steps[index]
        print("BEGIN application mode \(mode.rawValue)"); fflush(stdout)
        setMode(mode)
        let started = Date(); var steadySince: Date?
        testTimer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(started) > 40 { self.finishLiveNetworkTest("Timeout switching to \(mode.rawValue): \(self.status.message)"); return }
            guard !self.busy, !self.polling else { return }
            guard self.status.phase == expected else { steadySince = nil; if self.status.phase == .error { self.finishLiveNetworkTest(self.status.message) }; return }
            guard self.status.guardActive == (mode == .on) else { self.finishLiveNetworkTest("Wrong guard state in \(mode.rawValue)"); return }
            if steadySince == nil { steadySince = Date() }
            let requiredHold: TimeInterval = mode == .auto ? 12 : 1
            guard Date().timeIntervalSince(steadySince!) >= requiredHold else { return }
            self.testTimer?.invalidate()
            DispatchQueue.global().async {
                let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/curl"); process.arguments = ["--silent","--fail","--noproxy","*","--max-time","7","https://www.apple.com/library/test/success.html"]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                var success = false
                do { try process.run(); process.waitUntilExit(); success = process.terminationStatus == 0 } catch {}
                guard success else { DispatchQueue.main.async { self.finishLiveNetworkTest("Direct HTTPS failed in \(mode.rawValue)") }; return }
                let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 7; configuration.timeoutIntervalForResource = 10
                let session = URLSession(configuration:configuration)
                session.dataTask(with:URL(string:"https://www.apple.com/library/test/success.html")!) { data,response,error in
                    let nativeSuccess = error == nil && (response as? HTTPURLResponse)?.statusCode == 200 && !(data?.isEmpty ?? true)
                    session.finishTasksAndInvalidate()
                    DispatchQueue.main.async {
                        guard nativeSuccess else { self.finishLiveNetworkTest("Native macOS HTTPS failed in \(mode.rawValue): \(error?.localizedDescription ?? "HTTP response")"); return }
                        print("PASS application \(mode.rawValue): phase=\(expected.rawValue), guard=\(self.status.guardActive), curl and native URLSession HTTPS work; hold=\(Int(requiredHold))s"); fflush(stdout)
                        self.runLiveStep(index+1)
                    }
                }.resume()
            }
        }
    }
    func finishLiveNetworkTest(_ error:String?) {
        testTimer?.invalidate()
        if let error = error {
            testExitCode = 1; fputs("LIVE TEST FAILED: \(error)\n",stderr)
            settings.mode = .off; try? Storage.save(settings)
            client.send(RPCRequest(command:"stop",settings:nil,network:nil)) { _ in NSApp.terminate(nil) }
        } else {
            print("LIVE APPLICATION TEST PASSED: on -> auto(home) -> on -> off -> auto(home), actual HTTPS in every mode. App and service used their normal configure/network paths. Final mode is auto at home."); fflush(stdout)
            NSApp.terminate(nil)
        }
    }
    func checkInterface() {
        func require(_ condition:Bool,_ message:String) { if !condition { fputs("UI check failed: \(message)\n",stderr); exit(1) } }
        func buttons(_ view:NSView) -> [ActionButton] { (view as? ActionButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) } }
        let routingPicker = RoutingPicker(database:routingDatabase,query:"te")
        require(routingPicker.rows.arrangedSubviews.contains { ($0 as? NSButton)?.title == "Telegram" },"routing picker must suggest Telegram while typing")
        routingPicker.selected.insert("telegram"); routingPicker.search.stringValue = "chatgpt.com"; routingPicker.updateRows()
        require(routingPicker.selected.contains("telegram") && routingPicker.rows.arrangedSubviews.contains { ($0 as? NSButton)?.title.hasPrefix("Своё правило:") == true },"routing selection must survive search and offer custom domains")
        require(routingPicker.rows.arrangedSubviews.contains { ($0 as? NSButton)?.identifier?.rawValue == "openai" },"domain alias must suggest its service")
        routingPicker.search.stringValue = ""; routingPicker.updateRows(); routingPicker.layoutSubtreeIfNeeded()
        require(routingPicker.rows.arrangedSubviews.count > 5 && routingPicker.subviews.compactMap { $0 as? NSScrollView }.first!.frame.height >= 330,"routing picker must show a tall scrollable catalog")
        require(ApplicationArtwork.icon != nil,"bundled application artwork")
        let iconAlert = ApplicationArtwork.alert(title:"AutoTurn",detail:"Icon check")
        require(iconAlert.icon === ApplicationArtwork.icon && !iconAlert.icon.isTemplate,"dialog must use bundled application artwork")
        var iconImages = Set<Data>()
        for icon in StatusIcon.allCases {
            let image = icon.image
            require(image === icon.image,"status artwork must be reused between polls")
            require(image.isTemplate && image.size == NSSize(width:18,height:18),"status icon dimensions/template")
            guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:data) else { require(false,"status icon rasterization"); return }
            require(bitmap.pixelsWide >= 18 && bitmap.pixelsHigh >= 18,"status icon raster size")
            iconImages.insert(data)
        }
        require(iconImages.count == StatusIcon.allCases.count,"status icons must differ visually")
        require(StatusIcon.state(.home,missingLocation:false) == .home && StatusIcon.state(.connected,missingLocation:false) == .connected && StatusIcon.state(.connected,missingLocation:true) == .unknown,"status icon home/VPN/permission mapping")
        let sample = Profile(name:"Резервный профиль с длинным названием",addresses:["10.0.0.2/32"],dns:["1.1.1.1"],mtu:1280,interface:[:],peer:[:],endpointHost:"198.51.100.10",endpointPort:51820,resolvedIP:"198.51.100.10")
        for profiles in [[],[sample,sample,sample]] {
            settings.profiles = profiles
            for width in [CGFloat(700),760,1000] {
                window.setContentSize(NSSize(width:width,height:700))
                for name in ["Соединение","Профили","Маршруты","Домашняя сеть","События","Настройки"] {
                    tab = name; buildPage(); window.contentView?.layoutSubtreeIfNeeded()
                    require(abs(window.contentView!.bounds.width-width)<1,"window width changed")
                    require(body.bounds.width == width-48,"content margins")
                    for button in buttons(body) { require(button.frame.width > 20 && button.frame.height >= 36,"button collapsed in \(name)") }
                    if name == "Профили" || (name == "Соединение" && profiles.isEmpty) {
                        require(buttons(body).contains { $0.title == "+ Добавить профиль" },"import button missing")
                    }
                    for view in page.arrangedSubviews { require(view.frame.minY >= -1 && view.frame.maxY <= page.bounds.height+1,"clipped content in \(name)") }
                }
            }
            let menu = menuView(); menu.layoutSubtreeIfNeeded(); require(buttons(menu).contains { $0.title == "Ещё ···" },"menu management missing")
            require(menu.bounds.width == 332,"menu width differs from approved design")
            require(buttons(menu).contains { $0.title == "Открыть пульт ↗" },"console shortcut missing")
            require(buttons(menu).filter { $0.profileSubtitle != nil }.count == profiles.count,"menu profile rows missing")
            for button in buttons(menu) {
                let frame = button.convert(button.bounds,to:menu)
                require(frame.minX >= 20 && frame.maxX <= 312.1 && frame.minY >= 0 && frame.maxY <= menu.bounds.height,"clipped menu action")
                if button.profileSubtitle != nil { require(frame.height == 50 && button.rowStyle,"menu profile layout") }
            }
            func checkCredits(_ view:NSView) { if let field = view as? NSTextField, field.stringValue.contains("LENCHA_") { let frame = field.convert(field.bounds,to:menu); require(frame.width > 40 && frame.maxX <= menu.bounds.width && frame.minX >= 0 && frame.minY >= 0,"clipped menu credit") }; view.subviews.forEach { checkCredits($0) } }
            checkCredits(menu)
            let mark = menu.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "HL100" }
            require(mark != nil && mark!.frame.width >= mark!.intrinsicContentSize.width,"HL100 label clipped")
        }
        checkingConnection = true
        tab = "Соединение"; buildPage()
        require(buttons(body).contains { $0.title == "Проверяем HTTPS…" && !$0.isEnabled },"console check must show progress and prevent repeats")
        for appearance in MenuAppearance.allCases {
            testMenuAppearance = appearance
            require(buttons(menuView()).contains { $0.title == "Проверяем HTTPS…" && !$0.isEnabled },"menu check must show progress and prevent repeats")
        }
        checkingConnection = false; testMenuAppearance = nil
        let mockRelease = MacRelease(version:"9.9.9",build:999,minimumOS:"13.0",archiveURL:"",sha256:"",signature:"",notes:"")
        updater.candidate = mockRelease
        for appearance in MenuAppearance.allCases {
            testMenuAppearance = appearance
            for phase in [Phase.home,.connected,.recovering,.off,.setup] {
                status.phase = phase
                let menu = menuView(); menu.layoutSubtreeIfNeeded()
                require(buttons(menu).contains { $0.title == "● Обновить до 9.9.9" },"available update missing from menu")
                for button in buttons(menu) {
                    let frame = button.convert(button.bounds,to:menu)
                    require(frame.minX >= 20 && frame.maxX <= 312.1 && frame.maxY <= menu.bounds.height,"menu theme clips action")
                }
            }
        }
        testMenuAppearance = nil
        for appearance in ConsoleAppearance.allCases {
            testConsoleAppearance = appearance
            for width in [CGFloat(700),760] {
                window.setContentSize(NSSize(width:width,height:700))
                for name in ["Соединение","Профили","Маршруты","Домашняя сеть","События","Настройки"] {
                    tab = name; buildPage(); window.contentView?.layoutSubtreeIfNeeded()
                    require(abs(window.contentView!.bounds.width-width)<1,"theme changed window size")
                    for button in buttons(body) {
                        let frame = button.convert(button.bounds,to:body)
                        require(button.frame.width > 20 && button.frame.height >= 36,"theme collapsed control")
                        require(frame.minX >= -1 && frame.maxX <= body.bounds.width+1,"theme action exceeds content width")
                    }
                    if name == "Соединение" { require(buttons(body).contains { $0.title == "Проверить связь" },"console theme lost check action") }
                    if name == "Настройки" { require(Set(buttons(body).map { $0.title }).isSuperset(of:ConsoleAppearance.allCases.map(\.title)),"console themes missing") }
                }
            }
        }
        testConsoleAppearance = nil
        require(RoutingDatabase.validCatalog(routingDatabase.snapshot.catalog),"bundled route catalog invalid")
        settings.routing.mode = .rules
        settings.routing.rules = [RoutingRule(name:"YouTube",serviceID:"youtube",sourcePath:"source2/youtube.txt",baseDomains:["youtube.com","googlevideo.com","ytimg.com"]),RoutingRule(name:"Свой сервер",domains:["panel.hl100.ru"],destination:.direct)]
        for appearance in RoutingAppearance.allCases {
            testRoutingAppearance = appearance
            for width in [CGFloat(700),760] {
                window.setContentSize(NSSize(width:width,height:700)); tab = "Маршруты"; buildPage(); window.contentView?.layoutSubtreeIfNeeded()
                require(buttons(body).contains { $0.title == "Обновить базы" },"route database action missing")
                require(buttons(body).contains { $0.title == "Импорт" } && buttons(body).contains { $0.title == "Экспорт" },"route import/export missing")
                for button in buttons(body) { let frame = button.convert(button.bounds,to:body); require(frame.minX >= -1 && frame.maxX <= body.bounds.width+1,"route theme action exceeds content width") }
            }
        }
        testRoutingAppearance = nil; settings.routing = RoutingSettings()
        tab = "Настройки"; buildPage(); window.contentView?.layoutSubtreeIfNeeded()
        require(buttons(body).filter { MenuAppearance.allCases.map(\.title).contains($0.title) }.count == 3,"appearance choices missing")
        require(buttons(body).contains { $0.title == "● Обновить до 9.9.9" },"settings update missing")
        require(navigation!.arrangedSubviews.compactMap { $0 as? ActionButton }.contains { $0.title == "● Обновить" },"global update badge missing")
        for width in [CGFloat(700),760] {
            window.setContentSize(NSSize(width:width,height:700)); window.contentView?.layoutSubtreeIfNeeded()
            for button in navigation!.arrangedSubviews.compactMap({ $0 as? ActionButton }) {
                require(button.frame.maxX <= navigation!.bounds.width+1 && button.frame.minX >= 0,"navigation/update indicator clipped")
            }
        }
        updater.candidate = nil
        tab = "Домашняя сеть"; buildPage(); window.contentView?.layoutSubtreeIfNeeded()
        let homeField = page.arrangedSubviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString != nil }!
        homeField.stringValue = "ExistingHome"; pendingHomeField = homeField
        updateHomeNetwork(NetworkObservation(available:true,interface:"en0",ssid:"SecondHome",gateway:"192.0.2.1"))
        require(homeField.stringValue == "ExistingHome, SecondHome" && pendingHomeField == nil,"home network not filled after permission")
        addHomeSSID("SecondHome",to:homeField); require(homeField.stringValue == "ExistingHome, SecondHome","duplicate home network")
        require(homeNetworkLabel?.stringValue == "Текущий Wi-Fi: SecondHome","home label not updated live")
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([URL(fileURLWithPath:"/tmp/test.conf") as NSURL,URL(fileURLWithPath:"/tmp/unrelated.txt") as NSURL])
        let surface = window.contentView as! ConsoleSurface
        require(surface.files(pasteboard).map { $0.lastPathComponent } == ["test.conf"],"file drop filtering")
        settings.profiles = []; status.phase = .home; status.message = "Домашняя сеть · через роутер"
        togglePopover(); require(popover.isShown,"popover did not open")
        let previousView = popover.contentViewController!.view
        status.phase = .connected; status.message = "VPN подключён · трафик проверен"; status.guardActive = true
        updateStatus()
        require(popover.isShown && popover.contentViewController!.view !== previousView,"open menu did not refresh in place")
        require(popover.window.styleMask.contains(.nonactivatingPanel),"menu must not activate another Space")
        require(popover.window.collectionBehavior.contains(.fullScreenAuxiliary),"menu missing full-screen support")
        let fixedFrame = popover.window.frame
        let anchorWindow = statusItem.button!.window!
        let anchorFrame = anchorWindow.frame
        anchorWindow.setFrameOrigin(NSPoint(x:anchorFrame.minX,y:anchorFrame.minY+60))
        require(popover.window.frame == fixedFrame && popover.isShown,"menu followed auto-hiding status-bar anchor")
        // A live status refresh must keep the menu's screen anchor, too.
        status.message += " · обновлено"; updateStatus()
        require(popover.window.frame.maxY == fixedFrame.maxY && popover.window.frame.maxX == fixedFrame.maxX,"live refresh moved floating menu")
        anchorWindow.setFrame(anchorFrame,display:false)
        let unchangedView = popover.contentViewController!.view; updateStatus()
        require(popover.contentViewController!.view === unchangedView,"unchanged status rebuilt menu")
        if let inside = NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:popover.contentViewController!.view.window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1) {
            handlePopoverClick(inside); require(popover.isShown,"inside click closed menu")
        }
        if let outside = NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1) {
            handlePopoverClick(outside); require(!popover.isShown,"outside click did not close menu")
        }
        stopPopoverMonitoring()
        require(localClickMonitor == nil && globalClickMonitor == nil && resignObserver == nil,"popover monitors leaked")
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1000 { updateStatus() }
        let milliseconds = (CFAbsoluteTimeGetCurrent()-start)*1000/1000
        print(String(format:"Unchanged UI update: %.3f ms per call (1000 calls); no layout rebuild. This is not a display FPS measurement.",milliseconds))
        print("UI checks passed: five tabs, three menu themes, update indicators, profile layouts, open menu refresh without reopening, unchanged status preserves view, inside/outside clicks, monitor cleanup and file drop. No Keychain or network changes.")
        NSApp.terminate(nil)
    }
    func renderPreview() {
        status = ServiceStatus(phase:.setup,mode:.auto,profileID:nil,profileName:nil,network:"Проверка сети начнётся после настройки",message:"Импортируй AmneziaWG .conf и установи VPN-службу",guardActive:false,verifiedAt:nil,events:[],tunnel:nil)
        if let index = CommandLine.arguments.firstIndex(of:"--preview-tab"), index+1 < CommandLine.arguments.count { tab = CommandLine.arguments[index+1] }
        if CommandLine.arguments.contains("--preview-profiles") {
            settings.profiles = ["Основной","Резервный","Дальний"].map { Profile(name:$0,addresses:["10.0.0.2/32"],dns:["1.1.1.1"],mtu:1280,interface:[:],peer:[:],endpointHost:"198.51.100.10",endpointPort:51820,resolvedIP:"198.51.100.10") }; settings.selectedID = settings.profiles.first?.id
        }
        if CommandLine.arguments.contains("--preview-connected") {
            serviceAvailable = true
            status = ServiceStatus(phase:.connected,mode:.auto,profileID:settings.selectedID,profileName:selectedProfile()?.name,network:"Другая Wi-Fi-сеть",message:"VPN подключён · связь проверена",guardActive:true,verifiedAt:Date(),events:[],tunnel:nil)
        }
        if let i = CommandLine.arguments.firstIndex(of:"--preview-console-style"), i+1 < CommandLine.arguments.count { testConsoleAppearance = ConsoleAppearance(rawValue:CommandLine.arguments[i+1]) }
        if let i = CommandLine.arguments.firstIndex(of:"--preview-routing-style"), i+1 < CommandLine.arguments.count { testRoutingAppearance = RoutingAppearance(rawValue:CommandLine.arguments[i+1]) }
        if tab == "Маршруты" {
            settings.routing.mode = .rules
            settings.routing.rules = ["youtube","telegram","openai","github"].compactMap { id in guard let entry = routingDatabase.snapshot.services[id] else { return nil }; return RoutingRule(name:entry.name,serviceID:id,sourcePath:entry.sourcePath,baseDomains:entry.domains,destination:id == "github" ? .direct : .vpn) }
            settings.routing.rules.append(RoutingRule(name:"Мой сервер",domains:["panel.hl100.ru"],destination:.direct)); routingSelectedID = settings.routing.rules.first?.id
        }
        if let i = CommandLine.arguments.firstIndex(of:"--preview-menu-style"), i+1 < CommandLine.arguments.count { testMenuAppearance = MenuAppearance(rawValue:CommandLine.arguments[i+1]) }
        buildPage(); updateStatus(); window.setContentSize(NSSize(width:760,height:700)); window.contentView?.layoutSubtreeIfNeeded()
        guard let i = CommandLine.arguments.firstIndex(of:"--render-preview"), i+1 < CommandLine.arguments.count, let windowView = window.contentView else { NSApp.terminate(nil); return }
        let view = CommandLine.arguments.contains("--preview-menu") ? menuView() : windowView
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { NSApp.terminate(nil); return }
        view.cacheDisplay(in:view.bounds,to:bitmap); if let data = bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:CommandLine.arguments[i+1])) }
        print("Native AppKit preview rendered \(view.bounds); no Keychain, helper or network changes performed")
        NSApp.terminate(nil)
    }
}
// Read-only diagnostics: parse the supplied file without Keychain, UI or tunnel changes.
if CommandLine.arguments.contains("--settings-fingerprint") {
    do {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Storage.load())
        print(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()); exit(0)
    } catch { fputs("Settings preservation check failed; no profile data printed\n",stderr); exit(1) }
}
if CommandLine.arguments.contains("--check-update-feed") {
    let updater = Updater()
    var olderBuild: Int?
    if let index = CommandLine.arguments.firstIndex(of:"--installed-build"), index+1 < CommandLine.arguments.count { olderBuild = Int(CommandLine.arguments[index+1]) }
    updater.check(installedBuildOverride:olderBuild) { result in
        switch result {
        case .failure(let error): fputs("Update feed failed: \(error.localizedDescription)\n",stderr); exit(1)
        case .success(nil): print("Signed GitHub update feed checked; installed version is current"); exit(0)
        case .success(let release?):
            print("Signed GitHub update verified: \(release.version), build \(release.build)")
            if CommandLine.arguments.contains("--download-update-test") {
                updater.download(release) { result in
                    switch result { case .failure(let error):fputs("Download verification failed: \(error.localizedDescription)\n",stderr); exit(1); case .success: print("GitHub archive downloaded; SHA-256 and Ed25519 signature verified. No installation or network configuration changes."); exit(0) }
                }
            } else { exit(0) }
        }
    }
    dispatchMain()
}
if let index = CommandLine.arguments.firstIndex(of:"--validate-profile"), index+1 < CommandLine.arguments.count {
    do {
        let file = URL(fileURLWithPath:CommandLine.arguments[index+1])
        let profile = try Profile.parse(String(contentsOf:file,encoding:.utf8),name:"Validation")
        _ = try profile.validated()
        _ = try profile.uapi(ip:"198.51.100.1")
        print("AmneziaWG profile validated, including helper transport and UAPI serialization. No keys printed, stored or sent; no network changes.")
        exit(0)
    } catch { fputs("Profile validation failed: \(error.localizedDescription)\n",stderr); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of:"--routing-live-check"), index+1 < CommandLine.arguments.count {
    exit(RoutingLiveCheck.run(profilePath:CommandLine.arguments[index+1]))
}
if let index = CommandLine.arguments.firstIndex(of:"--ipc-test-client"), index+1 < CommandLine.arguments.count {
    do { let fd = try IPC.connect(CommandLine.arguments[index+1]); defer { close(fd) }; let answer = String(data:try IPC.readLine(fd:fd),encoding:.utf8); guard answer == "allowed" else { throw AppError.message("Client was rejected") }; print("Signed app IPC authentication passed; no settings or network changes"); exit(0) } catch { fputs("IPC authentication test failed\n",stderr); exit(1) }
}
let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of:"--render-alert-preview"), index+1 < CommandLine.arguments.count {
    app.setActivationPolicy(.accessory)
    if let icon = ApplicationArtwork.icon { app.applicationIconImage = icon }
    let alert = ApplicationArtwork.alert(title:"Доступен AutoTurn 0.1.8",detail:"Иконка приложения загружается напрямую из установленного пакета. Профили и настройки сохранятся. Скачать обновление?")
    alert.addButton(withTitle:"Продолжить"); alert.addButton(withTitle:"Отмена")
    alert.window.appearance = NSAppearance(named:.darkAqua)
    alert.layout()
    let view = alert.window.contentView!
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
    view.cacheDisplay(in:view.bounds,to:bitmap)
    try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))
    print("Real NSAlert preview rendered; no settings, modal or network changes")
    exit(0)
}
let controller = Controller(); app.delegate = controller; app.run()
if controller.liveNetworkTest { exit(controller.testExitCode) }
