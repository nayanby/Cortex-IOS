import CoreGraphics
import Foundation

// A causal, speed-adaptive filter: suppress small hand jitter at low speed,
// follow fast writing promptly, and never let the tip trail by more than 1.6 pt.
struct ConsumerStrokeSmoother {
    private var raw:CGPoint?
    private var filtered:CGPoint?
    private var timestamp:TimeInterval?
    private var speed:Double = 0
    let maximumLag:CGFloat = 1.6
    mutating func reset() {raw = nil;filtered = nil;timestamp = nil;speed = 0}
    mutating func sample(_ point:CGPoint,time:TimeInterval) -> CGPoint {
        guard point.x.isFinite,point.y.isFinite,time.isFinite else {return filtered ?? .zero}
        guard let previousRaw = raw,let previous = filtered,let previousTime = timestamp else {
            raw = point;filtered = point;timestamp = time;return point
        }
        let dt = min(1.0/20,max(1.0/240,time-previousTime))
        let measured = Double(hypot(point.x-previousRaw.x,point.y-previousRaw.y))/dt
        let speedAlpha = 1-exp(-2*Double.pi*16*dt)
        speed += speedAlpha*(measured-speed)
        let cutoff = 7 + 0.10*speed
        let alpha = CGFloat(1-exp(-2*Double.pi*cutoff*dt))
        var result = CGPoint(x:previous.x+alpha*(point.x-previous.x),y:previous.y+alpha*(point.y-previous.y))
        let dx = point.x-result.x,dy = point.y-result.y,distance = hypot(dx,dy)
        if distance>maximumLag {result = CGPoint(x:point.x-dx*maximumLag/distance,y:point.y-dy*maximumLag/distance)}
        raw = point;filtered = result;timestamp = time
        return result
    }
    mutating func finish(_ point:CGPoint,time:TimeInterval) -> CGPoint {
        guard point.x.isFinite,point.y.isFinite,time.isFinite else {return filtered ?? .zero}
        raw = point;filtered = point;timestamp = time;return point
    }
}
