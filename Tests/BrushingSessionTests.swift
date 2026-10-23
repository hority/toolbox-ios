import XCTest
@testable import Toolbox

final class BrushingSessionTests: XCTestCase {
    func testStepCrossingZoneBoundarySplitsCredit() {
        var session = BrushingSession()
        session.advance(by: 0.9, brushing: false)
        for _ in 0..<188 { session.advance(by: 0.1, brushing: false) }
        session.advance(by: 0.5, brushing: true)
        XCTAssertEqual(session.activeTime[.upperRight] ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(session.activeTime[.upperFront] ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(session.currentZone, .upperFront)
    }

    func testFullyBrushedSessionFinishesWithThreeStars() {
        var session = BrushingSession()
        while !session.isFinished { session.advance(by: 0.1, brushing: true) }
        XCTAssertNil(session.currentZone)
        XCTAssertEqual(BrushingSession.stars(for: session.overallRatio), 3)
        session.advance(by: 1, brushing: true)
        XCTAssertEqual(session.elapsed, BrushingSession.totalDuration)
    }
}
