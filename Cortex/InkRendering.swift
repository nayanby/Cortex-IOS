import UIKit
import PencilKit
import PDFKit

// Render the stored strokes as vectors. The input canvas remains PencilKit so
// coalesced/predicted Apple Pencil samples and the existing drawing files survive.
enum ConsumerInkRenderer {
    struct Stroke {
        let path:CGPath
        let points:[CGPoint]
        let width:CGFloat
        let color:UIColor
        let wash:Bool
        let underliner:Bool
    }
    static func strokes(_ drawing:PKDrawing) -> [Stroke] {
        drawing.strokes.flatMap { stroke -> [Stroke] in
            let ranges = stroke.mask == nil ? [CGFloat(0)...CGFloat(max(0,stroke.path.count-1))] : stroke.maskedPathRanges
            return ranges.compactMap { range in
            let samples = Array(stroke.path.interpolatedPoints(in:range,by:.distance(0.8)))
            guard let first = samples.first else {return nil}
            let transform = stroke.transform
            let points = samples.map {$0.location.applying(transform)}
            let wash = stroke.ink.inkType == .marker
            var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
            stroke.ink.color.getRed(&r,green:&g,blue:&b,alpha:&a)
            let color = UIColor(red:r,green:g,blue:b,alpha:wash ? 1 : a)
            let hex = (Int((r*255).rounded())<<16) | (Int((g*255).rounded())<<8) | Int((b*255).rounded())
            let underline = [0xE89090,0xD4C04A,0xB1E5E6].contains(hex)
            let width = max(0.5,first.size.width * hypot(transform.a,transform.b))
            let path = CGMutablePath();path.move(to:points[0])
            for point in points.dropFirst() {path.addLine(to:point)}
            if points.count == 1 {path.addLine(to:CGPoint(x:points[0].x+0.01,y:points[0].y))}
            return Stroke(path:path,points:points,width:width,color:color,wash:wash,underliner:underline)
            }
        }
    }
    static func straightenLastStroke(_ drawing:PKDrawing) -> PKDrawing {
        guard let stroke = drawing.strokes.last,let first = stroke.path.first,let last = stroke.path.last else {return drawing}
        let endpoint = PKStrokePoint(location:CGPoint(x:last.location.x,y:first.location.y),timeOffset:max(0.001,last.timeOffset),size:first.size,opacity:first.opacity,force:first.force,azimuth:first.azimuth,altitude:first.altitude)
        let line = PKStroke(ink:stroke.ink,path:PKStrokePath(controlPoints:[first,endpoint],creationDate:stroke.path.creationDate),transform:stroke.transform)
        return PKDrawing(strokes:Array(drawing.strokes.dropLast())+[line])
    }
    static func draw(_ drawing:PKDrawing,in context:CGContext) {
        context.saveGState();context.setShouldAntialias(true);context.setAllowsAntialiasing(true)
        for stroke in strokes(drawing) {
            context.setBlendMode(stroke.wash ? .multiply : .normal)
            context.setStrokeColor(stroke.color.cgColor);context.setLineWidth(stroke.width)
            context.setLineCap(stroke.underliner ? .butt : .round);context.setLineJoin(.round)
            context.addPath(stroke.path);context.strokePath()
        }
        context.restoreGState()
    }
    static func webPayload(_ drawing:PKDrawing) -> [[String:Any]] {
        strokes(drawing).map {stroke in
            var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
            stroke.color.getRed(&r,green:&g,blue:&b,alpha:&a)
            return ["points":stroke.points.map {[Double($0.x),Double($0.y)]},"width":Double(stroke.width),
                    "color":String(format:"#%02X%02X%02X",Int((r*255).rounded()),Int((g*255).rounded()),Int((b*255).rounded())),
                    "wash":stroke.wash,"underliner":stroke.underliner]
        }
    }
}
final class ConsumerInkAnnotation: PDFAnnotation {
    var drawing = PKDrawing()
    var marksVisible = true
    override func draw(with box:PDFDisplayBox,in context:CGContext) {
        guard marksVisible else {return}
        context.saveGState()
        context.translateBy(x:bounds.minX,y:bounds.maxY);context.scaleBy(x:1,y:-1)
        ConsumerInkRenderer.draw(drawing,in:context)
        context.restoreGState()
    }
}
