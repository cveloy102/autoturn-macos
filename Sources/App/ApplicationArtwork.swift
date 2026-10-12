import AppKit

// Load the bundle artwork directly: LaunchServices may retain the old placeholder.
enum ApplicationArtwork {
    static let icon: NSImage? = {
        guard let url = Bundle.main.url(forResource:"AutoTurn",withExtension:"icns"), let image = NSImage(contentsOf:url) else { return nil }
        image.isTemplate = false
        return image
    }()
    static func alert(title:String,detail:String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        if detail.count > 600 || detail.components(separatedBy:.newlines).count > 8 {
            // Bound the content, not the window: modal actions stay below the scroll area.
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1024,height:768)
            let width = min(440,max(240,screen.width-180))
            let height = min(280,max(100,screen.height-300))
            let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:width,height:height))
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.drawsBackground = false; scroll.borderType = .bezelBorder
            let text = NSTextView(frame:NSRect(x:0,y:0,width:width,height:height))
            text.isEditable = false; text.isSelectable = true; text.isRichText = false
            text.font = NSFont.systemFont(ofSize:13); text.textColor = .labelColor; text.drawsBackground = false
            text.textContainerInset = NSSize(width:8,height:8); text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.maxSize = NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
            text.textContainer?.widthTracksTextView = true; text.textContainer?.containerSize = NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
            text.string = detail; scroll.documentView = text; alert.accessoryView = scroll
        } else { alert.informativeText = detail }
        if let image = icon { alert.icon = image }
        return alert
    }
}
