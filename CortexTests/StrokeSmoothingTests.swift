import XCTest
import CoreGraphics
@testable import Cortex

final class StrokeSmoothingTests:XCTestCase {
    func testSmallAlternatingHandJitterIsReduced() {
        var smoother = ConsumerStrokeSmoother()
        let raw = (0..<240).map {CGPoint(x:Double($0)*0.7,y:$0%2 == 0 ? 0.45 : -0.45)}
        let filtered = raw.enumerated().map {smoother.sample($0.element,time:Double($0.offset)/120)}
        let rawEnergy = raw.suffix(120).reduce(0.0) {$0+Double($1.y*$1.y)}
        let filteredEnergy = filtered.suffix(120).reduce(0.0) {$0+Double($1.y*$1.y)}
        XCTAssertLessThan(filteredEnergy,rawEnergy*0.5,"Smoothing must reduce visible high-frequency hand jitter")
        XCTAssertEqual(filtered.first,raw.first,"The beginning of a stroke must stay under the tip")
    }
    func testFastWritingAndCornersKeepTipCloseAndFinishExactly() {
        var smoother = ConsumerStrokeSmoother()
        let samples = (0..<100).map {i in i<50 ? CGPoint(x:CGFloat(i*8),y:0) : CGPoint(x:392,y:CGFloat((i-49)*8))}
        for (i,point) in samples.enumerated() {
            let output = smoother.sample(point,time:Double(i)/120)
            XCTAssertLessThanOrEqual(hypot(output.x-point.x,output.y-point.y),1.601,"A smoother must not pull the pen far behind fast handwriting")
        }
        let end = CGPoint(x:392,y:408)
        XCTAssertEqual(smoother.finish(end,time:1),end,"Lifting the pen must preserve the exact endpoint")
        smoother.reset();XCTAssertEqual(smoother.sample(CGPoint(x:10,y:20),time:2),CGPoint(x:10,y:20))
    }
}
