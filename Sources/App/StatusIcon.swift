import AppKit

// Template artwork keeps the same stroke weight in light and dark menu bars.
enum StatusIcon: CaseIterable {
    case home, connected, connecting, error, off, unknown
    static func state(_ phase: Phase, missingLocation: Bool) -> StatusIcon {
        if missingLocation { return .unknown }
        switch phase {
        case .home: return .home
        case .connected: return .connected
        case .connecting, .waiting: return .connecting
        case .recovering, .error: return .error
        case .off: return .off
        case .setup: return .unknown
        }
    }
    var image: NSImage {
        let icon = self
        let image = NSImage(size: NSSize(width:18,height:18), flipped:true) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform(); transform.scale(by:0.9); transform.concat()
            NSColor.black.setStroke()
            func path(_ points: [NSPoint], close: Bool = false) {
                let p = NSBezierPath(); p.lineWidth = 1.6; p.lineCapStyle = .round; p.lineJoinStyle = .round
                guard let first = points.first else { return }
                p.move(to:first); for point in points.dropFirst() { p.line(to:point) }
                if close { p.close() }; p.stroke()
            }
            func point(_ x:CGFloat,_ y:CGFloat) -> NSPoint { NSPoint(x:x,y:y) }
            func shield() {
                let p = NSBezierPath(); p.lineWidth = 1.6; p.lineCapStyle = .round; p.lineJoinStyle = .round
                p.move(to:point(10,2.5)); p.line(to:point(17,5)); p.line(to:point(17,10))
                p.curve(to:point(10,18),controlPoint1:point(17,14),controlPoint2:point(14,16))
                p.curve(to:point(3,10),controlPoint1:point(6,16),controlPoint2:point(3,14))
                p.line(to:point(3,5)); p.close(); p.stroke()
            }
            switch icon {
            case .home:
                path([point(4.5,10.5),point(2.5,4.5)])
                path([point(15.5,10.5),point(17.5,4.5)])
                let body = NSBezierPath(roundedRect:NSRect(x:2.5,y:10.5,width:15,height:6),xRadius:1.5,yRadius:1.5)
                body.lineWidth = 1.6; body.stroke()
                path([point(5.5,13.5),point(6.5,13.5)]); path([point(9,13.5),point(10,13.5)])
            case .connected:
                shield(); path([point(6.5,10),point(9,12.5),point(13.5,7.5)])
            case .error:
                shield(); path([point(10,6.5),point(10,10.5)]); path([point(10,13.5),point(10,13.6)])
            case .off:
                shield(); path([point(5.5,14.5),point(14.5,5.5)])
            case .connecting:
                let p = NSBezierPath(); p.lineWidth = 1.6; p.lineCapStyle = .round
                p.move(to:point(16.5,8)); p.curve(to:point(4.5,5),controlPoint1:point(14.5,1),controlPoint2:point(7,1))
                p.line(to:point(2.5,7)); p.stroke(); path([point(2.5,3.5),point(2.5,7),point(6,7)])
                let q = NSBezierPath(); q.lineWidth = 1.6; q.lineCapStyle = .round
                q.move(to:point(3.5,12)); q.curve(to:point(15.5,15),controlPoint1:point(5.5,19),controlPoint2:point(13,19))
                q.line(to:point(17.5,13)); q.stroke(); path([point(17.5,16.5),point(17.5,13),point(14,13)])
            case .unknown:
                let circle = NSBezierPath(ovalIn:NSRect(x:2.5,y:2.5,width:15,height:15)); circle.lineWidth = 1.6; circle.stroke()
                let q = NSBezierPath(); q.lineWidth = 1.6; q.lineCapStyle = .round
                q.move(to:point(7.5,7.5)); q.curve(to:point(12.5,7.5),controlPoint1:point(7.5,4.2),controlPoint2:point(12.5,4.2))
                q.curve(to:point(10,11.5),controlPoint1:point(12.5,9.5),controlPoint2:point(10,9.5)); q.stroke()
                path([point(10,14),point(10,14.1)])
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
