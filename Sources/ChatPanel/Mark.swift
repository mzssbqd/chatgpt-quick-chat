import AppKit

enum Mark {
    // Two offset speech strokes around an opening, drawn on an 18-point grid.
    static func image(size: CGFloat, template: Bool) -> NSImage {
        let icon = NSImage(size: NSSize(width:size,height:size), flipped:false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.scale(by:rect.width / 18)
            transform.concat()
            if !template {
                NSColor(srgbRed:0.14,green:0.24,blue:0.29,alpha:1).setFill()
                NSBezierPath(roundedRect:NSRect(x:1,y:1,width:16,height:16),xRadius:3.8,yRadius:3.8).fill()
            }
            (template ? NSColor.black : .white).setStroke()
            let p = NSBezierPath()
            p.lineWidth = template ? 1.7 : 1.15
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to:NSPoint(x:4,y:7))
            p.line(to:NSPoint(x:4,y:12))
            p.curve(to:NSPoint(x:6,y:14),controlPoint1:NSPoint(x:4,y:13.3),controlPoint2:NSPoint(x:4.7,y:14))
            p.line(to:NSPoint(x:13,y:14))
            p.move(to:NSPoint(x:14,y:11))
            p.line(to:NSPoint(x:14,y:7))
            p.curve(to:NSPoint(x:12,y:5),controlPoint1:NSPoint(x:14,y:5.7),controlPoint2:NSPoint(x:13.3,y:5))
            p.line(to:NSPoint(x:9,y:5))
            p.line(to:NSPoint(x:6,y:3))
            p.move(to:NSPoint(x:7,y:9.5))
            p.line(to:NSPoint(x:11,y:9.5))
            p.stroke()
            return true
        }
        icon.isTemplate = template
        return icon
    }
    static func writePNG(to url:URL) throws {
        guard let data = image(size:1024,template:false).tiffRepresentation,
              let bitmap = NSBitmapImageRep(data:data),
              let png = bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to:url)
    }
}
