import AppKit

// Capture the status item's screen position once. A panel is not an attached
// child of the menu-bar window, so that window's auto-hide animation cannot
// drag the open menu off screen or switch the user's full-screen Space.
final class MenuPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender:Any?) { dismiss?() }
    var dismiss: (() -> Void)?
}
final class StableMenuPanel {
    let window: MenuPanelWindow
    var onClose: (() -> Void)?
    var contentViewController: NSViewController?
    private var screenFrame = NSRect.zero
    var contentSize = NSSize.zero {
        didSet {
            guard isShown else { return }
            let top = window.frame.maxY, right = window.frame.maxX
            installContent()
            position(right:right,top:top)
        }
    }
    var isShown: Bool { window.isVisible }
    init() {
        window = MenuPanelWindow(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.isOpaque = false
        window.backgroundColor = .clear; window.hasShadow = true
        window.level = .statusBar; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        window.animationBehavior = .none
        window.dismiss = { [weak self] in self?.performClose(nil) }
    }
    private func installContent() {
        guard let view = contentViewController?.view else { return }
        let height = min(contentSize.height,max(1,screenFrame.height-16))
        window.setContentSize(NSSize(width:contentSize.width,height:height))
        if height < contentSize.height {
            let scroll = NSScrollView(frame:NSRect(origin:.zero,size:NSSize(width:contentSize.width,height:height)))
            scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollsDynamically = true
            scroll.documentView = view; window.contentView = scroll
        } else { window.contentView = view }
    }
    private func position(right:CGFloat,top:CGFloat) {
        let size = window.frame.size
        let x = max(screenFrame.minX+8,min(right-size.width,screenFrame.maxX-size.width-8))
        let y = max(screenFrame.minY+8,min(top-size.height,screenFrame.maxY-size.height-8))
        window.setFrameOrigin(NSPoint(x:x,y:y))
    }
    func show(relativeTo rect:NSRect,of view:NSView,preferredEdge:NSRectEdge) {
        guard let anchorWindow = view.window, let screen = anchorWindow.screen ?? NSScreen.main else { return }
        let anchor = anchorWindow.convertToScreen(view.convert(rect,to:nil))
        screenFrame = screen.frame
        installContent(); position(right:anchor.maxX+8,top:anchor.minY-7)
        // Nonactivating panels receive clicks without bringing the main console
        // forward or activating another desktop when a different app is full screen.
        window.makeKeyAndOrderFront(nil)
    }
    func performClose(_ sender:Any?) {
        guard isShown else { return }
        window.orderOut(sender); onClose?()
    }
}
