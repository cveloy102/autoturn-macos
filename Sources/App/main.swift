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
            (primary ? Palette.red : Palette.panel).setFill(); rect.fill()
            (primary ? Palette.red : Palette.line).setStroke(); NSBezierPath(rect:rect).stroke()
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
        hasVerticalScroller = true; drawsBackground = false; borderType = .noBorder
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
        navigation.frame = NSRect(x:24,y:90,width:bounds.width-48,height:48)
        content.frame = NSRect(x:24,y:162,width:bounds.width-48,height:max(400,bounds.height-232))
        bottom.frame = NSRect(x:24,y:bounds.height-46,width:bounds.width-48,height:46)
    }
    override func draw(_ dirtyRect:NSRect) {
        Palette.line.setFill()
        for y in [CGFloat(90),138,bounds.height-46] { NSRect(x:0,y:y,width:bounds.width,height:1).fill() }
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

final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    var settings = Settings(), status = ServiceStatus()
    var serviceAvailable = false, busy = false, checkingUpdate = false, polling = false
    var window: NSWindow!, body = NSView(), page = NSStackView(), footer: NSTextField!
    var tab = "Соединение"
    var navigation: NSStackView?
    var statusItem: NSStatusItem!, popover = NSPopover()
    var localClickMonitor: Any?, globalClickMonitor: Any?, resignObserver: NSObjectProtocol?
    var renderedMenuRevision = "", observedRevision = ""
    var lastStatusRefresh = Date.distantPast
    let observeLiveNetwork = CommandLine.arguments.contains("--observe-live-network")
    let client = ServiceClient(), observer = NetworkObserver(), updater = Updater()
    let updateHistory = UpdateHistory()
    var updateTimer: Timer?
    var timer: Timer?, connectionTitle: NSTextField?, connectionMessage: NSTextField?, connectionNetwork: NSTextField?, connectionProfile: NSTextField?, connectionGuard: NSTextField?
    let liveNetworkTest = CommandLine.arguments.contains("--live-network-test")
    var testExitCode: Int32 = 0
    var testTimer: Timer?
    let preview = CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--ui-self-check")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !preview { do { settings = try Storage.load() } catch { showError(error) } }
        buildWindow(); buildStatusItem()
        if CommandLine.arguments.contains("--ui-self-check") { checkInterface(); return }; if preview { renderPreview(); return }
        observer.changed = { [weak self] network in guard let self = self, self.serviceAvailable else { return }; self.client.send(RPCRequest(command:"network",settings:nil,network:network)) { self.accept($0,quiet:true) } }
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
        refresh()
        timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in
            guard let self = self else { return }
            if self.popover.isShown || self.observeLiveNetwork || Date().timeIntervalSince(self.lastStatusRefresh) >= 5 { self.refresh() }
        }
        RunLoop.main.add(timer!,forMode:.common)
        if !CommandLine.arguments.contains("--background") { openWindow() }
        if liveNetworkTest { beginLiveNetworkTest() }
        else { setupAutomaticUpdates() }
    }
    func buildWindow() {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:700),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "AutoTurn / Пульт"; window.contentMinSize = NSSize(width:700,height:700); window.delegate = self; window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named:.darkAqua); window.backgroundColor = Palette.bg
        let container = ConsoleSurface(frame:NSRect(x:0,y:0,width:760,height:700)); window.contentView = container
        container.dropped = { [weak self] files in self?.importProfiles(files) }
        let mark = PixelMark(frame:.zero); mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant:25).isActive = true; mark.heightAnchor.constraint(equalToConstant:25).isActive = true
        let word = label("AUTOTURN_",size:23)
        let wordText = NSMutableAttributedString(string:"AUTO",attributes:[.font:NSFont.monospacedSystemFont(ofSize:23,weight:.medium),.foregroundColor:Palette.ink])
        wordText.append(NSAttributedString(string:"TURN_",attributes:[.font:NSFont.monospacedSystemFont(ofSize:23,weight:.medium),.foregroundColor:Palette.red])); word.attributedStringValue = wordText
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
        nav.arrangedSubviews.forEach { nav.removeArrangedSubview($0); $0.removeFromSuperview() }
        for name in ["Соединение","Профили","Домашняя сеть","События"] {
            let button = ActionButton(name == "Профили" ? "Профили \(settings.profiles.count)" : name,primary:tab == name) { [weak self] in self?.tab = name; self?.buildPage() }
            button.tabStyle = true; nav.addArrangedSubview(button)
        }
        nav.addArrangedSubview(NSView())
    }
    func buildPage() {
        buildNavigation()
        body.subviews.forEach { $0.removeFromSuperview() }; page = stack(spacing:10); pin(page,inside:body,inset:0)
        connectionTitle = nil; connectionMessage = nil; connectionNetwork = nil; connectionProfile = nil; connectionGuard = nil
        switch tab {
        case "Профили": profilesPage()
        case "Домашняя сеть": homePage()
        case "События": eventsPage()
        default: connectionPage()
        }
        for view in page.arrangedSubviews where !(view is ActionButton) { view.widthAnchor.constraint(equalTo:page.widthAnchor).isActive = true }
        page.addArrangedSubview(NSView())
    }
    func connectionPage() {
        page.addArrangedSubview(label("[ 01 / CONNECTION ]",size:11,color:Palette.red))
        connectionTitle = heading(titleForStatus()); page.addArrangedSubview(connectionTitle!)
        connectionMessage = label(status.message,color:Palette.dim); page.addArrangedSubview(connectionMessage!)
        if settings.profiles.isEmpty {
            page.addArrangedSubview(ActionButton("+ Добавить профиль",primary:true) { [weak self] in self?.importProfile() })
            page.addArrangedSubview(label("Выбери файл AmneziaWG .conf или перетащи его в это окно.",size:12,color:Palette.dim))
        }
        page.addArrangedSubview(modeButtons())
        let facts = stack(spacing:12)
        func fact(_ title:String,_ value:NSTextField) {
            let key = label(title,color:Palette.dim); key.widthAnchor.constraint(equalToConstant:90).isActive = true
            value.alignment = .right; value.setContentHuggingPriority(.init(1),for:.horizontal)
            let row = stack([key,value],vertical:false,spacing:12); facts.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:facts.widthAnchor).isActive = true
        }
        connectionNetwork = label(status.network); connectionProfile = label(status.profileName ?? selectedProfile()?.name ?? "не выбран")
        connectionGuard = label(guardDescription(),size:11,color:status.guardActive ? Palette.green : Palette.dim)
        page.addArrangedSubview(line()); fact("Сеть",connectionNetwork!); fact("Профиль",connectionProfile!); fact("Трафик",label("Весь интернет через VPN")); fact("Защита",connectionGuard!)
        page.addArrangedSubview(facts); page.addArrangedSubview(line())
        let actions = stack(vertical:false,spacing:8)
        let check = ActionButton("Проверить связь",primary:true) { [weak self] in self?.command("check") }; check.isEnabled = serviceAvailable
        let next = ActionButton("Следующий профиль ↗") { [weak self] in self?.command("next") }; next.isEnabled = serviceAvailable
        actions.addArrangedSubview(check); actions.addArrangedSubview(next); actions.addArrangedSubview(NSView()); page.addArrangedSubview(actions)
        let setup = stack(vertical:false,spacing:8)
        if !serviceAvailable { setup.addArrangedSubview(ActionButton("Установить VPN-службу…") { [weak self] in self?.installService() }) }
        setup.addArrangedSubview(ActionButton("Обновления…") { [weak self] in self?.checkUpdates() }); setup.addArrangedSubview(NSView()); page.addArrangedSubview(setup)
        page.addArrangedSubview(line()); page.addArrangedSubview(label("ПРИ СБОЕ   Резерв по порядку. Без выхода напрямую.",size:11,color:Palette.dim))
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
            let select = ActionButton("\(active ? "✓" : String(index+1))  \(String(profile.name.prefix(28)))",primary:active) { [weak self] in self?.settings.selectedID = profile.id; self?.persistAndConfigure() }
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
        page.addArrangedSubview(label("Текущий Wi-Fi: \(current.ssid ?? "название недоступно")"))
        page.addArrangedSubview(ActionButton("Разрешить определение домашнего Wi-Fi…") { [weak self] in self?.observer.requestPermission() })
        let field = NSTextField(string:settings.homeSSIDs.joined(separator:"\n")); field.font = NSFont.monospacedSystemFont(ofSize:13,weight:.regular); field.textColor = Palette.ink; field.backgroundColor = Palette.panel; field.placeholderString = "Home_5G, Home_2G"; field.heightAnchor.constraint(equalToConstant:65).isActive = true; page.addArrangedSubview(field)
        let row = stack(vertical:false)
        row.addArrangedSubview(ActionButton("Добавить текущую") { [weak self] in guard let ssid = self?.observer.snapshot().ssid else { self?.showError(AppError.message("Разреши геолокацию для чтения SSID")); return }; var homes = field.stringValue.components(separatedBy:CharacterSet(charactersIn:",\n")).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }; if !homes.contains(ssid) { homes.append(ssid) }; field.stringValue = homes.joined(separator:", ") })
        row.addArrangedSubview(ActionButton("Сохранить сети",primary:true) { [weak self] in guard let self = self else { return }; let homes = field.stringValue.components(separatedBy:CharacterSet(charactersIn:",\n")).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }; guard homes.count <= 32, homes.allSatisfy({$0.utf8.count <= 32}) else { self.showError(AppError.message("Слишком длинное название сети")); return }; self.settings.homeSSIDs = Array(NSOrderedSet(array:homes)) as? [String] ?? homes; self.persistAndConfigure() })
        row.addArrangedSubview(NSView()); page.addArrangedSubview(row)
        let login = NSButton(checkboxWithTitle:"Запускать AutoTurn при входе",target:self,action:#selector(toggleLogin(_:))); login.state = settings.launchAtLogin ? .on : .off; page.addArrangedSubview(login)
        page.addArrangedSubview(label("Если SSID недоступен или интернет идёт через Ethernet, считаем сеть внешней. Название Wi-Fi само по себе не подтверждает подлинность сети.",size:11,color:Palette.dim))
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
        statusItem.button?.image = NSImage(systemSymbolName:"shield",accessibilityDescription:"AutoTurn"); statusItem.button?.image?.isTemplate = true; statusItem.button?.title = ""; statusItem.button?.font = NSFont.monospacedSystemFont(ofSize:16,weight:.regular)
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.toolTip = "AutoTurn · powered by LENCHA"
        popover.behavior = .transient; popover.animates = false; popover.delegate = self
    }
    func menuView() -> NSView {
        let view = FlippedDocument(frame:NSRect(x:0,y:0,width:292,height:600)); fill(view)
        var y: CGFloat = 18
        func place(_ child:NSView,_ height:CGFloat,_ x:CGFloat = 16,_ width:CGFloat = 260) {
            child.translatesAutoresizingMaskIntoConstraints = true
            child.frame = NSRect(x:x,y:y,width:width,height:height); view.addSubview(child)
        }
        func divider() { y += 7; place(line(),1); y += 8 }
        func row(_ text:String,_ icon:String? = nil,_ action:@escaping () -> Void) {
            let button = ActionButton(text,action:action); button.menuStyle = true; button.menuIcon = icon
            place(button,34); y += 34
        }
        let brand = label("AUTOTURN_",size:18)
        let word = NSMutableAttributedString(string:"AUTOTURN",attributes:[.font:brand.font!,.foregroundColor:Palette.ink])
        word.append(NSAttributedString(string:"_",attributes:[.font:brand.font!,.foregroundColor:Palette.red])); brand.attributedStringValue = word
        place(brand,24,16,195); place(label("HL100",size:11,color:Palette.dim),18,241,35)
        y += 37; place(line(),1); y += 17
        let dot = NSView(); fill(dot,color:status.phase == .connected ? Palette.green : status.phase == .error || status.phase == .recovering ? Palette.red : status.phase == .connecting || status.phase == .waiting ? NSColor.systemOrange : Palette.dim)
        place(dot,7,16,7); dot.frame.origin.y += 5
        let message = label(status.message,size:12)
        let messageHeight = max(18,ceil((status.message as NSString).boundingRect(with:NSSize(width:244,height:200),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:message.font!]).height)+3)
        place(message,messageHeight,32,244); y += messageHeight+6
        let reason = status.phase == .home ? "Домашняя сеть" : status.phase == .waiting ? "Сеть недоступна" : status.phase == .off ? "Выключено вручную" : status.phase == .setup ? "Настройка" : "Вне дома"
        let detail = label("\(reason) · \(status.profileName ?? selectedProfile()?.name ?? "нет профиля")",size:11,color:Palette.dim)
        detail.maximumNumberOfLines = 1; detail.lineBreakMode = .byTruncatingTail
        place(detail,18); y += 34
        for (index,mode) in [Mode.auto,.on,.off].enumerated() {
            let button = ActionButton(["Авто","Вкл.","Выкл."][index],primary:settings.mode == mode) { [weak self] in self?.setMode(mode) }
            place(button,36,16+CGFloat(index)*260/3,260/3)
        }
        y += 60; place(label("ПРОФИЛИ / ПО ПОРЯДКУ",size:11,color:Palette.dim),18); y += 27
        for (index,profile) in settings.profiles.prefix(3).enumerated() {
            let selected = profile.id == (status.profileID ?? settings.selectedID ?? settings.profiles.first?.id)
            let button = ActionButton(profile.name,primary:selected) { [weak self] in self?.settings.selectedID = profile.id; self?.persistAndConfigure() }
            button.rowStyle = true; button.profileSubtitle = "AmneziaWG"; button.profileMark = selected ? "✓" : String(format:"%02d",index+1)
            button.profileState = selected ? (status.phase == .connected ? "активен" : status.phase == .connecting ? "проверка" : status.phase == .waiting ? "ожидание" : status.phase == .recovering || status.phase == .error ? "нет связи" : "выбран") : "резерв"
            button.toolTip = profile.name; place(button,50); y += 50
        }
        if settings.profiles.isEmpty { place(label("Импортируй AmneziaWG .conf",size:11,color:Palette.dim),18); y += 18 }
        if settings.profiles.count > 3 { row("Все профили…","slider.horizontal.3") { [weak self] in self?.tab = "Профили"; self?.openWindow() } }
        divider()
        row("Проверить связь","waveform.path.ecg") { [weak self] in self?.command("check") }
        row("Следующий профиль","arrow.right") { [weak self] in self?.command("next") }
        divider()
        row("Домашняя сеть…","house") { [weak self] in self?.tab = "Домашняя сеть"; self?.openWindow() }
        row("Открыть пульт…","slider.horizontal.3") { [weak self] in self?.openWindow() }
        row("Диагностика…","terminal") { [weak self] in self?.tab = "События"; self?.openWindow() }
        row("+ Добавить профиль…") { [weak self] in self?.openWindow(); self?.importProfile() }
        row(updater.candidate.map { "Обновить до \($0.version)…" } ?? "Проверить обновления…","arrow.triangle.2.circlepath") { [weak self] in self?.checkUpdates() }
        divider(); row("Завершить…") { [weak self] in self?.quit() }
        y += 9; place(line(),1); y += 14
        let credit = label("powered by LENCHA_",size:11,color:Palette.dim)
        let signature = NSMutableAttributedString(string:credit.stringValue,attributes:[.font:credit.font!,.foregroundColor:Palette.dim])
        signature.addAttribute(.foregroundColor,value:Palette.red,range:(credit.stringValue as NSString).range(of:"LENCHA_")); credit.attributedStringValue = signature
        place(credit,18,21,250); y += 29
        view.frame.size.height = y; view.layoutSubtreeIfNeeded(); return view
    }
    func menuRevision() -> String {
        ([settings.mode.rawValue,status.phase.rawValue,status.message,status.network,status.profileID ?? "",settings.selectedID ?? "",String(status.guardActive),String(serviceAvailable),String(updater.candidate?.build ?? 0)] + settings.profiles.map { $0.id + $0.name }).joined(separator:"\u{1f}")
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
    func popoverDidClose(_ notification:Notification) { stopPopoverMonitoring() }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        let controller = NSViewController(); controller.view = menuView()
        popover.contentViewController = controller; popover.contentSize = controller.view.frame.size
        renderedMenuRevision = menuRevision()
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps:true)
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
    func titleForStatus() -> String { switch status.phase { case .setup:return "Начнём с профиля_"; case .home:return "Ты дома_"; case .connecting:return "Проверяем связь_"; case .connected:return "На связи_"; case .waiting:return "Ждём сеть_"; case .recovering:return "Держим VPN_"; case .off:return "Выключено вручную_"; case .error:return "Нужно внимание_" } }
    func guardDescription() -> String { if !serviceAvailable { return FileManager.default.fileExists(atPath:"/Library/LaunchDaemons/ru.hl100.autoturn.helper.plist") ? "Состояние службы и блокировки не подтверждено" : "VPN-служба ещё не установлена; интернет не изменён" }; return status.guardActive ? "Прямой трафик заблокирован" : "Блокировка прямого доступа выключена" }
    func selectedProfile() -> Profile? { settings.profiles.first { $0.id == settings.selectedID } ?? settings.profiles.first }
    func updateStatus() {
        if let title = connectionTitle { paintHeading(title,titleForStatus()) }; connectionMessage?.stringValue = status.message; connectionNetwork?.stringValue = status.network; connectionProfile?.stringValue = status.profileName ?? selectedProfile()?.name ?? "не выбран"; connectionGuard?.stringValue = guardDescription(); connectionGuard?.textColor = status.guardActive ? Palette.green : Palette.dim
        let modeName = settings.mode == .auto ? "АВТО" : settings.mode == .on ? "ВРУЧНУЮ" : "ВЫКЛЮЧЕНО"
        let phaseNames: [Phase:String] = [.setup:"НАСТРОЙКА",.home:"ДОМА",.connecting:"ПОДКЛЮЧЕНИЕ",.connected:"ПРОВЕРЕНО",.waiting:"ОЖИДАНИЕ",.recovering:"РЕЗЕРВ",.off:"ПАУЗА",.error:"ОШИБКА"]
        footer?.stringValue = "\(modeName) / \(phaseNames[status.phase] ?? "")"
        let symbol = status.phase == .connected ? "▪" : status.phase == .recovering || status.phase == .error ? "!" : status.phase == .home ? "⌂" : "·"
        statusItem.button?.title = " \(symbol)"; statusItem.button?.toolTip = "AutoTurn · \(status.message)"
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
    func command(_ command: String) { guard serviceAvailable else { showError(AppError.message("Сначала импортируй профиль и установи VPN-службу")); return }; busy = true; client.send(RPCRequest(command:command,settings:nil,network:nil)) { [weak self] result in self?.busy = false; self?.accept(result) } }
    func persistAndConfigure() {
        do { try Storage.save(settings) } catch { showError(error); return }
        buildPage()
        guard serviceAvailable else { return }; busy = true
        client.send(RPCRequest(command:"configure",settings:settings,network:observer.snapshot())) { [weak self] result in self?.busy = false; self?.accept(result); self?.observer.report() }
    }
    func setMode(_ mode: Mode) {
        if mode == .off && !liveNetworkTest && !confirm("Отключить VPN?",detail:"Вне дома интернет сможет идти напрямую. Автоматика будет выключена до возврата в Авто.") { return }
        guard mode == .off || !settings.profiles.isEmpty else { tab = "Профили"; openWindow(); return }
        settings.mode = mode; buildPage(); refreshOpenMenu()
        let snapshot = settings
        // Apply the user's network action before Keychain persistence. In particular,
        // Off must not depend on reading/validating profiles or an unlocked Keychain.
        busy = true
        let request = mode == .off ? RPCRequest(command:"stop",settings:nil,network:nil) : RPCRequest(command:"configure",settings:snapshot,network:observer.snapshot())
        client.send(request) { [weak self] result in
            guard let self = self else { return }
            self.accept(result); self.observer.report()
            do { try Storage.save(snapshot) } catch { self.info("Режим применён к службе, но настройки не сохранены: " + error.localizedDescription) }
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
    @objc func woke() { observer.report(); refresh(); checkAutomaticUpdates() }
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
        updateTimer = Timer(timeInterval:15*60,repeats:true) { [weak self] _ in self?.checkAutomaticUpdates() }
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
                self.updateHistory.succeeded(); self.refreshOpenMenu()
                if let release = release {
                    if manual { self.presentUpdate(release) }
                    else if self.updateHistory.shouldNotify(release.build) { self.notifyUpdate(release) }
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
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Доступен AutoTurn \(release.version)"
            content.body = "Нажми, чтобы открыть обновление. Профили и настройки сохранятся."
            let request = UNNotificationRequest(identifier:"autoturn-update-\(release.build)",content:content,trigger:nil)
            center.add(request) { error in if error == nil { DispatchQueue.main.async { self?.updateHistory.notified(release.build) } } }
        }
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner,.list]) }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping () -> Void) {
        DispatchQueue.main.async { self.openWindow(); self.checkUpdates() }; completionHandler()
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
    func confirm(_ title:String,detail:String) -> Bool { let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.addButton(withTitle:"Продолжить"); alert.addButton(withTitle:"Отмена"); return alert.runModal() == .alertFirstButtonReturn }
    func showError(_ error:Error) { info(error.localizedDescription) }
    func info(_ text:String) { let alert = NSAlert(); alert.messageText = "AutoTurn"; alert.informativeText = text; alert.addButton(withTitle:"OK"); alert.runModal() }
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
        let sample = Profile(name:"Резервный профиль с длинным названием",addresses:["10.0.0.2/32"],dns:["1.1.1.1"],mtu:1280,interface:[:],peer:[:],endpointHost:"198.51.100.10",endpointPort:51820,resolvedIP:"198.51.100.10")
        for profiles in [[],[sample,sample,sample]] {
            settings.profiles = profiles
            for width in [CGFloat(700),760,1000] {
                window.setContentSize(NSSize(width:width,height:700))
                for name in ["Соединение","Профили","Домашняя сеть","События"] {
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
            let menu = menuView(); menu.layoutSubtreeIfNeeded(); require(buttons(menu).contains { $0.title == "+ Добавить профиль…" },"menu import missing")
            require(menu.bounds.width == 292,"menu width differs from approved design")
            require(buttons(menu).contains { $0.title == "Диагностика…" && $0.menuIcon == "terminal" },"menu diagnostics missing")
            require(buttons(menu).filter { $0.profileSubtitle != nil }.count == profiles.count,"menu profile rows missing")
            for button in buttons(menu) {
                let frame = button.convert(button.bounds,to:menu)
                require(frame.minX >= 16 && frame.maxX <= 276.1 && frame.minY >= 0 && frame.maxY <= menu.bounds.height,"clipped menu action")
                if button.profileSubtitle != nil { require(frame.height == 50 && button.rowStyle,"menu profile layout") }
            }
            func checkCredits(_ view:NSView) { if let field = view as? NSTextField, field.stringValue.contains("LENCHA_") { let frame = field.convert(field.bounds,to:menu); require(frame.width > 40 && frame.maxX <= menu.bounds.width && frame.minX >= 0 && frame.minY >= 0,"clipped menu credit") }; view.subviews.forEach { checkCredits($0) } }
            checkCredits(menu)
        }
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
        print("UI checks passed: four tabs, profile layouts, open menu refresh without reopening, unchanged status preserves view, inside/outside clicks, monitor cleanup and file drop. No Keychain or network changes.")
        NSApp.terminate(nil)
    }
    func renderPreview() {
        status = ServiceStatus(phase:.setup,mode:.auto,profileID:nil,profileName:nil,network:"Проверка сети начнётся после настройки",message:"Импортируй AmneziaWG .conf и установи VPN-службу",guardActive:false,verifiedAt:nil,events:[],tunnel:nil)
        if let index = CommandLine.arguments.firstIndex(of:"--preview-tab"), index+1 < CommandLine.arguments.count { tab = CommandLine.arguments[index+1] }
        if CommandLine.arguments.contains("--preview-profiles") {
            settings.profiles = ["Основной","Резервный","Дальний"].map { Profile(name:$0,addresses:["10.0.0.2/32"],dns:["1.1.1.1"],mtu:1280,interface:[:],peer:[:],endpointHost:"198.51.100.10",endpointPort:51820,resolvedIP:"198.51.100.10") }; settings.selectedID = settings.profiles.first?.id
        }
        if CommandLine.arguments.contains("--preview-connected") {
            status = ServiceStatus(phase:.connected,mode:.auto,profileID:settings.selectedID,profileName:selectedProfile()?.name,network:"Другая Wi-Fi-сеть",message:"VPN подключён · связь проверена",guardActive:true,verifiedAt:Date(),events:[],tunnel:nil)
        }
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
if let index = CommandLine.arguments.firstIndex(of:"--ipc-test-client"), index+1 < CommandLine.arguments.count {
    do { let fd = try IPC.connect(CommandLine.arguments[index+1]); defer { close(fd) }; let answer = String(data:try IPC.readLine(fd:fd),encoding:.utf8); guard answer == "allowed" else { throw AppError.message("Client was rejected") }; print("Signed app IPC authentication passed; no settings or network changes"); exit(0) } catch { fputs("IPC authentication test failed\n",stderr); exit(1) }
}
let app = NSApplication.shared
let controller = Controller(); app.delegate = controller; app.run()
if controller.liveNetworkTest { exit(controller.testExitCode) }
