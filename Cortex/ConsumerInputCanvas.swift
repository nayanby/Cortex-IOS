import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit

// Consumer uses uniform, coalesced stylus samples rather than a textured brush.
// Publish the live path on every touch batch so the vector page renderer updates
// while the pencil moves, not only when PencilKit commits a completed stroke.
final class ConsumerInputCanvas:PKCanvasView {
    var widthScale:CGFloat = 1
    var markingMode:CortexInkMode = .pen
    var onInkChange:((ConsumerInputCanvas)->Void)?
    let history = UndoManager()
    private var base = PKDrawing()
    private var points:[PKStrokePoint] = []
    private var smoother = ConsumerStrokeSmoother()
    private var started:TimeInterval = 0
    private var timestamp = Date()
    private var activeTool:PKInkingTool?
    private lazy var consumerGesture = ConsumerStrokeGesture(canvas:self)
    override init(frame:CGRect) {
        super.init(frame:frame)
        drawingGestureRecognizer.isEnabled = false
        addGestureRecognizer(consumerGesture)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    func configureInput() {drawingGestureRecognizer.isEnabled = false}
    fileprivate func begin(_ touch:UITouch,event:UIEvent) {
        base = drawing;points = [];smoother.reset();started = touch.timestamp;timestamp = Date();activeTool = tool as? PKInkingTool
        append(touch,event:event)
    }
    fileprivate func append(_ touch:UITouch,event:UIEvent,final:Bool = false) {
        if markingMode == .eraser {
            let locations = (event.coalescedTouches(for:touch) ?? [touch]).map {$0.location(in:self)}
            let remaining = drawing.strokes.filter {stroke in
                let samples = stroke.path.interpolatedPoints(by:.distance(2))
                return !samples.contains {point in
                    let p = point.location.applying(stroke.transform)
                    return locations.contains {hypot(p.x-$0.x,p.y-$0.y) <= 11*widthScale}
                }
            }
            drawing = PKDrawing(strokes:remaining);onInkChange?(self);return
        }
        guard let activeTool else {return}
        for sample in event.coalescedTouches(for:touch) ?? [touch] {
            let location = sample.location(in:self)
            let point = markingMode == .underliner ? CGPoint(x:location.x,y:points.first?.location.y ?? location.y) : smoother.sample(location,time:sample.timestamp)
            if let previous = points.last,markingMode != .underliner,hypot(point.x-previous.location.x,point.y-previous.location.y)<0.35 {continue}
            let value = PKStrokePoint(location:point,timeOffset:max(0,sample.timestamp-started),size:CGSize(width:activeTool.width*widthScale,height:activeTool.width*widthScale),opacity:1,force:1,azimuth:0,altitude:.pi/2)
            if markingMode == .underliner && points.count>1 {points[1] = value} else {points.append(value)}
        }
        if final,markingMode != .underliner {
            let endpoint = smoother.finish(touch.location(in:self),time:touch.timestamp)
            if let previous = points.last,hypot(endpoint.x-previous.location.x,endpoint.y-previous.location.y)>0.01 {
                points.append(PKStrokePoint(location:endpoint,timeOffset:max(previous.timeOffset+0.001,touch.timestamp-started),size:previous.size,opacity:1,force:1,azimuth:0,altitude:.pi/2))
            }
        }
        guard !points.isEmpty else {return}
        let stroke = PKStroke(ink:activeTool.ink,path:PKStrokePath(controlPoints:points,creationDate:timestamp))
        drawing = PKDrawing(strokes:base.strokes+[stroke]);onInkChange?(self)
    }
    fileprivate func end(cancelled:Bool) {
        let before = base
        if cancelled {drawing = before;onInkChange?(self)}
        else {history.registerUndo(withTarget:self) {$0.restore(before)}}
        points = [];activeTool = nil
    }
    private func restore(_ value:PKDrawing) {
        let before = drawing;history.registerUndo(withTarget:self) {$0.restore(before)}
        drawing = value;onInkChange?(self)
    }
    func clearMarks() {restore(PKDrawing())}
}
private final class ConsumerStrokeGesture:UIGestureRecognizer {
    weak var canvas:ConsumerInputCanvas?
    private weak var tracked:UITouch?
    init(canvas:ConsumerInputCanvas) {
        self.canvas = canvas;super.init(target:nil,action:nil)
        cancelsTouchesInView = true;delaysTouchesBegan = false;delaysTouchesEnded = false
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) {
        guard tracked == nil,let canvas,let touch = touches.first else {state = .failed;return}
        guard canvas.drawingPolicy != .pencilOnly || touch.type == .pencil else {state = .failed;return}
        tracked = touch;state = .began;canvas.begin(touch,event:event)
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) {
        guard let touch = tracked,touches.contains(touch) else {return}
        canvas?.append(touch,event:event);state = .changed
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) {
        guard let touch = tracked,touches.contains(touch) else {return}
        canvas?.append(touch,event:event,final:true);canvas?.end(cancelled:false);state = .ended
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent) {canvas?.end(cancelled:true);state = .cancelled}
    override func reset() {tracked = nil;super.reset()}
}
