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
        alert.messageText = title; alert.informativeText = detail
        if let image = icon { alert.icon = image }
        return alert
    }
}
