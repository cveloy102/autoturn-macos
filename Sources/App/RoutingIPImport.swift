import AppKit

extension Controller {
    func importIPList(_ rule: RoutingRule) {
        popover.performClose(nil)
        let alert = ApplicationArtwork.alert(title:"IP-список для «\(rule.name)»",detail:"Добавим адреса к существующим доменам. Можно загрузить текстовый IP/CIDR-список или ip.list HydraRoute из файла либо по HTTPS-ссылке.")
        alert.addButton(withTitle:"Из файла…"); alert.addButton(withTitle:"По ссылке…"); alert.addButton(withTitle:"Отмена")
        let choice = alert.runModal()
        if choice == .alertFirstButtonReturn {
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size <= 700000 else { throw AppError.message("IP-список слишком большой") }
                applyIPList(try String(contentsOf:url,encoding:.utf8),to:rule)
            } catch { showError(error) }
        } else if choice == .alertSecondButtonReturn {
            let input = ApplicationArtwork.alert(title:"Загрузить IP-список",detail:"Прямая HTTPS-ссылка на текстовый список. Например, Raw-ссылка на GitHub. Адреса добавятся к «\(rule.name)».")
            let field = NSTextField(frame:NSRect(x:0,y:0,width:420,height:28)); field.placeholderString = "https://…/ip.list"; input.accessoryView = field; input.addButton(withTitle:"Загрузить"); input.addButton(withTitle:"Отмена")
            guard input.runModal() == .alertFirstButtonReturn else { return }; input.window.makeFirstResponder(nil)
            guard let url = URL(string:field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { info("Укажи прямую HTTPS-ссылку на список"); return }
            routingFeedback = "Загружаем IP-список…"; buildPage()
            var request = URLRequest(url:url); request.timeoutInterval = 20
            URLSession.shared.dataTask(with:request) { [weak self] data,response,error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let error = error { self.showError(error); return }
                    guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.url?.scheme == "https", let data = data, data.count <= 700000, let text = String(data:data,encoding:.utf8) else { self.info("Не удалось получить текстовый IP-список (до 700 КБ)"); return }
                    self.applyIPList(text,to:rule)
                }
            }.resume()
        }
    }
    func applyIPList(_ text: String,to rule: RoutingRule) {
        do {
            let blocks = try RoutingIPImport.parse(text)
            var chosen = blocks[0]
            if blocks.count > 1 {
                let alert = ApplicationArtwork.alert(title:"Выбери блок IP-списка",detail:"В HydraRoute-файле несколько групп. Добавим только выбранную к «\(rule.name)».")
                let menu = NSPopUpButton(frame:NSRect(x:0,y:0,width:420,height:28)); menu.addItems(withTitles:blocks.map { "\($0.name) · \($0.ranges.count) IP/подсетей" }); alert.accessoryView = menu; alert.addButton(withTitle:"Продолжить"); alert.addButton(withTitle:"Отмена")
                guard alert.runModal() == .alertFirstButtonReturn else { return }; chosen = blocks[menu.indexOfSelectedItem]
            }
            guard let index = settings.routing.rules.firstIndex(where: { $0.id == rule.id }) else { info("Правило уже удалено"); return }
            let existing = Set(settings.routing.rules[index].allIPRanges), incoming = Set(chosen.ranges).subtracting(existing)
            guard !incoming.isEmpty else { info("Все адреса из списка уже есть в этом правиле"); return }
            guard confirm("Добавить \(incoming.count) IP/подсетей к «\(rule.name)»?",detail:"Домены и текущие IP останутся. Новые адреса получат направление этого правила: \(settings.routing.rules[index].destination == .vpn ? "через VPN" : "напрямую").") else { return }
            var updated = settings.routing; updated.rules[index].ipRanges = Array(Set(updated.rules[index].ipRanges).union(incoming)).sorted()
            settings.routing = try updated.validated(); routingFeedback = "Добавлено IP/подсетей: \(incoming.count)"; persistRouting()
        } catch { showError(error) }
    }
}
