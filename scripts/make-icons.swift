import AppKit
import Foundation

let directory = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
func render(_ pixels:Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    let transform = NSAffineTransform(); transform.scale(by:CGFloat(pixels)/1024); transform.concat()
    NSColor(calibratedRed:16/255,green:16/255,blue:16/255,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:32,y:32,width:960,height:960),xRadius:216,yRadius:216).fill()
    // Android coordinates use a downward Y axis.
    let p = NSBezierPath()
    let vertices:[NSPoint] = [(252,756),(432,260),(592,260),(772,756),(634,756),(512,390),(390,756)].map { NSPoint(x:CGFloat($0.0),y:CGFloat(1024-$0.1)) }
    p.move(to:vertices[0]); for v in vertices.dropFirst() { p.line(to:v) }; p.close()
    NSColor(calibratedRed:232/255,green:228/255,blue:217/255,alpha:1).setFill(); p.fill()
    NSColor(calibratedRed:240/255,green:68/255,blue:62/255,alpha:1).setFill()
    NSRect(x:394,y:1024-650,width:236,height:86).fill()
    return bitmap.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to:directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size*2).write(to:directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
