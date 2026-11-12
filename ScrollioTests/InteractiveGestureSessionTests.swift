import XCTest
@testable import Scrollio_Debug

/// The "follow the hand" state machine: axis lock, progress, release and the guarantee that
/// a swipe that began gets exactly one terminal command.
final class InteractiveGestureSessionTests: XCTestCase {

    private typealias Session = InteractiveGestureSession
    private typealias Command = InteractiveGestureSession.Command

    /// 1000 pt of travel = progress 1; one Space = progress 1.
    private func configuration(
        invert: Bool = false,
        progressPerPoint: Double = 0.001,
        maximumProgress: Double = 1
    ) -> Session.Configuration {
        Session.Configuration(
            progressPerPoint: progressPerPoint,
            maximumProgress: maximumProgress,
            invertHorizontal: invert
        )
    }

    private enum Step {
        case move(CGFloat, CGFloat, at: TimeInterval)
        case release(at: TimeInterval, pending: CGPoint = .zero)
        case cancel
        case expire
    }

    private func run(_ steps: [Step], configuration: Session.Configuration? = nil) -> (commands: [Command], session: Session) {
        var session = Session(configuration: configuration ?? self.configuration(), startTime: 0)
        var commands: [Command] = []
        for step in steps {
            switch step {
            case .move(let dx, let dy, let time):
                commands += session.move(deltaX: dx, deltaY: dy, at: time)
            case .release(let time, let pending):
                commands += session.release(pendingDeltaX: pending.x, pendingDeltaY: pending.y, at: time)
            case .cancel:
                commands += session.cancel()
            case .expire:
                commands += session.expire()
            }
        }
        return (commands, session)
    }

