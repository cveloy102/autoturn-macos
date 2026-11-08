import AppKit

extension Controller {
    func dnsPreferences() {
        page.addArrangedSubview(label("ЗАЩИТА DNS",size:11,color:Palette.dim))
        page.addArrangedSubview(label(settings.dns.providers.map(\.title).joined(separator:" → "),size:12))
        page.addArrangedSubview(label(status.dnsMessage ?? "Для защиты DNS обнови VPN-службу",size:11,color:Palette.dim))
        page.addArrangedSubview(ActionButton("Настроить DNS…") { [weak self] in self?.editDNSPreferences() })
        page.addArrangedSubview(label("При сбое VPN обычные сайты используют резервный зашифрованный DNS. Домены из VPN-правил ждут VPN. В режиме «Всё через VPN» прямой доступ закрыт. Дома без VPN работает DNS роутера.",size:11,color:Palette.dim))
        page.addArrangedSubview(line())
    }
    func editDNSPreferences() {
        popover.performClose(nil)
        let alert = NSAlert(); alert.messageText = "Защита DNS"
        alert.informativeText = "Серверы пробуются по порядку. Для подключения VPN и прямого резерва нужен хотя бы один DoH-сервер. Quad9 также блокирует известные вредоносные домены."
        alert.addButton(withTitle:"Сохранить"); alert.addButton(withTitle:"Отмена")
        let view = NSView(frame:NSRect(x:0,y:0,width:420,height:250))
        var selectors: [NSPopUpButton] = []
        for index in 0..<3 {
            let caption = NSTextField(labelWithString:index == 0 ? "Основной" : "Резерв \(index)")
            caption.frame = NSRect(x:0,y:216-index*38,width:105,height:22); view.addSubview(caption)
            let choice = NSPopUpButton(frame:NSRect(x:110,y:212-index*38,width:310,height:28))
            choice.addItem(withTitle:"Не использовать")
            choice.addItems(withTitles:DNSProvider.allCases.map(\.title))
            if index < settings.dns.providers.count, let selected = DNSProvider.allCases.firstIndex(of:settings.dns.providers[index]) { choice.selectItem(at:selected+1) }
            view.addSubview(choice); selectors.append(choice)
        }
        let urlLabel = NSTextField(labelWithString:"Свой DoH: HTTPS-адрес и IPv4 сервера")
        urlLabel.frame = NSRect(x:0,y:92,width:420,height:22); view.addSubview(urlLabel)
        let url = NSTextField(string:settings.dns.customURL); url.placeholderString = "https://dns.example/dns-query"
        url.frame = NSRect(x:0,y:58,width:420,height:26); view.addSubview(url)
        let ip = NSTextField(string:settings.dns.customIP); ip.placeholderString = "IPv4 — без обращения к DNS роутера"
        ip.frame = NSRect(x:0,y:22,width:420,height:26); view.addSubview(ip)
        alert.accessoryView = view
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var value = DNSSettings()
        value.providers = selectors.compactMap { $0.indexOfSelectedItem > 0 ? DNSProvider.allCases[$0.indexOfSelectedItem-1] : nil }
        value.customURL = url.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        value.customIP = ip.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        do {
            value = try value.validated()
            settings.dns = value; persistAndConfigure()
        } catch { showError(error) }
    }
}
