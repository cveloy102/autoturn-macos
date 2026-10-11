import AppKit
import UniformTypeIdentifiers

enum RoutingAppearance: String, CaseIterable {
    case console, catalog, workshop
    var title: String { switch self { case .console:return "1 · Консоль"; case .catalog:return "2 · Каталог"; case .workshop:return "3 · Мастерская" } }
}
extension Controller {
    func routingPage() {
        page.addArrangedSubview(label("ROUTING / \(routingAppearance.rawValue.uppercased())",size:11,color:Palette.red))
        page.addArrangedSubview(heading("Маршруты_"))
        page.addArrangedSubview(label(settings.routing.mode == .all ? "Весь интернет через VPN. Правила сохранены для переключения." : "Всё напрямую. Через VPN — только выбранные сервисы, домены и IP.",size:11,color:Palette.dim))
        if !serviceAvailable && !preview { page.addArrangedSubview(ActionButton("Установить новую VPN-службу…",primary:true) { [weak self] in self?.installService() }) }
        let modes = stack(vertical:false,spacing:0)
        for (mode,title) in [(RoutingMode.all,"Всё через VPN"),(.rules,"По правилам")] {
            modes.addArrangedSubview(ActionButton(title,primary:settings.routing.mode == mode) { [weak self] in guard let self = self else { return }; self.settings.routing.mode = mode; self.persistRouting() })
        }
        page.addArrangedSubview(modes)
        let search = NSSearchField(); search.placeholderString = "Сервис или домен…"; search.stringValue = routingQuery; search.font = NSFont.monospacedSystemFont(ofSize:12,weight:.regular); search.target = self; search.action = #selector(routingSearchChanged(_:)); search.sendsSearchStringImmediately = true; search.translatesAutoresizingMaskIntoConstraints = false; search.widthAnchor.constraint(greaterThanOrEqualToConstant:120).isActive = true; search.setContentHuggingPriority(.init(1),for:.horizontal); routingSearch = search
        let toolbar = stack([search,ActionButton("+ Добавить",primary:true) { [weak self] in self?.addRoutingRule() }],vertical:false,spacing:10); page.addArrangedSubview(toolbar)
        let fileActions = stack([ActionButton("Импорт") { [weak self] in self?.importRoutes() },ActionButton("Экспорт") { [weak self] in self?.exportRoutes() }],vertical:false,spacing:8); page.addArrangedSubview(fileActions)
        let list = stack(spacing:routingAppearance == .catalog ? 12 : 0); routingList = list
        if settings.routing.rules.isEmpty {
            list.addArrangedSubview(label("Пока нет правил_",size:18)); list.addArrangedSubview(label("Добавь YouTube, Telegram или свой домен. Для сервиса приложение загрузит связанные домены из базы.",size:11,color:Palette.dim))
            list.addArrangedSubview(ActionButton("+ YouTube",primary:true) { [weak self] in self?.addRoutingRule(suggestion:"YouTube") })
            page.addArrangedSubview(list)
        } else {
            updateRoutingList()
            if let selected = settings.routing.rules.first(where: { $0.id == routingSelectedID }) ?? settings.routing.rules.first {
                routingSelectedID = selected.id
                let detail = routingDetail(selected)
                let narrow = consoleAppearance == .workspace || body.bounds.width < 640
                if routingAppearance == .catalog || narrow { page.addArrangedSubview(list); page.addArrangedSubview(detail) }
                else {
                    let columns = stack([list,detail],vertical:false,spacing:22); columns.alignment = .top
                    detail.widthAnchor.constraint(equalToConstant:routingAppearance == .workshop ? 330 : 290).isActive = true
                    list.setContentHuggingPriority(.init(1),for:.horizontal); page.addArrangedSubview(columns)
                }
            }
        }
        page.addArrangedSubview(line())
        page.addArrangedSubview(label("GEO-AGGREGATOR / БАЗА СЕРВИСОВ",size:11,color:Palette.dim))
        let date = settings.routing.databaseUpdatedAt.map { DateFormatter.localizedString(from:$0,dateStyle:.short,timeStyle:.short) } ?? "встроенный список"
        page.addArrangedSubview(label("Обновление: \(date)",size:11,color:Palette.dim))
        let update = ActionButton(routingBusy ? "Обновляем базы…" : "Обновить базы") { [weak self] in self?.refreshRoutingDatabase(manual:true) }; update.isEnabled = !routingBusy; page.addArrangedSubview(update)
        let automatic = NSButton(checkboxWithTitle:"Обновлять базу автоматически раз в сутки",target:self,action:#selector(toggleRoutingUpdates(_:))); automatic.state = settings.routing.automaticDatabaseUpdates ? .on : .off; page.addArrangedSubview(automatic)
        routingStatusLabel = label(routingFeedback.isEmpty ? "Дома работает роутер. Свои домены сохраняются при обновлении базы." : routingFeedback,size:11,color:Palette.dim); page.addArrangedSubview(routingStatusLabel!)
        page.addArrangedSubview(label("Доменные правила используют DNS приложения и доступное имя сайта. При защищённом DNS и скрытом имени работают IP-правила; остальное идёт напрямую.",size:11,color:Palette.dim))
    }
    @objc func routingSearchChanged(_ sender: NSSearchField) { routingQuery = sender.stringValue; updateRoutingList(); window.contentView?.needsLayout = true }
    @objc func toggleRoutingUpdates(_ sender: NSButton) { settings.routing.automaticDatabaseUpdates = sender.state == .on; persistRouting(); checkRoutingUpdates() }
    func updateRoutingList() {
        guard let list = routingList else { return }
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        let q = routingQuery.lowercased(), filtered = settings.routing.rules.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.allDomains.contains(where: { $0.contains(q) }) }
        if filtered.isEmpty { list.addArrangedSubview(label("Нет совпадений. Добавь сервис или свой домен.",size:11,color:Palette.dim)); return }
        if routingAppearance == .catalog {
            for start in stride(from:0,to:filtered.count,by:2) {
                let row = stack(vertical:false,spacing:10); row.distribution = .fillEqually; row.alignment = .top
                for rule in filtered[start..<min(start+2,filtered.count)] { row.addArrangedSubview(routingTile(rule)) }
                if start+1 >= filtered.count { row.addArrangedSubview(NSView()) }
                list.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:list.widthAnchor).isActive = true
            }
        } else {
            for rule in filtered {
                let button = ActionButton(rule.name,primary:rule.id == (routingSelectedID ?? settings.routing.rules.first?.id)) { [weak self] in self?.routingSelectedID = rule.id; self?.buildPage() }
                button.setContentCompressionResistancePriority(.defaultLow,for:.horizontal); button.rowStyle = true; button.profileSubtitle = rule.serviceID == nil ? "Своё правило" : "\(rule.allDomains.count) доменов"; button.profileState = !rule.enabled ? "Выкл." : rule.destination == .vpn ? "VPN" : "Прямо"; button.profileMark = rule.serviceID == nil ? "+" : "↗"; button.font = NSFont.monospacedSystemFont(ofSize:11,weight:.regular)
                list.addArrangedSubview(button); button.heightAnchor.constraint(equalToConstant:58).isActive = true; button.widthAnchor.constraint(equalTo:list.widthAnchor).isActive = true
            }
        }
    }
    func serviceSymbol(_ id: String?) -> String { switch id { case "youtube":return "play.rectangle"; case "telegram":return "paperplane"; case "github":return "chevron.left.forwardslash.chevron.right"; case "openai":return "sparkles"; case "discord":return "bubble.left.and.bubble.right"; default:return id == nil ? "globe" : "network" } }
    func routingTile(_ rule: RoutingRule) -> NSView {
        let card = NSView(); fill(card,color:Palette.panel); card.layer?.cornerRadius = 8; card.layer?.borderWidth = 1; card.layer?.borderColor = rule.id == routingSelectedID ? Palette.red.cgColor : Palette.line.cgColor
        let image = NSImageView(); image.image = NSImage(systemSymbolName:serviceSymbol(rule.serviceID),accessibilityDescription:rule.name); image.contentTintColor = rule.id == routingSelectedID ? Palette.red : Palette.ink; image.translatesAutoresizingMaskIntoConstraints = false; image.widthAnchor.constraint(equalToConstant:24).isActive = true; image.heightAnchor.constraint(equalToConstant:24).isActive = true
        let content = stack([image,ActionButton(rule.name) { [weak self] in self?.routingSelectedID = rule.id; self?.buildPage() },label(!rule.enabled ? "Выключено" : rule.destination == .vpn ? "Через VPN" : "Напрямую",size:11,color:rule.destination == .vpn ? Palette.green : Palette.dim)],spacing:8)
        content.arrangedSubviews[1].setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        pin(content,inside:card,inset:14); return card
    }
    func routingDetail(_ rule: RoutingRule) -> NSView {
        let card = NSView(); fill(card,color:Palette.panel); card.layer?.cornerRadius = routingAppearance == .workshop ? 2 : 7
        let detail = stack(spacing:11)
        let image = NSImageView(); image.image = NSImage(systemSymbolName:serviceSymbol(rule.serviceID),accessibilityDescription:rule.name); image.contentTintColor = Palette.red; image.translatesAutoresizingMaskIntoConstraints = false; image.widthAnchor.constraint(equalToConstant:24).isActive = true; image.heightAnchor.constraint(equalToConstant:24).isActive = true
        detail.addArrangedSubview(stack([image,label(rule.name,size:16)],vertical:false,spacing:10)); detail.addArrangedSubview(label(rule.serviceID == nil ? "Своё правило" : "Geo-Aggregator / \(rule.allDomains.count) доменов",size:11,color:Palette.dim))
        let modes = stack(vertical:body.bounds.width < 550,spacing:6)
        for (destination,title) in [(RouteDestination.vpn,"Через VPN"),(.direct,"Напрямую")] {
            let button = ActionButton(title,primary:rule.destination == destination) { [weak self] in guard let self = self, let index = self.settings.routing.rules.firstIndex(where: { $0.id == rule.id }) else { return }; self.settings.routing.rules[index].destination = destination; self.persistRouting() }; button.font = NSFont.monospacedSystemFont(ofSize:11,weight:.regular); modes.addArrangedSubview(button)
        }
        detail.addArrangedSubview(modes)
        detail.addArrangedSubview(label("ДОМЕНЫ / С ПОДДОМЕНАМИ",size:10,color:Palette.dim))
        if routingAppearance == .workshop {
            detail.addArrangedSubview(label("Из базы: \(rule.baseDomains.count). Ниже — свои дополнения.",size:11,color:Palette.dim))
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.heightAnchor.constraint(equalToConstant:130).isActive = true
            let text = NSTextView(); text.font = NSFont.monospacedSystemFont(ofSize:11,weight:.regular); text.backgroundColor = Palette.bg; text.textColor = Palette.ink; text.isRichText = false; text.string = (rule.domains+rule.ipRanges).joined(separator:"\n"); scroll.documentView = text; text.autoresizingMask = [.width]; text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true; detail.addArrangedSubview(scroll)
            detail.addArrangedSubview(ActionButton("Сохранить дополнения",primary:true) { [weak self] in self?.replaceManualRules(rule,text:text.string) })
        } else {
            detail.addArrangedSubview(label(rule.allDomains.prefix(8).joined(separator:"\n"),size:11))
            if rule.allDomains.count > 8 { detail.addArrangedSubview(label("Ещё \(rule.allDomains.count-8) · весь список в редакторе",size:11,color:Palette.dim)) }
            detail.addArrangedSubview(ActionButton("Редактировать дополнения…") { [weak self] in self?.editRoutingRule(rule) })
        }
        if !rule.allIPRanges.isEmpty { detail.addArrangedSubview(label("IP / подсети: \(rule.allIPRanges.count)",size:11,color:Palette.dim)); detail.addArrangedSubview(label(rule.allIPRanges.prefix(8).joined(separator:"\n"),size:11)) }
        detail.addArrangedSubview(label(rule.destination == .vpn ? "При сбое VPN этот трафик не выходит напрямую." : "Опознанные соединения идут напрямую.",size:11,color:Palette.dim))
        detail.addArrangedSubview(ActionButton(rule.enabled ? "Выключить правило" : "Включить правило") { [weak self] in guard let self = self, let index = self.settings.routing.rules.firstIndex(where: { $0.id == rule.id }) else { return }; self.settings.routing.rules[index].enabled.toggle(); self.persistRouting() })
        detail.addArrangedSubview(ActionButton("Удалить правило…") { [weak self] in guard let self = self, self.confirm("Удалить \(rule.name)?",detail:"Будет удалено только правило маршрутизации.") else { return }; self.settings.routing.rules.removeAll { $0.id == rule.id }; self.routingSelectedID = nil; self.persistRouting() })
        pin(detail,inside:card,inset:16); for v in detail.arrangedSubviews { v.widthAnchor.constraint(equalTo:detail.widthAnchor).isActive = true }; return card
    }
    func persistRouting() {
        do { settings.routing = try settings.routing.validated() } catch { showError(error); return }
        if preview { buildPage(); return }
        if serviceAvailable && status.routingProtocol != 2 && settings.routing.mode == .rules { info("Сначала установи обновлённую VPN-службу из этой версии приложения"); return }
        persistAndConfigure(); buildPage()
    }
    func addRoutingRule(suggestion: String? = nil) {
        let alert = ApplicationArtwork.alert(title:"Добавить сервис или домен",detail:"Выбери готовый сервис либо введи свой домен. Для сервиса загрузим весь список из Geo-Aggregator.")
        let combo = NSComboBox(frame:NSRect(x:0,y:0,width:370,height:28)); combo.addItems(withObjectValues:routingDatabase.snapshot.catalog.services.map { $0.name }); combo.stringValue = suggestion ?? routingQuery; combo.completes = true
        alert.accessoryView = combo; alert.addButton(withTitle:"Добавить"); alert.addButton(withTitle:"Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        alert.window.makeFirstResponder(nil)
        let value = combo.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        var selected = routingDatabase.find(value)
        if selected == nil && !value.contains(".") && !value.contains(":") && !value.contains("/") {
            let candidates = routingDatabase.snapshot.catalog.services.filter { $0.name.localizedCaseInsensitiveContains(value) || $0.id.localizedCaseInsensitiveContains(value) }
            if !candidates.isEmpty && !value.isEmpty {
                let picker = ApplicationArtwork.alert(title:"Выбери сервис",detail:"По запросу «\(value)» найдено \(candidates.count) сервисов.")
                let menu = NSPopUpButton(frame:NSRect(x:0,y:0,width:370,height:28)); menu.addItems(withTitles:candidates.map { $0.name }); picker.accessoryView = menu; picker.addButton(withTitle:"Добавить"); picker.addButton(withTitle:"Отмена")
                guard picker.runModal() == .alertFirstButtonReturn else { return }; selected = candidates[menu.indexOfSelectedItem]
            }
        }
        if let service = selected {
            if let existing = settings.routing.rules.first(where: { $0.serviceID == service.id }) { routingSelectedID = existing.id; tab = "Маршруты"; buildPage(); return }
            var rule = RoutingRule(name:service.name,serviceID:service.id,sourcePath:service.src)
            if let cached = routingDatabase.snapshot.services[service.id] { rule.baseDomains = cached.domains; appendRoutingRule(rule); return }
            guard !routingBusy else { info("Дождись завершения обновления базы"); return }
            routingBusy = true; routingFeedback = "Загружаем \(service.name)…"; buildPage()
            routingDatabase.refresh(rules:settings.routing.rules+[rule]) { [weak self] result in
                guard let self = self else { return }; self.routingBusy = false
                switch result { case .success(let snapshot): if let data = snapshot.services[service.id] { rule.baseDomains = data.domains; self.routingFeedback = "\(service.name) добавлен"; self.appendRoutingRule(rule) }; case .failure(let error):self.routingFeedback = "Сервис не добавлен: " + error.localizedDescription; if self.tab == "Маршруты" { self.buildPage() } }
            }
        } else {
            do {
                var rule = RoutingRule(name:value)
                if Profile.isIP(value) { rule.ipRanges = [value+(value.contains(":") ? "/128" : "/32")] }
                else if Profile.validCIDR(value) { rule.ipRanges = [value] }
                else { rule.domains = [try RoutingPolicy.normalizeDomain(value)] }
                appendRoutingRule(rule)
            } catch { showError(error) }
        }
    }
    func appendRoutingRule(_ rule: RoutingRule) {
        do { var updated = settings.routing; updated.rules.append(rule); settings.routing = try updated.validated(); routingSelectedID = rule.id; persistRouting() } catch { showError(error) }
    }
    func editRoutingRule(_ rule: RoutingRule) {
        let alert = ApplicationArtwork.alert(title:rule.name,detail:"Свои домены и IP-подсети — по одному на строке. Из базы: \(rule.baseDomains.count) доменов; обновление их не затронет твои дополнения.")
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:410,height:220)); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame:scroll.bounds); text.font = NSFont.monospacedSystemFont(ofSize:12,weight:.regular); text.isRichText = false; text.string = (rule.domains+rule.ipRanges).joined(separator:"\n"); text.autoresizingMask = [.width]; scroll.documentView = text
        alert.accessoryView = scroll; alert.addButton(withTitle:"Сохранить"); alert.addButton(withTitle:"Отмена"); if alert.runModal() == .alertFirstButtonReturn { replaceManualRules(rule,text:text.string) }
    }
    func replaceManualRules(_ rule: RoutingRule, text: String) {
        guard let index = settings.routing.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        do {
            var domains: [String] = [], ips: [String] = []
            for line in text.components(separatedBy:.newlines).map({ $0.trimmingCharacters(in:.whitespacesAndNewlines) }) where !line.isEmpty {
                if Profile.validCIDR(line) { ips.append(line) } else if Profile.isIP(line) { ips.append(line+(line.contains(":") ? "/128" : "/32")) } else { domains.append(try RoutingPolicy.normalizeDomain(line)) }
            }
            var updated = settings.routing; updated.rules[index].domains = Array(Set(domains)).sorted(); updated.rules[index].ipRanges = Array(Set(ips)).sorted(); settings.routing = try updated.validated(); persistRouting()
        } catch { showError(error) }
    }
    func importRoutes() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let routing = try RoutingExport.read(Data(contentsOf:url)); guard confirm("Импортировать \(routing.rules.count) правил?",detail:"Текущие правила будут заменены. VPN-профили и домашние сети сохранятся. Режим «всё через VPN» сохранится до явного переключения.") else { return }; var incoming = routing; incoming.mode = settings.routing.mode; settings.routing = incoming; routingSelectedID = nil; persistRouting() } catch { showError(error) }
    }
    func exportRoutes() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "AutoTurn-routes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; try encoder.encode(RoutingExport(routing:settings.routing)).write(to:url,options:.atomic) } catch { showError(error) }
    }
    func setupRoutingUpdates() {
        routingTimer = Timer(timeInterval:60,repeats:true) { [weak self] _ in self?.checkRoutingUpdates() }; RunLoop.main.add(routingTimer!,forMode:.common); checkRoutingUpdates()
    }
    func checkRoutingUpdates() {
        guard !preview, settings.routing.automaticDatabaseUpdates, !routingBusy else { return }
        let last = UserDefaults.standard.object(forKey:"routing.lastAttempt") as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= 86400 { refreshRoutingDatabase(manual:false) }
    }
    func refreshRoutingDatabase(manual: Bool) {
        guard !routingBusy else { return }; routingBusy = true; UserDefaults.standard.set(Date(),forKey:"routing.lastAttempt"); routingFeedback = "Обновляем каталог и списки сервисов…"; if tab == "Маршруты" { buildPage() }
        routingDatabase.refresh(rules:settings.routing.rules) { [weak self] result in
            guard let self = self else { return }; self.routingBusy = false
            switch result {
            case .success(let snapshot):
                var updated = self.settings.routing
                for index in updated.rules.indices { if let id = updated.rules[index].serviceID, let service = snapshot.services[id] { updated.rules[index].baseDomains = service.domains; updated.rules[index].baseIPRanges = nil; updated.rules[index].sourcePath = service.sourcePath } }
                do { updated.databaseUpdatedAt = snapshot.updatedAt; self.settings.routing = try updated.validated(); self.routingFeedback = "База актуальна. Свои дополнения сохранены."; if !self.preview { self.persistAndConfigure() } } catch { self.routingFeedback = "Правила сохранены без изменений: " + error.localizedDescription }
            case .failure(let error): self.routingFeedback = "Не удалось обновить базу; работает предыдущая. " + error.localizedDescription
            }
            if self.tab == "Маршруты" { self.buildPage() }
        }
    }
}