    /// Compares command lists with a tolerance on the numbers.
    private func assertCommands(
        _ actual: [Command],
        _ expected: [Command],
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, "\(name): \(actual)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            switch (a, e) {
            case (.update(let x), .update(let y)):
                XCTAssertEqual(x, y, accuracy: 1e-9, "\(name): \(actual)", file: file, line: line)
            case (.end(let x), .end(let y)):
                XCTAssertEqual(x, y, accuracy: 1e-6, "\(name): \(actual)", file: file, line: line)
            default:
                XCTAssertEqual(a, e, "\(name): \(actual)", file: file, line: line)
            }
        }
    }

    // MARK: - Sequences

    func testSequencesProduceExpectedCommands() {
        let cases: [(name: String, configuration: Session.Configuration, steps: [Step], expected: [Command])] = [
            (
                "click: no movement",
                configuration(),
                [.release(at: 0.1)],
                [.click]
            ),
            (
                "click: jitter below the lock distance",
                configuration(),
                [.move(3, -2, at: 0.01), .move(-2, 3, at: 0.02), .release(at: 0.1)],
                [.click]
            ),
            (
                "no click: wandered diagonally past the click tolerance without locking",
                configuration(),
                [.move(12, 12, at: 0.01), .release(at: 0.1)],
                []
            ),
            (
                "below 8 pt nothing locks",
                configuration(),
                [.move(-7, 0, at: 0.01)],
                []
            ),
            (
                "hand left brings in the next Space; progress starts with the locking movement",
                configuration(),
                [.move(-5, 0, at: 0.01), .move(-5, 0, at: 0.02), .move(-90, 0, at: 0.03)],
                [.begin(.horizontal), .update(0.005), .update(0.095)]
            ),
            (
                "hand right goes to the previous Space",
                configuration(),
                [.move(20, 0, at: 0.01), .move(30, 0, at: 0.02)],
                [.begin(.horizontal), .update(-0.02), .update(-0.05)]
            ),
            (
                "invert left and right flips the swipe",
                configuration(invert: true),
                [.move(-20, 0, at: 0.01), .move(-30, 0, at: 0.02)],
                [.begin(.horizontal), .update(-0.02), .update(-0.05)]
            ),
            (
                "diagonal waits, then the dominant axis locks",
                configuration(),
                [.move(10, 9, at: 0.01), .move(10, 0, at: 0.02)],
                [.begin(.horizontal), .update(-0.01)]
            ),
            (
                "vertical movement after a horizontal lock is ignored",
                configuration(),
                [.move(-20, 0, at: 0.01), .move(0, -200, at: 0.02), .move(-10, 0, at: 0.03)],
                [.begin(.horizontal), .update(0.02), .update(0.03)]
            ),
            (
                "release while still moving outward ends with the velocity of the last 80 ms",
                configuration(),
                [.move(-100, 0, at: 0.00), .move(-100, 0, at: 0.04), .move(-100, 0, at: 0.08), .release(at: 0.08)],
                // 0.2 of progress in the 80 ms before the release.
                [.begin(.horizontal), .update(0.1), .update(0.2), .update(0.3), .end(velocity: 2.5)]
            ),
            (
                "release after a pause ends with zero velocity and lets macOS decide",
                configuration(),
                [.move(-300, 0, at: 0.0), .release(at: 0.5)],
                [.begin(.horizontal), .update(0.3), .end(velocity: 0)]
            ),
            (
                "moving back before the release cancels",
                configuration(),
                [.move(-300, 0, at: 0.0), .move(40, 0, at: 0.30), .release(at: 0.31)],
                [.begin(.horizontal), .update(0.3), .update(0.26), .cancel]
            ),
            (
                "an old reversal does not cancel once the hand moves outward again",
                configuration(),
                [.move(-300, 0, at: 0.0), .move(40, 0, at: 0.1), .move(-20, 0, at: 0.5), .release(at: 0.5)],
                [.begin(.horizontal), .update(0.3), .update(0.26), .update(0.28), .end(velocity: 0.25)]
            ),
            (
                "back at the origin cancels",
                configuration(),
                [.move(-50, 0, at: 0.0), .move(50, 0, at: 0.2), .release(at: 1.0)],
                [.begin(.horizontal), .update(0.05), .update(0), .cancel]
            ),
            (
                "movement that arrives with the release decides the direction but is not sent",
                configuration(),
                [.move(-300, 0, at: 0.0), .release(at: 0.3, pending: CGPoint(x: 30, y: 0))],
                [.begin(.horizontal), .update(0.3), .cancel]
            ),
            (
                "progress saturates at one Space and turning back responds at once",
                configuration(),
                [.move(-900, 0, at: 0.0), .move(-900, 0, at: 0.1), .move(-500, 0, at: 0.2), .move(100, 0, at: 0.3)],
                [.begin(.horizontal), .update(0.9), .update(1), .update(0.9)]
            ),
            (
                "pushing against the limit still ends towards the next Space",
                configuration(),
                [.move(-900, 0, at: 0.0), .move(-900, 0, at: 0.1), .move(-80, 0, at: 0.5), .release(at: 0.5)],
                [.begin(.horizontal), .update(0.9), .update(1), .end(velocity: 1)]
            ),
            (
                "vertical lock: the up action fires once at 40 pt, like the classic mode",
                configuration(),
                [.move(0, -10, at: 0.01), .move(0, -20, at: 0.02), .move(0, -15, at: 0.03), .move(0, -100, at: 0.04), .release(at: 0.1)],
                [.discrete(.up)]
            ),
            (
                "vertical lock in one big movement",
                configuration(),
                [.move(0, 45, at: 0.01), .release(at: 0.1)],
                [.discrete(.down)]
            ),
            (
                // It did nothing at all, however far the hand went: the first 8 pt decided
                // the whole hold, and the jolt of pressing the button is enough for those.
                "vertical lock, then clearly sideways: a swipe after all",
                configuration(),
                [.move(0, -10, at: 0.01), .move(-200, 0, at: 0.02), .release(at: 0.1)],
                [.begin(.horizontal), .update(0.2), .end(velocity: 0)]
            ),
            (
                "vertical lock that barely moved is still a click",
                configuration(),
                [.move(0, -9, at: 0.01), .release(at: 0.1)],
                [.click]
            ),
            (
                "vertical action that arrives with the release still fires",
                configuration(),
                [.move(0, -10, at: 0.01), .release(at: 0.1, pending: CGPoint(x: 0, y: -40))],
                [.discrete(.up)]
            ),
            (
                "cancel while armed does nothing; later input is ignored",
                configuration(),
                [.cancel, .move(-100, 0, at: 0.1), .release(at: 0.2)],
                []
            ),
            (
                "cancel mid-swipe reverts once; later input is ignored",
                configuration(),
                [.move(-100, 0, at: 0.0), .cancel, .cancel, .move(-100, 0, at: 0.1), .release(at: 0.2)],
                [.begin(.horizontal), .update(0.1), .cancel]
            ),
            (
                "watchdog timer mid-swipe cancels",
                configuration(),
                [.move(-100, 0, at: 0.0), .expire, .release(at: 11)],
                [.begin(.horizontal), .update(0.1), .cancel]
            ),
            (
                "movement after the watchdog timeout cancels without a timer",
                configuration(),
                [.move(-100, 0, at: 1), .move(-100, 0, at: 10), .move(-100, 0, at: 10.1), .release(at: 10.2)],
                [.begin(.horizontal), .update(0.1), .cancel]
            ),
            (
                "a release after the timeout cancels instead of ending",
                configuration(),
                [.move(-100, 0, at: 1), .release(at: 10)],
                [.begin(.horizontal), .update(0.1), .cancel]
            ),
            (
                "a hold that timed out while armed neither swipes nor clicks",
                configuration(),
                [.move(-100, 0, at: 10), .release(at: 10.1)],
                []
            ),
            (
                "tracking scale: 2x speed on a narrower Space",
                configuration(progressPerPoint: 0.004, maximumProgress: 1.5),
                [.move(-100, 0, at: 0.0), .move(-400, 0, at: 0.1)],
                [.begin(.horizontal), .update(0.4), .update(1.5)]
            ),
        ]

        for testCase in cases {
            let result = run(testCase.steps, configuration: testCase.configuration)
            assertCommands(result.commands, testCase.expected, testCase.name)
        }
    }

    /// The lock is decided on the first 8 pt, and the jolt of pressing a thumb button is
    /// enough to make those vertical. Such a hold did nothing sideways, however far the hand
    /// went, until the button was released and pressed again.
    func testAHoldLockedVerticalByAJoltThatThenGoesSidewaysBecomesASwipe() {
        // 9 pt down (the jolt), then to the left.
        var session = Session(configuration: configuration(), startTime: 0)
        XCTAssertEqual(session.move(deltaX: 0, deltaY: 9, at: 0.01), [])
        XCTAssertEqual(session.phase, .discrete)
        XCTAssertEqual(session.move(deltaX: -20, deltaY: 0, at: 0.02), [], "not yet a direction")
        XCTAssertEqual(session.phase, .discrete)
        // 40 pt and clearly sideways: the swipe begins with this movement (no jump by the 20 pt before).
        let commands = session.move(deltaX: -30, deltaY: 0, at: 0.03)
        XCTAssertEqual(commands.first, .begin(.horizontal))
        XCTAssertEqual(commands.count, 2)
        guard case .update(let progress)? = commands.last else { return XCTFail("\(commands)") }
        XCTAssertEqual(progress, 0.03, accuracy: 1e-9)
        XCTAssertEqual(session.phase, .swiping)
        // From here it is an ordinary swipe with exactly one terminal command.
        XCTAssertEqual(session.move(deltaX: -100, deltaY: 0, at: 0.05).count, 1)
        let end = session.release(at: 0.06)
        XCTAssertEqual(end.count, 1)
        XCTAssertTrue(end[0].isSwipeCommand)
        XCTAssertEqual(session.phase, .finished)
    }

    /// A hold that really is vertical keeps its action, once, and never swipes afterwards.
    func testAVerticalHoldStillRunsItsActionAndDoesNotSwipeAfterwards() {
        var session = Session(configuration: configuration(), startTime: 0)
        XCTAssertEqual(session.move(deltaX: 0, deltaY: -9, at: 0.01), [])
        XCTAssertEqual(session.move(deltaX: 0, deltaY: -40, at: 0.02), [.discrete(.up)])
        // Sideways after the action ran: nothing more (one direction per hold).
        XCTAssertEqual(session.move(deltaX: -200, deltaY: 0, at: 0.03), [])
        XCTAssertEqual(session.phase, .discrete)
        XCTAssertEqual(session.release(at: 0.04), [])
    }

    func testLockNeedsTheDominanceRatio() {
        // 10 across, 9 down: 10 < 9 * 1.2, so neither axis wins yet.
        var session = Session(configuration: configuration(), startTime: 0)
        XCTAssertEqual(session.move(deltaX: 10, deltaY: 9, at: 0.01), [])
        XCTAssertEqual(session.phase, .armed)
        // 13 across, 10 down: 13 >= 10 * 1.2.
        XCTAssertEqual(session.move(deltaX: 3, deltaY: 1, at: 0.02).first, .begin(.horizontal))
        XCTAssertEqual(session.phase, .swiping)
    }

    func testPhasesFollowTheHold() {
        var swipe = Session(configuration: configuration(), startTime: 0)
        XCTAssertEqual(swipe.phase, .armed)
        _ = swipe.move(deltaX: -20, deltaY: 0, at: 0.01)
        XCTAssertEqual(swipe.phase, .swiping)
        XCTAssertEqual(swipe.progress, 0.02, accuracy: 1e-9)
        _ = swipe.release(at: 0.02)
        XCTAssertEqual(swipe.phase, .finished)

        var vertical = Session(configuration: configuration(), startTime: 0)
        _ = vertical.move(deltaX: 0, deltaY: 9, at: 0.01)
        XCTAssertEqual(vertical.phase, .discrete)
        _ = vertical.cancel()
        XCTAssertEqual(vertical.phase, .finished)
    }

    func testVelocityOfAYoungSwipeUsesItsOwnAge() {
        // Locked 40 ms before the release: 0.1 of progress in 0.04 s.
        let result = run([.move(-50, 0, at: 1.00), .move(-50, 0, at: 1.04), .release(at: 1.04)])
        assertCommands(
            result.commands,
            [.begin(.horizontal), .update(0.05), .update(0.1), .end(velocity: 2.5)],
            "young swipe"
        )
    }

    func testVelocityStaysFiniteWhenLockAndReleaseCoincide() {
        let result = run([.release(at: 0.5, pending: CGPoint(x: -600, y: 0))])
        guard case .end(let velocity)? = result.commands.last else {
            return XCTFail("expected an end, got \(result.commands)")
        }
        XCTAssertTrue(velocity.isFinite)
        XCTAssertGreaterThan(velocity, 0)
        XCTAssertEqual(Array(result.commands.dropLast()), [.begin(.horizontal), .update(0.6)])
    }

    // MARK: - Invariants

    /// Deterministic generator (SplitMix64), so a failure can be replayed from its seed.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testFuzzedHoldsAlwaysFormOneWellFormedSwipe() {
        for seed in UInt64(1)...400 {
            var generator = SeededGenerator(state: seed)
            let limit = Double.random(in: 0.5...2, using: &generator)
            var session = Session(
                configuration: configuration(
                    invert: Bool.random(using: &generator),
                    progressPerPoint: Double.random(in: 0.0002...0.01, using: &generator),
                    maximumProgress: limit
                ),
                startTime: 0
            )
            var commands: [Command] = []
            var time: TimeInterval = 0
            let stepCount = Int.random(in: 0...60, using: &generator)
            for _ in 0..<stepCount {
                time += Double.random(in: 0...0.4, using: &generator)
                switch Int.random(in: 0..<40, using: &generator) {
                case 0:
                    commands += session.cancel()
                case 1:
                    commands += session.expire()
                case 2:
                    commands += session.release(
                        pendingDeltaX: CGFloat(Int.random(in: -30...30, using: &generator)),
                        pendingDeltaY: CGFloat(Int.random(in: -30...30, using: &generator)),
                        at: time
                    )
                default:
                    // Mostly sideways, sometimes vertical or still.
                    let horizontal = Int.random(in: 0..<4, using: &generator) != 0
                    commands += session.move(
                        deltaX: CGFloat(Int.random(in: horizontal ? -60...60 : -3...3, using: &generator)),
                        deltaY: CGFloat(Int.random(in: horizontal ? -3...3 : -60...60, using: &generator)),
                        at: time
                    )
                }
            }
            // Every hold ends: a release, or the cancel path.
            commands += Bool.random(using: &generator) ? session.release(at: time) : session.cancel()
            XCTAssertEqual(session.phase, .finished, "seed \(seed)")
            XCTAssertEqual(session.release(at: time + 1), [], "seed \(seed): input after the end")
            XCTAssertEqual(session.move(deltaX: -50, deltaY: 0, at: time + 1), [], "seed \(seed): input after the end")

            assertWellFormed(commands, limit: limit, seed: seed)
        }
    }

    private func assertWellFormed(_ commands: [Command], limit: Double, seed: UInt64) {
        var begins = 0
        var terminals = 0
        var isOpen = false
        var actions = 0
        for command in commands {
            switch command {
            case .begin:
                XCTAssertEqual(begins, 0, "seed \(seed): a hold begins at most one swipe")
                begins += 1
                isOpen = true
            case .update(let progress):
                XCTAssertTrue(isOpen, "seed \(seed): update outside began ... terminal")
                XCTAssertTrue(progress.isFinite, "seed \(seed)")
                XCTAssertLessThanOrEqual(abs(progress), limit + 1e-12, "seed \(seed): progress past the limit")
            case .end(let velocity):
                XCTAssertTrue(isOpen, "seed \(seed): end without a began")
                XCTAssertTrue(velocity.isFinite, "seed \(seed)")
                terminals += 1
                isOpen = false
            case .cancel:
                XCTAssertTrue(isOpen, "seed \(seed): cancel without a began")
                terminals += 1
                isOpen = false
            case .discrete(let direction):
                XCTAssertTrue(direction == .up || direction == .down, "seed \(seed): sideways action")
                actions += 1
            case .click:
                actions += 1
            }
        }
        XCTAssertFalse(isOpen, "seed \(seed): swipe left open")
        XCTAssertEqual(terminals, begins, "seed \(seed): exactly one terminal per began")
        XCTAssertLessThanOrEqual(actions, 1, "seed \(seed): at most one discrete action or click per hold")
        if begins > 0 {
            XCTAssertEqual(actions, 0, "seed \(seed): a swipe never also runs an action")
        }
    }

    // MARK: - Pointer-freeze warp compensation

    private let anchor = CGPoint(x: 500.4, y: 300.7)

    func testWarpCompensatorLeavesDeltasAloneWhileThePointerStaysOnTheAnchor() {
        var compensator = MouseGestureWarpDeltaCompensator()
        for delta in [CGPoint(x: -12, y: 1), CGPoint(x: -15, y: 0), CGPoint(x: 0, y: 0)] {
            XCTAssertEqual(compensator.physicalDelta(delta, location: CGPoint(x: 500, y: 300), anchor: anchor), delta)
        }
    }

    func testWarpCompensatorRemovesTheJumpFoldedIntoTheSnapBackEvent() {
        var compensator = MouseGestureWarpDeltaCompensator()
        // Two events drift left by 10 each; the lock warps back.
        XCTAssertEqual(
            compensator.physicalDelta(CGPoint(x: -10, y: 0), location: CGPoint(x: 490.4, y: 300.7), anchor: anchor),
            CGPoint(x: -10, y: 0)
        )
        XCTAssertEqual(
            compensator.physicalDelta(CGPoint(x: -10, y: 0), location: CGPoint(x: 480.4, y: 300.7), anchor: anchor),
            CGPoint(x: -10, y: 0)
        )
        // Snap back: the hand moved -10 again, the system adds the +20 jump.
        let snapped = compensator.physicalDelta(CGPoint(x: 10, y: 0), location: CGPoint(x: 500, y: 300), anchor: anchor)
        XCTAssertEqual(snapped.x, -10, accuracy: 1e-9)
        XCTAssertEqual(snapped.y, 0, accuracy: 1e-9)
        // Back to normal afterwards.
        XCTAssertEqual(
            compensator.physicalDelta(CGPoint(x: -10, y: 0), location: CGPoint(x: 500, y: 300), anchor: anchor),
            CGPoint(x: -10, y: 0)
        )
    }

    func testWarpCompensatorKeepsHonestDeltasWhenTheWarpAddsNothing() {
        var compensator = MouseGestureWarpDeltaCompensator()
        _ = compensator.physicalDelta(CGPoint(x: -10, y: 0), location: CGPoint(x: 490.4, y: 300.7), anchor: anchor)
        _ = compensator.physicalDelta(CGPoint(x: -10, y: 0), location: CGPoint(x: 480.4, y: 300.7), anchor: anchor)
        // Older systems: the snap-back event carries only the hand's movement.
        let snapped = compensator.physicalDelta(CGPoint(x: -10, y: 0), location: CGPoint(x: 500, y: 300), anchor: anchor)
        XCTAssertEqual(snapped, CGPoint(x: -10, y: 0))
    }

    func testWarpCompensatorResetForgetsTheDrift() {
        var compensator = MouseGestureWarpDeltaCompensator()
        _ = compensator.physicalDelta(CGPoint(x: -10, y: 0), location: CGPoint(x: 480, y: 300), anchor: anchor)
        compensator.reset()
        let delta = compensator.physicalDelta(CGPoint(x: 20, y: 0), location: CGPoint(x: 500, y: 300), anchor: anchor)
        XCTAssertEqual(delta, CGPoint(x: 20, y: 0))
    }
}
