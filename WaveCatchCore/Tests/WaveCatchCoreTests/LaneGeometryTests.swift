import XCTest
import WaveCatchCore

final class LaneGeometryTests: XCTestCase {
    func testUpperLanesArcDownFromTheWaveAndLowerLanesSkimTheSides() {
        for lane in Lane.allCases {
            var previous = LaneGeometry.point(lane: lane, progress: 0)
            for step in 0...8 {
                let sample = LaneGeometry.point(lane: lane, progress: Double(step) / 8)
                XCTAssertGreaterThan(sample.y, 0.12, "\(lane) stays clear of the top edge")
                XCTAssertLessThan(sample.y, 0.50, "\(lane) stays above the touch pad")
                XCTAssertGreaterThan(sample.x, 0.10, "\(lane) stays clear of the left edge")
                XCTAssertLessThan(sample.x, 0.90, "\(lane) stays clear of the right edge")
                assertAwayFromCorners(sample, lane: lane)
                previous = sample
            }
            _ = previous
        }

        let upperStart = LaneGeometry.point(lane: .upperLeft, progress: 0)
        let upperEnd = LaneGeometry.catchSpot(.upperLeft)
        XCTAssertLessThan(upperStart.y, upperEnd.y)
        let bowed = LaneGeometry.point(lane: .upperLeft, progress: 0.5)
        let chordX = (upperStart.x + upperEnd.x) / 2
        XCTAssertLessThan(bowed.x, chordX - 0.05)

        let rightStart = LaneGeometry.point(lane: .upperRight, progress: 0)
        let rightEnd = LaneGeometry.catchSpot(.upperRight)
        let rightBow = LaneGeometry.point(lane: .upperRight, progress: 0.5)
        XCTAssertGreaterThan(rightBow.x, (rightStart.x + rightEnd.x) / 2 + 0.05)

        let leftEdge = LaneGeometry.point(lane: .lowerLeft, progress: 0)
        let leftSpot = LaneGeometry.catchSpot(.lowerLeft)
        XCTAssertGreaterThan(leftEdge.x, 0.12)
        XCTAssertLessThan(leftEdge.x, 0.18)
        XCTAssertGreaterThan(leftSpot.x, 0.3)
        XCTAssertLessThan(abs(leftEdge.y - leftSpot.y), 0.05)
        XCTAssertGreaterThan(leftSpot.x, leftEdge.x)

        let rightEdge = LaneGeometry.point(lane: .lowerRight, progress: 0)
        let rightSpot = LaneGeometry.catchSpot(.lowerRight)
        XCTAssertGreaterThan(rightEdge.x, 0.82)
        XCTAssertLessThan(rightEdge.x, 0.88)
        XCTAssertLessThan(rightSpot.x, 0.7)
        XCTAssertLessThan(abs(rightEdge.y - rightSpot.y), 0.05)
    }

    private func assertAwayFromCorners(_ point: LaneGeometry.Point, lane: Lane) {
        let corners = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
        for corner in corners {
            let dx = point.x - corner.0
            let dy = point.y - corner.1
            XCTAssertGreaterThan(dx * dx + dy * dy, 0.02, "\(lane) passed near a corner")
        }
    }
}
