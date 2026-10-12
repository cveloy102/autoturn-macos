import AppKit

// Keep the selection separate from the filtered rows so typing does not lose checks.
final class RoutingPicker: NSView, NSSearchFieldDelegate {
    let search = NSSearchField(frame:.zero)
    let rows = NSStackView()
    let counter = NSTextField(labelWithString:"")
    let services: [CatalogService]
    let database: RoutingDatabase
    var selected = Set<String>()
    var custom = Set<String>()
    init(database: RoutingDatabase, query: String) {
        self.database = database; self.services = database.snapshot.catalog.services.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        super.init(frame:NSRect(x:0,y:0,width:440,height:410))
        search.frame = NSRect(x:0,y:374,width:440,height:28); search.placeholderString = "Сервис, домен или IP…"; search.stringValue = query; search.delegate = self
        addSubview(search)
        let scroll = NSScrollView(frame:NSRect(x:0,y:34,width:440,height:330)); scroll.hasVerticalScroller = true; scroll.drawsBackground = true; scroll.backgroundColor = Palette.panel
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 4; rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rows; rows.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive = true; addSubview(scroll)
        counter.frame = NSRect(x:0,y:0,width:440,height:24); counter.font = NSFont.monospacedSystemFont(ofSize:11,weight:.regular); addSubview(counter)
        updateRows()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:)") }
    func controlTextDidChange(_ notification:Notification) { updateRows() }
    func updateRows() {
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        let q = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let exact = database.find(q)?.id
        let filtered = services.filter { q.isEmpty || $0.id == exact || $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) || database.snapshot.services[$0.id]?.domains.contains(where: { $0.localizedCaseInsensitiveContains(q) }) == true }
        if !q.isEmpty && (Profile.isIP(q) || Profile.validCIDR(q) || (try? RoutingPolicy.normalizeDomain(q)) != nil) {
            let button = NSButton(checkboxWithTitle:"Своё правило: \(q)",target:self,action:#selector(toggleCustom(_:))); button.identifier = NSUserInterfaceItemIdentifier(q); button.state = custom.contains(q) ? .on : .off; rows.addArrangedSubview(button)
        }
        for service in filtered {
            let button = NSButton(checkboxWithTitle:service.name,target:self,action:#selector(toggleService(_:))); button.identifier = NSUserInterfaceItemIdentifier(service.id); button.state = selected.contains(service.id) ? .on : .off
            button.heightAnchor.constraint(equalToConstant:26).isActive = true; rows.addArrangedSubview(button)
        }
        if rows.arrangedSubviews.isEmpty { rows.addArrangedSubview(NSTextField(labelWithString:"Нет совпадений. Введи полный домен, например chatgpt.com.")) }
        updateCounter()
    }
    @objc func toggleService(_ sender:NSButton) { guard let id = sender.identifier?.rawValue else { return }; if sender.state == .on { selected.insert(id) } else { selected.remove(id) }; updateCounter() }
    @objc func toggleCustom(_ sender:NSButton) { guard let value = sender.identifier?.rawValue else { return }; if sender.state == .on { custom.insert(value) } else { custom.remove(value) }; updateCounter() }
    func updateCounter() { counter.stringValue = "Выбрано: \(selected.count + custom.count) · галочки сохраняются при поиске" }
}
