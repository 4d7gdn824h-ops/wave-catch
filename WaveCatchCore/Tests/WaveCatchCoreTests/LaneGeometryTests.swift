import XCTest
import WaveCatchCore

final class LaneGeometryTests: XCTestCase {
    func testUpperLanesArcDownFromTheWaveAndLowerLanesSkimTheSides() {
        for lane in Lane.allCases {
            for step in 0...8 {
                let sample = LaneGeometry.point(lane: lane, progress: Double(step) / 8)
                XCTAssertGreaterThan(sample.y, 0.16, "\(lane) stays clear of the top edge")
                XCTAssertLessThan(sample.y, 0.78, "\(lane) stays clear of the bottom edge")
                XCTAssertGreaterThan(sample.x, 0.12, "\(lane) stays clear of the left edge")
                XCTAssertLessThan(sample.x, 0.88, "\(lane) stays clear of the right edge")
                assertAwayFromCorners(sample, lane: lane)
            }
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
        XCTAssertLessThan(rightStart.y, rightEnd.y)

        let leftEdge = LaneGeometry.point(lane: .lowerLeft, progress: 0)
        let leftSpot = LaneGeometry.catchSpot(.lowerLeft)
        XCTAssertGreaterThan(leftEdge.x, 0.18)
        XCTAssertLessThan(leftEdge.x, 0.26)
        XCTAssertGreaterThan(leftSpot.x, leftEdge.x)
        XCTAssertLessThan(leftSpot.x, 0.36)
        XCTAssertLessThan(abs(leftEdge.y - leftSpot.y), 0.05)
        XCTAssertLessThan(leftSpot.y, 0.56)

        let rightEdge = LaneGeometry.point(lane: .lowerRight, progress: 0)
        let rightSpot = LaneGeometry.catchSpot(.lowerRight)
        XCTAssertGreaterThan(rightEdge.x, 0.74)
        XCTAssertLessThan(rightEdge.x, 0.82)
        XCTAssertLessThan(rightSpot.x, rightEdge.x)
        XCTAssertGreaterThan(rightSpot.x, 0.64)
        XCTAssertLessThan(abs(rightEdge.y - rightSpot.y), 0.05)
        XCTAssertLessThan(rightSpot.y, 0.56)
        assertLowerLanesClearTheCornerButtons()

        let anchor = LaneGeometry.surferAnchor
        XCTAssertEqual(anchor.x, 0.50, accuracy: 0.001)
        XCTAssertEqual(anchor.y, 0.50, accuracy: 0.001)
        assertCloserToCorner(.upperLeft, corner: (0, 0), than: anchor)
        assertCloserToCorner(.upperRight, corner: (1, 0), than: anchor)
        assertCloserToCorner(.lowerLeft, corner: (0, 1), than: anchor)
        assertCloserToCorner(.lowerRight, corner: (1, 1), than: anchor)
    }

    /// iPhone 15 Pro Max landscape points, and the insets that push a corner button
    /// furthest into the playfield. Both orientations are covered: the island can
    /// sit on either side, and this phone also insets both sides at once.
    private func assertLowerLanesClearTheCornerButtons() {
        let screens: [(CGFloat, CGFloat)] = [(932, 430), (956, 440)]
        let layouts: [(CGFloat, CGFloat, CGFloat)] = [
            (59, 59, 21),
            (59, 0, 21),
            (0, 59, 21),
        ]
        let side: CGFloat = 104
        let margin: CGFloat = 8
        let gap: CGFloat = 12
        let halfW: CGFloat = 44
        let halfH: CGFloat = 50
        let ringRadius: CGFloat = 70
        for (width, height) in screens {
            for (insetLeft, insetRight, insetBottom) in layouts {
                let buttons = [
                    CGRect(
                        x: insetLeft + margin,
                        y: height - insetBottom - margin - side,
                        width: side,
                        height: side
                    ),
                    CGRect(
                        x: width - insetRight - margin - side,
                        y: height - insetBottom - margin - side,
                        width: side,
                        height: side
                    ),
                ]
                for lane in [Lane.lowerLeft, Lane.lowerRight] {
                    for step in 0...16 {
                        let sample = LaneGeometry.point(lane: lane, progress: Double(step) / 16)
                        let centerX = CGFloat(sample.x) * width
                        let centerY = CGFloat(sample.y) * height
                        let item = CGRect(
                            x: centerX - halfW,
                            y: centerY - halfH,
                            width: halfW * 2,
                            height: halfH * 2
                        )
                        for button in buttons {
                            let keptClear = button.insetBy(dx: -gap, dy: -gap)
                            XCTAssertFalse(
                                item.intersects(keptClear),
                                "\(lane) at \(sample) overlaps a corner button on \(width)x\(height)"
                            )
                            if step == 16 {
                                let spot = CGRect(
                                    x: centerX - ringRadius,
                                    y: centerY - ringRadius,
                                    width: ringRadius * 2,
                                    height: ringRadius * 2
                                )
                                XCTAssertFalse(
                                    spot.intersects(keptClear),
                                    "\(lane) landing ring overlaps a corner button on \(width)x\(height)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func assertCloserToCorner(_ lane: Lane, corner: (Double, Double), than anchor: LaneGeometry.Point) {
        let spot = LaneGeometry.catchSpot(lane)
        XCTAssertLessThan(distanceSquared(spot, corner), distanceSquared(anchor, corner), "\(lane) landing sits nearer its corner than the surfer")
    }

    private func distanceSquared(_ point: LaneGeometry.Point, _ corner: (Double, Double)) -> Double {
        let dx = point.x - corner.0
        let dy = point.y - corner.1
        return dx * dx + dy * dy
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
