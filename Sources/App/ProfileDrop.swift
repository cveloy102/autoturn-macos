import AppKit

class ProfileDropView: NSView {
    static let legacyFiles = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    var dropped: (([URL]) -> Bool)?
    var showDropBorder = false
    private var draggingFile = false
    override init(frame:NSRect) { super.init(frame:frame); registerForDraggedTypes([.fileURL,Self.legacyFiles]) }
    required init?(coder:NSCoder) { fatalError() }
    func files(_ pasteboard:NSPasteboard) -> [URL] {
        var urls = pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        if urls.isEmpty, let paths = pasteboard.propertyList(forType:Self.legacyFiles) as? [String] { urls = paths.map { URL(fileURLWithPath:$0) } }
        var seen = Set<String>()
        return urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "conf" && seen.insert($0.standardizedFileURL.path).inserted }
    }
    func receive(_ pasteboard:NSPasteboard) -> Bool {
        draggingFile = false; needsDisplay = true
        let urls = files(pasteboard)
        guard !urls.isEmpty, let handler = dropped else { return false }
        return handler(urls)
    }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation {
        draggingFile = dropped != nil && !files(sender.draggingPasteboard).isEmpty; needsDisplay = true
        return draggingFile ? .copy : []
    }
    override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender:NSDraggingInfo?) { draggingFile = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender:NSDraggingInfo) -> Bool { dropped != nil && !files(sender.draggingPasteboard).isEmpty }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool { receive(sender.draggingPasteboard) }
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        if draggingFile || showDropBorder {
            (draggingFile ? Palette.red : Palette.line).setStroke()
            let path = NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:6,yRadius:6); path.lineWidth = draggingFile ? 3 : 1; path.stroke()
        }
    }
}

func profileDropZone(_ handler:@escaping ([URL]) -> Bool) -> NSView {
    let zone = ProfileDropView(frame:.zero); zone.showDropBorder = true; zone.dropped = handler
    zone.heightAnchor.constraint(equalToConstant:64).isActive = true
    let hint = label("Перетащи .conf сюда\nМожно добавить несколько профилей",size:11,color:Palette.dim)
    hint.alignment = .center; pin(hint,inside:zone,inset:10)
    return zone
}
