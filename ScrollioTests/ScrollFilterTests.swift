//
//  ScrollFilterTests.swift
//  MosTests
//
//  ScrollFilter: a low-pass on the per-frame scroll distance.
//

import XCTest
@testable import Scrollio_Debug

final class ScrollFilterTests: XCTestCase {

    var sut: ScrollFilter!

    override func setUp() {
        super.setUp()
        sut = ScrollFilter()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial state and reset

    func testInitialValue_isZero() {
        let val = sut.value()
        XCTAssertEqual(val.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(val.x, 0.0, accuracy: 1e-10)
        XCTAssertEqual(sut.pending.y, 0.0)
        XCTAssertEqual(sut.pending.x, 0.0)
    }

    func testReset_clearsToZero() {
        _ = sut.fill(with: (y: 10.0, x: 5.0))
        sut.reset()
        let val = sut.value()
        XCTAssertEqual(val.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(val.x, 0.0, accuracy: 1e-10)
        XCTAssertEqual(sut.pending.y, 0.0)
        XCTAssertEqual(sut.pending.x, 0.0)
    }

    // MARK: - fill

    func testFill_firstCall_movesByTheWeightWithoutDelay() {
        let result = sut.fill(with: (y: 10.0, x: 0.0))
        XCTAssertEqual(result.y, 2.3, accuracy: 1e-10, "weight 0.23 of the way on the first frame")
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    func testFill_secondCall_advancesTowardTheInput() {
        _ = sut.fill(with: (y: 10.0, x: 0.0))
        let result = sut.fill(with: (y: 10.0, x: 0.0))
        XCTAssertEqual(result.y, 2.3 + 0.23 * 7.7, accuracy: 1e-10)
    }

    func testFill_customWeight() {
        XCTAssertEqual(sut.fill(with: (y: 10.0, x: -4.0), weight: 0.5).y, 5.0, accuracy: 1e-10)
        XCTAssertEqual(sut.value().x, -2.0, accuracy: 1e-10)
        XCTAssertEqual(sut.fill(with: (y: 10.0, x: -4.0), weight: 1).y, 10.0, accuracy: 1e-10, "weight 1 passes the input through")
        XCTAssertEqual(sut.fill(with: (y: 0.0, x: 0.0), weight: .nan).y, 0.0, accuracy: 1e-10, "an unusable weight does not smooth")
    }

    func testFill_convergesToTarget_afterMultipleCalls() {
        let target = 10.0
        var lastY = 0.0
        for _ in 0..<20 {
            let result = sut.fill(with: (y: target, x: 0.0))
            XCTAssertGreaterThanOrEqual(result.y, lastY, "value should be monotonically non-decreasing toward target")
            lastY = result.y
        }
        XCTAssertEqual(lastY, target, accuracy: 0.1, "after many fills, should converge close to target")
    }

    func testFill_xAxisIndependent() {
        _ = sut.fill(with: (y: 0.0, x: 20.0))
        let val = sut.value()
        XCTAssertEqual(val.y, 0.0, accuracy: 1e-10, "Y axis should remain at zero")
        XCTAssertEqual(val.x, 4.6, accuracy: 1e-10)
    }

    func testFill_negativeValues() {
        _ = sut.fill(with: (y: -10.0, x: -5.0))
        let val = sut.value()
        XCTAssertLessThan(val.y, 0.0, "negative fill should produce negative smoothed values")
        XCTAssertLessThan(val.x, 0.0, "negative fill should produce negative smoothed values")
    }

    func testFill_directionChange_smoothsTransition() {
        for _ in 0..<5 {
            _ = sut.fill(with: (y: 10.0, x: 0.0))
        }
        let beforeChange = sut.value().y
        _ = sut.fill(with: (y: -10.0, x: 0.0))
        let oneStepAfter = sut.value().y
        _ = sut.fill(with: (y: -10.0, x: 0.0))
        let twoStepsAfter = sut.value().y

        XCTAssertGreaterThan(beforeChange, 0.0)
        XCTAssertLessThan(oneStepAfter, beforeChange, "turns toward the new direction at once")
        XCTAssertGreaterThan(oneStepAfter, -10.0, "but not all the way")
        XCTAssertLessThan(twoStepsAfter, oneStepAfter)
    }

    func testFill_returnValue_matchesValue() {
        let fillResult = sut.fill(with: (y: 7.0, x: 3.0))
        let valueResult = sut.value()
        XCTAssertEqual(fillResult.y, valueResult.y, accuracy: 1e-10)
        XCTAssertEqual(fillResult.x, valueResult.x, accuracy: 1e-10)
    }

    // MARK: - No distance is lost

    func testPending_isWhatHasGoneInButNotOut() {
        var input = 0.0, output = 0.0
        for value in [10.0, 10, 4, 0, -3, 0, 0] {
            input += value
            output += sut.fill(with: (y: value, x: 0)).y
            XCTAssertEqual(sut.pending.y, input - output, accuracy: 1e-9)
        }
    }

    func testPending_drainsOnceTheInputStops() {
        var input = 0.0, output = 0.0
        for _ in 0..<5 {
            input += 10
            output += sut.fill(with: (y: 10, x: 0)).y
        }
        for _ in 0..<200 {
            output += sut.fill(with: (y: 0, x: 0)).y
        }
        XCTAssertEqual(output, input, accuracy: 1e-6)
        XCTAssertEqual(sut.pending.y, 0, accuracy: 1e-6)
    }

    // MARK: - A changing weight

    func testCatchUp_withAConstantWeightChangesNothing() {
        let plain = ScrollFilter()
        for value in [10.0, 10, 10, 4, 0, 0, -3] {
            let a = sut.fill(with: (y: value, x: 0), weight: 0.3, catchUp: 0.3)
            let b = plain.fill(with: (y: value, x: 0), weight: 0.3)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testCatchUp_releasesWhatAFasterWeightLeavesBehind_withoutAJump() {
        var input = 0.0, output = 0.0
        var last = 0.0
        for _ in 0..<40 {
            input += 10
            last = sut.fill(with: (y: 10, x: 0), weight: 0.2, catchUp: 0.2).y
            output += last
        }
        XCTAssertEqual(last, 10, accuracy: 0.01, "steady: output equals input")
        // The weight doubles: the filter now holds less than it took in.
        for _ in 0..<60 {
            input += 10
            let next = sut.fill(with: (y: 10, x: 0), weight: 0.4, catchUp: 0.2).y
            XCTAssertLessThan(next, last * 1.6, "the surplus comes out over several frames")
            output += next
            last = next
        }
        for _ in 0..<300 {
            output += sut.fill(with: (y: 0, x: 0), weight: 0.4, catchUp: 0.2).y
        }
        XCTAssertEqual(output, input, accuracy: 1e-3, "nothing lost")
    }

    func testCatchUp_neverTurnsTheMotionAround() {
        for _ in 0..<40 {
            _ = sut.fill(with: (y: 10, x: 0), weight: 0.5, catchUp: 0.3)
        }
        // The weight drops: the filter would hand out more than it took in.
        var output: [Double] = []
        for _ in 0..<200 {
            output.append(sut.fill(with: (y: 0, x: 0), weight: 0.1, catchUp: 0.3).y)
        }
        XCTAssertTrue(output.allSatisfy { $0 >= 0 }, "slows down, never moves backwards")
    }
}
