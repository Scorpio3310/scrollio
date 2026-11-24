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

    /// Not in the table above: sideways, a swipe pulled back goes on through its start and
    /// brings in the Space on the other side. A session that stopped at the start would
    /// pass every other case.
    func testASidewaysSwipeGoesThroughItsStartToTheSpaceOnTheOtherSide() {
        let result = run([.move(-50, 0, at: 0.0), .move(150, 0, at: 0.2), .release(at: 0.2)])
        assertCommands(
            result.commands,
            // 0.15 of progress back in the 80 ms before the release.
            [.begin(.horizontal), .update(0.05), .update(-0.1), .end(velocity: -1.875)],
            "through the start"
        )
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

    // MARK: - Up and down as motions

    private typealias Channel = InteractiveGestureSession.Channel
    private typealias Role = InteractiveGestureSession.Role
    private typealias Roles = InteractiveGestureSession.Roles

    /// What a motion that is not the desktops is given: points of travel back that still
    /// count as a hand at rest, and the largest velocity in whole motions per second.
    private static let tunedReverseTolerance: CGFloat = 8
    private static let tunedTravelsPerSecond: Double = 12

    /// A channel as up and down get it: it begins at 40 pt and is one-sided unless it
    /// `crosses`. 1000 pt of travel = the whole motion, as in `configuration()`.
    private func channel(
        _ motion: DockSwipeAxis,
        _ sign: Double,
        crosses: Bool = false,
        tuned: Bool = false,
        progressPerPoint: Double = 0.001,
        maximumProgress: Double = 1
    ) -> Role {
        .channel(Channel(
            motion: motion,
            sign: sign,
            progressPerPoint: progressPerPoint,
            maximumProgress: maximumProgress,
            crossesStart: crosses,
            reverseTolerance: tuned ? Self.tunedReverseTolerance : 0,
            maximumTravelsPerSecond: tuned ? Self.tunedTravelsPerSecond : nil
        ))
    }

    /// Sideways the Spaces swipe as today; up and down as given.
    private func configuration(up: Role, down: Role) -> Session.Configuration {
        var configuration = self.configuration()
        configuration.roles.up = up
        configuration.roles.down = down
        return configuration
    }

    /// The sequences N1 to N28 of the design. They read the same with and without the
    /// reverse tolerance and the velocity bound.
    func testUpAndDownMotionsProduceExpectedCommands() {
        for tuned in [false, true] {
            // Up opens on the vertical motion, down on the other end of the pinch.
            let defaults = configuration(up: channel(.vertical, 1, tuned: tuned), down: channel(.pinch, -1, tuned: tuned))
            // Down is one action (a key combination, say).
            let upOnly = configuration(up: channel(.vertical, 1, tuned: tuned), down: .discrete)
            let downOnly = configuration(up: .discrete, down: channel(.pinch, 1, tuned: tuned))
            // Both on the vertical motion, one end each.
            let pairCrossing = configuration(
                up: channel(.vertical, 1, crosses: true, tuned: tuned),
                down: channel(.vertical, -1, crosses: true, tuned: tuned)
            )
            let pairClamped = configuration(up: channel(.vertical, 1, tuned: tuned), down: channel(.vertical, -1, tuned: tuned))
            // Both the same end of the same motion.
            let sameBoth = configuration(up: channel(.vertical, 1, tuned: tuned), down: channel(.vertical, 1, tuned: tuned))

            let cases: [(name: String, configuration: Session.Configuration, steps: [Step], expected: [Command])] = [
                (
                    "N1 up, slowly: the motion begins where the action ran (40 pt), with that movement",
                    defaults,
                    [.move(0, -10, at: 0.01), .move(0, -20, at: 0.02), .move(0, -15, at: 0.03), .move(0, -100, at: 0.04), .release(at: 0.5)],
                    [.begin(.vertical), .update(0.015), .update(0.115), .end(velocity: 0)]
                ),
                (
                    "N2 up in one big movement",
                    defaults,
                    [.move(0, -300, at: 0.01)],
                    [.begin(.vertical), .update(0.3)]
                ),
                (
                    "N3 below 40 pt a vertical hold shows the Dock nothing",
                    defaults,
                    [.move(0, -39, at: 0.01)],
                    []
                ),
                (
                    "N4 a 9 pt vertical jolt and a release is still the click",
                    defaults,
                    [.move(0, -9, at: 0.01), .release(at: 0.1)],
                    [.click]
                ),
                (
                    "N5 a vertical jolt, then sideways: the Spaces swipe, and no other motion",
                    defaults,
                    [.move(0, 9, at: 0.01), .move(-20, 0, at: 0.02), .move(-30, 0, at: 0.03), .move(-100, 0, at: 0.05), .release(at: 0.5)],
                    [.begin(.horizontal), .update(0.03), .update(0.13), .end(velocity: 0)]
                ),
                (
                    "N6 a 39 pt jolt up, then sideways",
                    defaults,
                    [.move(0, -39, at: 0.01), .move(-50, 0, at: 0.02)],
                    [.begin(.horizontal), .update(0.05)]
                ),
                (
                    "N7 sideways still locks at 8 pt",
                    defaults,
                    [.move(-9, 0, at: 0.01)],
                    [.begin(.horizontal), .update(0.009)]
                ),
                (
                    "N8 after a sideways lock, up and down are ignored",
                    defaults,
                    [.move(-9, 0, at: 0.01), .move(0, -300, at: 0.02), .move(0, 600, at: 0.03)],
                    [.begin(.horizontal), .update(0.009)]
                ),
                (
                    "N9 after an up lock, sideways is ignored",
                    defaults,
                    [.move(0, -100, at: 0.01), .move(-300, 0, at: 0.02), .move(0, -50, at: 0.03)],
                    [.begin(.vertical), .update(0.1), .update(0.15)]
                ),
                (
                    "N10 diagonal waits, then up",
                    defaults,
                    [.move(30, -30, at: 0.01), .move(0, -30, at: 0.02)],
                    [.begin(.vertical), .update(0.03)]
                ),
                (
                    "N11 30 pt up, then down past the press point: the first direction at 40 pt is down",
                    defaults,
                    [.move(0, -30, at: 0.01), .move(0, 60, at: 0.02), .move(0, 20, at: 0.03)],
                    [.begin(.pinch), .update(-0.02)]
                ),
                (
                    "N12 up, back to the start and beyond: progress stays 0, the release cancels",
                    defaults,
                    [.move(0, -200, at: 0.0), .move(0, 150, at: 0.2), .move(0, 150, at: 0.4), .move(0, 300, at: 0.6), .release(at: 1.0)],
                    [.begin(.vertical), .update(0.2), .update(0.05), .update(0), .cancel]
                ),
                (
                    "N13 behind the start and out again: it responds at once",
                    defaults,
                    [.move(0, -200, at: 0.0), .move(0, 500, at: 0.2), .move(0, -50, at: 0.4), .release(at: 0.4)],
                    [.begin(.vertical), .update(0.2), .update(0), .update(0.05), .end(velocity: 0.625)]
                ),
                (
                    "N14 up locked: far down neither begins the down motion nor runs anything",
                    defaults,
                    [.move(0, -100, at: 0.0), .move(0, 900, at: 0.2), .release(at: 0.21)],
                    [.begin(.vertical), .update(0.1), .update(0), .cancel]
                ),
                (
                    "N15 down on a channel of negative sign: from 0 down to minus the maximum",
                    defaults,
                    [.move(0, 100, at: 0.0), .move(0, 2000, at: 0.2), .move(0, -100, at: 0.4), .move(0, -2000, at: 0.6), .release(at: 0.7)],
                    [.begin(.pinch), .update(-0.1), .update(-1), .update(-0.9), .update(0), .cancel]
                ),
                (
                    "N16 a pair on one motion, allowed to cross: one motion, the sign turns",
                    pairCrossing,
                    [.move(0, -100, at: 0.0), .move(0, 300, at: 0.2), .release(at: 0.2)],
                    [.begin(.vertical), .update(0.1), .update(-0.2), .end(velocity: -3.75)]
                ),
                (
                    "N17 the same pair, each end for itself",
                    pairClamped,
                    [.move(0, -100, at: 0.0), .move(0, 300, at: 0.2), .release(at: 0.2)],
                    [.begin(.vertical), .update(0.1), .update(0), .cancel]
                ),
                (
                    "N18 both directions the same end: down from an up lock only undoes",
                    sameBoth,
                    [.move(0, -100, at: 0.0), .move(0, 300, at: 0.2), .release(at: 0.5)],
                    [.begin(.vertical), .update(0.1), .update(0), .cancel]
                ),
                (
                    "N19 up is one action, down a motion: up runs once, then nothing more",
                    downOnly,
                    [.move(0, -45, at: 0.01), .move(0, 400, at: 0.1), .release(at: 0.2)],
                    [.discrete(.up)]
                ),
                (
                    "N20 up a motion, down one action: after the up motion began, far down runs nothing",
                    upOnly,
                    [.move(0, -100, at: 0.0), .move(0, 400, at: 0.2), .release(at: 0.3)],
                    [.begin(.vertical), .update(0.1), .update(0), .cancel]
                ),
                (
                    "N21 up a motion, down one action: down runs at 40 pt",
                    upOnly,
                    [.move(0, 45, at: 0.01), .release(at: 0.1)],
                    [.discrete(.down)]
                ),
                (
                    "N22 a flick that arrives with the release begins and ends in one go",
                    defaults,
                    [.move(0, -10, at: 0.01), .release(at: 0.05, pending: CGPoint(x: 0, y: -60))],
                    [.begin(.vertical), .update(0.06), .end(velocity: 3.6)]
                ),
                (
                    "N23 up, released while still moving up",
                    defaults,
                    [.move(0, -100, at: 0.00), .move(0, -100, at: 0.04), .move(0, -100, at: 0.08), .release(at: 0.08)],
                    [.begin(.vertical), .update(0.1), .update(0.2), .update(0.3), .end(velocity: 2.5)]
                ),
                (
                    "N24 up, heading back at the release",
                    defaults,
                    [.move(0, -300, at: 0.0), .move(0, 40, at: 0.30), .release(at: 0.31)],
                    [.begin(.vertical), .update(0.3), .update(0.26), .cancel]
                ),
                (
                    "N25 the far end saturates and turning back responds at once",
                    defaults,
                    [.move(0, -900, at: 0.0), .move(0, -900, at: 0.1), .move(0, -500, at: 0.2), .move(0, 100, at: 0.3)],
                    [.begin(.vertical), .update(0.9), .update(1), .update(0.9)]
                ),
                (
                    "N26 the watchdog mid-motion cancels; the late release is nothing",
                    defaults,
                    [.move(0, -500, at: 0.0), .expire, .release(at: 11)],
                    [.begin(.vertical), .update(0.5), .cancel]
                ),
                (
                    "N27 held past the timeout at the far end: the next input cancels",
                    defaults,
                    [.move(0, -2000, at: 1), .release(at: 10)],
                    [.begin(.vertical), .update(1), .cancel]
                ),
                (
                    "N28 cancel before the 40 pt of a vertical hold: nothing at all",
                    defaults,
                    [.move(0, -30, at: 0.01), .cancel, .release(at: 0.2)],
                    []
                ),
            ]

            for testCase in cases {
                let result = run(testCase.steps, configuration: testCase.configuration)
                assertCommands(result.commands, testCase.expected, "\(testCase.name) (tuned: \(tuned))")
            }
        }
    }

    /// Letting go of a thumb button jolts the mouse. For up and down a little travel back
    /// inside the last 80 ms is a hand at rest, not a hand heading back. Sideways keeps its
    /// rule.
    func testASmallRecoilAtTheReleaseOfAnUpOrDownMotionIsAHandAtRest() {
        let tuned = configuration(up: channel(.vertical, 1, tuned: true), down: channel(.pinch, -1, tuned: true))
        let plain = configuration(up: channel(.vertical, 1), down: channel(.pinch, -1))
        // "Swipe speed" 3: the same 600 pt are 200 pt.
        let fast = configuration(
            up: channel(.vertical, 1, tuned: true, progressPerPoint: 0.003),
            down: channel(.pinch, -1, tuned: true, progressPerPoint: 0.003)
        )

        let cases: [(name: String, configuration: Session.Configuration, steps: [Step], expected: [Command])] = [
            (
                "60 %, a rest, 2 pt back: ends at rest and lets macOS decide",
                tuned,
                [.move(0, -600, at: 0.0), .move(0, 2, at: 1.0), .release(at: 1.0)],
                [.begin(.vertical), .update(0.6), .update(0.598), .end(velocity: 0)]
            ),
            (
                "the same without a tolerance cancels",
                plain,
                [.move(0, -600, at: 0.0), .move(0, 2, at: 1.0), .release(at: 1.0)],
                [.begin(.vertical), .update(0.6), .update(0.598), .cancel]
            ),
            (
                "8 pt back that arrive with the release are still a rest",
                tuned,
                [.move(0, -600, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 0, y: 8))],
                [.begin(.vertical), .update(0.6), .end(velocity: 0)]
            ),
            (
                "half a point more is heading back",
                tuned,
                [.move(0, -600, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 0, y: 8.5))],
                [.begin(.vertical), .update(0.6), .cancel]
            ),
            (
                "movements back inside the window add up",
                tuned,
                [.move(0, -600, at: 0.0), .move(0, 5, at: 1.0), .move(0, 5, at: 1.02), .release(at: 1.03)],
                [.begin(.vertical), .update(0.6), .update(0.595), .update(0.59), .cancel]
            ),
            (
                "travel back before the window does not count",
                tuned,
                [.move(0, -600, at: 0.0), .move(0, 6, at: 1.0), .move(0, 6, at: 1.2), .release(at: 1.2)],
                [.begin(.vertical), .update(0.6), .update(0.594), .update(0.588), .end(velocity: 0)]
            ),
            (
                "down, the other sign: 8 pt back are a rest",
                tuned,
                [.move(0, 600, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 0, y: -8))],
                [.begin(.pinch), .update(-0.6), .end(velocity: 0)]
            ),
            (
                "down, the other sign: 9 pt back cancel",
                tuned,
                [.move(0, 600, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 0, y: -9))],
                [.begin(.pinch), .update(-0.6), .cancel]
            ),
            (
                "the tolerance is travel of the hand: the same 8 pt at a higher speed",
                fast,
                [.move(0, -200, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 0, y: 8))],
                [.begin(.vertical), .update(0.6), .end(velocity: 0)]
            ),
            (
                "and the same half point more",
                fast,
                [.move(0, -200, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 0, y: 8.5))],
                [.begin(.vertical), .update(0.6), .cancel]
            ),
            (
                "back at the start is as it was, however little travel it took",
                tuned,
                [.move(0, -38, at: 0.0), .move(0, -4, at: 0.5), .move(0, 4, at: 1.0), .release(at: 1.0)],
                [.begin(.vertical), .update(0.004), .update(0), .cancel]
            ),
            (
                "movement across the motion's axis is no travel back",
                tuned,
                [.move(0, -600, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 30, y: 2))],
                [.begin(.vertical), .update(0.6), .end(velocity: 0)]
            ),
            (
                "sideways keeps its rule: one point back cancels",
                tuned,
                [.move(-600, 0, at: 0.0), .release(at: 1.0, pending: CGPoint(x: 1, y: 0))],
                [.begin(.horizontal), .update(0.6), .cancel]
            ),
        ]

        for testCase in cases {
            let result = run(testCase.steps, configuration: testCase.configuration)
            assertCommands(result.commands, testCase.expected, testCase.name)
        }
    }

    /// The pinch shows too much release velocity as a jolt, and a mouse hand is faster than
    /// fingers on a trackpad. Sideways stays as measured.
    func testTheReleaseVelocityOfAnUpOrDownMotionIsBounded() {
        let tuned = configuration(up: channel(.vertical, 1, tuned: true), down: channel(.pinch, -1, tuned: true))
        let plain = configuration(up: channel(.vertical, 1), down: channel(.pinch, -1))
        // A motion whose full progress is 2: twelve of them per second are 24.
        let wide = configuration(
            up: channel(.vertical, 1, tuned: true, progressPerPoint: 0.002, maximumProgress: 2),
            down: .discrete
        )
        let crossing = configuration(
            up: channel(.vertical, 1, crosses: true, tuned: true),
            down: channel(.vertical, -1, crosses: true, tuned: true)
        )

        let cases: [(name: String, configuration: Session.Configuration, steps: [Step], expected: [Command])] = [
            (
                // Half the motion within a sixtieth of a second: 30 per second.
                "faster than twelve whole motions per second ends at twelve",
                tuned,
                [.move(0, -100, at: 0.0), .move(0, -400, at: 0.016), .release(at: 0.016)],
                [.begin(.vertical), .update(0.1), .update(0.5), .end(velocity: 12)]
            ),
            (
                "the same without a bound is as measured",
                plain,
                [.move(0, -100, at: 0.0), .move(0, -400, at: 0.016), .release(at: 0.016)],
                [.begin(.vertical), .update(0.1), .update(0.5), .end(velocity: 30)]
            ),
            (
                "the other sign is bounded the other way",
                tuned,
                [.move(0, 100, at: 0.0), .move(0, 400, at: 0.016), .release(at: 0.016)],
                [.begin(.pinch), .update(-0.1), .update(-0.5), .end(velocity: -12)]
            ),
            (
                "below the bound the velocity is the measured one",
                tuned,
                [.move(0, -100, at: 0.00), .move(0, -100, at: 0.04), .move(0, -100, at: 0.08), .release(at: 0.08)],
                [.begin(.vertical), .update(0.1), .update(0.2), .update(0.3), .end(velocity: 2.5)]
            ),
            (
                "the bound counts whole motions",
                wide,
                [.move(0, -100, at: 0.0), .move(0, -400, at: 0.016), .release(at: 0.016)],
                [.begin(.vertical), .update(0.2), .update(1), .end(velocity: 24)]
            ),
            (
                "a motion that went through its start is bounded on the other side too",
                crossing,
                [.move(0, -100, at: 0.0), .move(0, 600, at: 0.016), .release(at: 0.016)],
                [.begin(.vertical), .update(0.1), .update(-0.5), .end(velocity: -12)]
            ),
            (
                "sideways is as measured, however fast",
                tuned,
                [.move(-100, 0, at: 0.0), .move(-900, 0, at: 0.016), .release(at: 0.016)],
                [.begin(.horizontal), .update(0.1), .update(1), .end(velocity: 60)]
            ),
        ]

        for testCase in cases {
            let result = run(testCase.steps, configuration: testCase.configuration)
            assertCommands(result.commands, testCase.expected, testCase.name)
        }
    }

    /// "Expected to switch" reads the motion that began: half of its own full progress, or
    /// one whole motion per second outward, whatever the sign of its channel.
    func testSwitchPredictionReadsTheMotionThatBegan() {
        let defaults = configuration(up: channel(.vertical, 1), down: channel(.pinch, -1))

        // Down drives the pinch towards minus one.
        var session = run([.move(0, 600, at: 0)], configuration: defaults).session
        XCTAssertEqual(session.progress, -0.6, accuracy: 1e-9)
        XCTAssertTrue(session.isExpectedToSwitch(releaseVelocity: 0), "past half, at rest")
        session = run([.move(0, 200, at: 0)], configuration: defaults).session
        XCTAssertFalse(session.isExpectedToSwitch(releaseVelocity: 0), "short of half, at rest")
        XCTAssertTrue(session.isExpectedToSwitch(releaseVelocity: -1.5), "short of half, still moving outward")
        XCTAssertFalse(session.isExpectedToSwitch(releaseVelocity: 1.5), "short of half, moving back")

        // Up, the positive side of another motion.
        session = run([.move(0, -500, at: 0)], configuration: defaults).session
        XCTAssertTrue(session.isExpectedToSwitch(releaseVelocity: 0))
        session = run([.move(0, -490, at: 0)], configuration: defaults).session
        XCTAssertFalse(session.isExpectedToSwitch(releaseVelocity: 0.9))
        XCTAssertTrue(session.isExpectedToSwitch(releaseVelocity: 1))

        // Half of the motion's own full progress, not of a Space.
        let wide = configuration(up: channel(.vertical, 1, maximumProgress: 2), down: .discrete)
        session = run([.move(0, -900, at: 0)], configuration: wide).session
        XCTAssertFalse(session.isExpectedToSwitch(releaseVelocity: 1.9), "0.9 of 2, under one motion per second")
        XCTAssertTrue(session.isExpectedToSwitch(releaseVelocity: 2))

        // No motion began, or it is back at its start: never.
        session = run([.move(0, -30, at: 0)], configuration: defaults).session
        XCTAssertEqual(session.phase, .discrete)
        XCTAssertFalse(session.isExpectedToSwitch(releaseVelocity: 5))
        session = run([.move(0, -100, at: 0), .move(0, 400, at: 0.1)], configuration: defaults).session
        XCTAssertEqual(session.phase, .swiping)
        XCTAssertFalse(session.isExpectedToSwitch(releaseVelocity: 5))
    }

    func testTheFollowedDirectionIsTheOneWhoseMotionBegan() {
        let defaults = configuration(up: channel(.vertical, 1, tuned: true), down: channel(.pinch, -1, tuned: true))

        var session = Session(configuration: defaults, startTime: 0)
        XCTAssertNil(session.followedDirection)
        XCTAssertNil(session.followedChannel)
        _ = session.move(deltaX: 0, deltaY: -30, at: 0.01)
        XCTAssertEqual(session.phase, .discrete, "past the lock, no motion yet")
        XCTAssertNil(session.followedDirection)
        _ = session.move(deltaX: 0, deltaY: -30, at: 0.02)
        XCTAssertEqual(session.phase, .swiping)
        XCTAssertEqual(session.followedDirection, .up)
        XCTAssertEqual(session.followedChannel.map { Role.channel($0) }, defaults.roles.up)
        XCTAssertEqual(session.followedChannel?.motion, .vertical)
        XCTAssertEqual(session.followedChannel?.sign, 1)
        // Far down: still the up motion. It stays readable after the release (for the log).
        _ = session.move(deltaX: 0, deltaY: 500, at: 0.03)
        XCTAssertEqual(session.followedDirection, .up)
        _ = session.release(at: 0.04)
        XCTAssertEqual(session.followedDirection, .up)

        var down = Session(configuration: defaults, startTime: 0)
        _ = down.move(deltaX: 0, deltaY: 60, at: 0.01)
        XCTAssertEqual(down.followedDirection, .down)
        XCTAssertEqual(down.followedChannel?.motion, .pinch)
        XCTAssertEqual(down.followedChannel?.sign, -1)

        // A caller that cannot show the motion it was told to begin cancels the hold: the
        // direction stays readable (to run its action once instead) and nothing follows.
        var refused = Session(configuration: defaults, startTime: 0)
        XCTAssertEqual(refused.move(deltaX: 0, deltaY: 60, at: 0.01).first, .begin(.pinch))
        XCTAssertEqual(refused.cancel(), [.cancel])
        XCTAssertEqual(refused.followedDirection, .down)
        XCTAssertEqual(refused.move(deltaX: 0, deltaY: 60, at: 0.02), [])
        XCTAssertEqual(refused.release(pendingDeltaX: 0, pendingDeltaY: 60, at: 0.03), [])

        // A jolt down, then to the left: the swipe follows left.
        var sideways = Session(configuration: defaults, startTime: 0)
        _ = sideways.move(deltaX: 0, deltaY: 9, at: 0.01)
        _ = sideways.move(deltaX: -50, deltaY: 0, at: 0.02)
        XCTAssertEqual(sideways.phase, .swiping)
        XCTAssertEqual(sideways.followedDirection, .left)
        XCTAssertEqual(sideways.followedChannel?.motion, .horizontal)

        // A direction that runs its action follows nothing.
        var action = Session(configuration: configuration(), startTime: 0)
        XCTAssertEqual(action.move(deltaX: 0, deltaY: -60, at: 0.01), [.discrete(.up)])
        XCTAssertNil(action.followedDirection)
        XCTAssertNil(action.followedChannel)
    }

    /// The initializer the hold, the thumb wheel and the tests have always used: sideways
    /// the Spaces swipe, up and down one action each, nothing of the new numbers.
    func testTheSpacesConfigurationGivesSidewaysTheSwipeAndUpAndDownOneAction() {
        let next = Channel(
            motion: .horizontal, sign: 1, progressPerPoint: 0.002, maximumProgress: 1.5,
            crossesStart: true, beginsAtLock: true
        )
        var previous = next
        previous.sign = -1
        XCTAssertEqual(next.reverseTolerance, 0, "the Spaces swipe keeps its release rule")
        XCTAssertNil(next.maximumTravelsPerSecond, "and its velocity as measured")
        XCTAssertFalse(Channel(motion: .vertical, sign: 1, progressPerPoint: 1, maximumProgress: 1).crossesStart)
        XCTAssertFalse(Channel(motion: .vertical, sign: 1, progressPerPoint: 1, maximumProgress: 1).beginsAtLock)

        let plain = Session.Configuration(progressPerPoint: 0.002, maximumProgress: 1.5, invertHorizontal: false)
        XCTAssertEqual(plain.roles, Roles(up: .discrete, down: .discrete, left: .channel(next), right: .channel(previous)))
        XCTAssertEqual(plain.lockDistance, 8)
        XCTAssertEqual(plain.dominanceRatio, MouseGestureRecognizer.defaultDominanceRatio)
        XCTAssertEqual(plain.velocityWindow, 0.08)
        XCTAssertEqual(plain.watchdogTimeout, 10)

        let inverted = Session.Configuration(progressPerPoint: 0.002, maximumProgress: 1.5, invertHorizontal: true)
        XCTAssertEqual(inverted.roles, Roles(up: .discrete, down: .discrete, left: .channel(previous), right: .channel(next)))

        // The thumb wheel's use: no travel is spent on arming.
        let wheel = Session.Configuration(
            progressPerPoint: 0.002, maximumProgress: 1.5, invertHorizontal: true,
            lockDistance: 0, dominanceRatio: 2, velocityWindow: 0.1, watchdogTimeout: 3
        )
        XCTAssertEqual(wheel.roles, inverted.roles)
        XCTAssertEqual(wheel.lockDistance, 0)
        XCTAssertEqual(wheel.dominanceRatio, 2)
        XCTAssertEqual(wheel.velocityWindow, 0.1)
        XCTAssertEqual(wheel.watchdogTimeout, 3)
        XCTAssertEqual(Session.Configuration(roles: plain.roles), plain, "the roles alone, with the same defaults")

        for (direction, role) in [
            (MouseGestureDirection.up, Role.discrete), (.down, .discrete), (.left, .channel(next)), (.right, .channel(previous)),
        ] {
            XCTAssertEqual(plain.roles[direction], role, "\(direction)")
        }
    }

    /// "Swap left and right" turns the Spaces swipe, nothing else.
    func testSwappingLeftAndRightDoesNotTurnUpAndDown() {
        var swapped = configuration(invert: true)
        swapped.roles.up = channel(.vertical, 1)
        swapped.roles.down = channel(.pinch, -1)
        assertCommands(run([.move(0, -50, at: 0.01)], configuration: swapped).commands, [.begin(.vertical), .update(0.05)], "up")
        assertCommands(run([.move(0, 50, at: 0.01)], configuration: swapped).commands, [.begin(.pinch), .update(-0.05)], "down")
        assertCommands(run([.move(-50, 0, at: 0.01)], configuration: swapped).commands, [.begin(.horizontal), .update(-0.05)], "left")
    }

    /// A channel's sign says which way, not how fast.
    func testOnlyTheDirectionOfAChannelsSignCounts() {
        let loud = configuration(up: channel(.vertical, -3), down: channel(.pinch, 7))
        assertCommands(run([.move(0, -50, at: 0.01)], configuration: loud).commands, [.begin(.vertical), .update(-0.05)], "up")
        assertCommands(run([.move(0, 50, at: 0.01)], configuration: loud).commands, [.begin(.pinch), .update(0.05)], "down")
    }

    func testAChannelsRangeIsOneSidedUnlessItCrossesItsStart() {
        func range(_ sign: Double, crosses: Bool = false, maximum: Double = 1.5) -> ClosedRange<Double> {
            Channel(
                motion: .vertical, sign: sign, progressPerPoint: 0.001, maximumProgress: maximum, crossesStart: crosses
            ).progressRange
        }
        XCTAssertEqual(range(1), 0...1.5)
        XCTAssertEqual(range(-1), -1.5...0)
        XCTAssertEqual(range(1, crosses: true), -1.5...1.5)
        XCTAssertEqual(range(-1, crosses: true), -1.5...1.5)

        // A maximum that is no positive number leaves no room, and breaks nothing.
        for maximum in [0, -1, Double.nan] {
            XCTAssertEqual(range(1, maximum: maximum), 0...0, "\(maximum)")
            XCTAssertEqual(range(-1, maximum: maximum), 0...0, "\(maximum)")
            XCTAssertEqual(range(1, crosses: true, maximum: maximum), 0...0, "\(maximum)")

            let stuck = configuration(
                up: channel(.vertical, 1, tuned: true, maximumProgress: maximum),
                down: channel(.vertical, -1, crosses: true, tuned: true, maximumProgress: maximum)
            )
            for towards: CGFloat in [-1, 1] {
                let result = run(
                    [.move(0, 100 * towards, at: 0.0), .move(0, -300 * towards, at: 0.1), .release(at: 0.2)],
                    configuration: stuck
                )
                XCTAssertEqual(result.commands, [.begin(.vertical), .cancel], "\(maximum), \(towards)")
            }
        }
    }

    // MARK: - Invariants with any roles

    private func randomRole(_ generator: inout SeededGenerator, sideways: Bool) -> Role {
        guard Int.random(in: 0..<4, using: &generator) != 0 else { return .discrete }
        let motions: [DockSwipeAxis] = [.horizontal, .vertical, .pinch]
        return .channel(Channel(
            motion: motions[Int.random(in: 0..<3, using: &generator)],
            sign: Bool.random(using: &generator) ? 1 : -1,
            progressPerPoint: Double.random(in: 0.0002...0.01, using: &generator),
            maximumProgress: Double.random(in: 0.5...2, using: &generator),
            crossesStart: Bool.random(using: &generator),
            beginsAtLock: sideways ? Bool.random(using: &generator) : Int.random(in: 0..<4, using: &generator) == 0,
            reverseTolerance: Bool.random(using: &generator) ? 0 : CGFloat(Int.random(in: 1...20, using: &generator)),
            maximumTravelsPerSecond: Bool.random(using: &generator) ? nil : Double.random(in: 0.5...15, using: &generator)
        ))
    }

    func testFuzzedHoldsWithAnyRolesBeginAtMostOneMotionAndNeverMixItWithAnAction() {
        var holdsWithAMotion = 0
        var holdsWithAnAction = 0
        for seed in UInt64(1)...3000 {
            var generator = SeededGenerator(state: seed &* 7919)
            let roles = Roles(
                up: randomRole(&generator, sideways: false),
                down: randomRole(&generator, sideways: false),
                left: randomRole(&generator, sideways: true),
                right: randomRole(&generator, sideways: true)
            )
            var session = Session(configuration: Session.Configuration(roles: roles), startTime: 0)
            var commands: [Command] = []
            var time: TimeInterval = 0
            for _ in 0..<Int.random(in: 0...60, using: &generator) {
                time += Double.random(in: 0...0.3, using: &generator)
                switch Int.random(in: 0..<50, using: &generator) {
                case 0:
                    commands += session.cancel()
                case 1:
                    commands += session.expire()
                case 2:
                    commands += session.release(
                        pendingDeltaX: CGFloat(Int.random(in: -50...50, using: &generator)),
                        pendingDeltaY: CGFloat(Int.random(in: -50...50, using: &generator)),
                        at: time
                    )
                default:
                    let horizontal = Bool.random(using: &generator)
                    commands += session.move(
                        deltaX: CGFloat(Int.random(in: horizontal ? -60...60 : -6...6, using: &generator)),
                        deltaY: CGFloat(Int.random(in: horizontal ? -6...6 : -60...60, using: &generator)),
                        at: time
                    )
                }
            }
            commands += Bool.random(using: &generator) ? session.release(at: time) : session.cancel()
            XCTAssertEqual(session.phase, .finished, "seed \(seed)")
            XCTAssertEqual(session.release(at: time + 1), [], "seed \(seed): input after the end")
            XCTAssertEqual(session.move(deltaX: 0, deltaY: -90, at: time + 1), [], "seed \(seed): input after the end")

            let counts = assertWellFormed(commands, roles: roles, session: session, seed: seed)
            holdsWithAMotion += counts.begins
            holdsWithAnAction += counts.actions
        }
        // The holds were not all of one kind.
        XCTAssertGreaterThan(holdsWithAMotion, 1000)
        XCTAssertGreaterThan(holdsWithAnAction, 300)
    }

    private func assertWellFormed(
        _ commands: [Command],
        roles: Roles,
        session: Session,
        seed: UInt64
    ) -> (begins: Int, actions: Int) {
        var begins = 0
        var terminals = 0
        var actions = 0
        var clicks = 0
        var isOpen = false
        var followed: Channel?
        var lastProgress: Double = 0
        for command in commands {
            switch command {
            case .begin(let motion):
                XCTAssertEqual(begins, 0, "seed \(seed): a hold begins at most one motion")
                XCTAssertEqual(actions, 0, "seed \(seed): a motion after an action")
                begins += 1
                isOpen = true
                guard let direction = session.followedDirection, case .channel(let channel) = roles[direction] else {
                    XCTFail("seed \(seed): a motion began without a followed channel")
                    continue
                }
                XCTAssertEqual(channel.motion, motion, "seed \(seed): another motion than its direction's")
                XCTAssertEqual(session.followedChannel, channel, "seed \(seed)")
                followed = channel
            case .update(let progress):
                XCTAssertTrue(isOpen, "seed \(seed): update outside began ... terminal")
                XCTAssertTrue(progress.isFinite, "seed \(seed)")
                if let followed {
                    // Inside the range: a one-sided motion never changes its sign.
                    XCTAssertTrue(followed.progressRange.contains(progress), "seed \(seed): \(progress) outside \(followed.progressRange)")
                }
                lastProgress = progress
            case .end(let velocity):
                XCTAssertTrue(isOpen, "seed \(seed): end without a began")
                XCTAssertTrue(velocity.isFinite, "seed \(seed)")
                XCTAssertNotEqual(lastProgress, 0, "seed \(seed): a release at the start is a cancel")
                if let followed, let perSecond = followed.maximumTravelsPerSecond {
                    XCTAssertLessThanOrEqual(abs(velocity), perSecond * followed.maximumProgress, "seed \(seed): velocity past its bound")
                }
                terminals += 1
                isOpen = false
            case .cancel:
                XCTAssertTrue(isOpen, "seed \(seed): cancel without a began")
                terminals += 1
                isOpen = false
            case .discrete(let direction):
                XCTAssertEqual(roles[direction], .discrete, "seed \(seed): the action of a direction that is a motion")
                XCTAssertEqual(begins, 0, "seed \(seed): an action after a motion began")
                actions += 1
            case .click:
                XCTAssertEqual(begins + actions, 0, "seed \(seed): a click after something ran")
                clicks += 1
            }
        }
        XCTAssertFalse(isOpen, "seed \(seed): motion left open")
        XCTAssertEqual(terminals, begins, "seed \(seed): exactly one terminal per began")
        XCTAssertLessThanOrEqual(actions + clicks, 1, "seed \(seed): at most one action or click per hold")
        if begins == 0 {
            XCTAssertNil(session.followedDirection, "seed \(seed): followed without a motion")
        }
        return (begins, actions)
    }

    // MARK: - Sideways is the released session, bit for bit

    private func bits(_ command: Command) -> String {
        switch command {
        case .begin(let motion): return "begin \(motion.rawValue)"
        case .update(let progress): return "update \(progress.bitPattern)"
        case .end(let velocity): return "end \(velocity.bitPattern)"
        case .cancel: return "cancel"
        case .discrete(let direction): return "discrete \(direction)"
        case .click: return "click"
        }
    }

    private func bits(_ command: ReleasedInteractiveGestureSession.Command) -> String {
        switch command {
        case .begin(let motion): return "begin \(motion.rawValue)"
        case .update(let progress): return "update \(progress.bitPattern)"
        case .end(let velocity): return "end \(velocity.bitPattern)"
        case .cancel: return "cancel"
        case .discrete(let direction): return "discrete \(direction)"
        case .click: return "click"
        }
    }

    /// The session of 1.1.1 (copied at the end of this file) and this one, fed the same
    /// random holds through the initializer both have: every command with the same bits,
    /// the same phase, progress and prediction after every step. Four kinds of hold: mostly
    /// sideways; a vertical jolt, then sideways; anything, with half points and other
    /// windows and timeouts; the thumb wheel's use (lock distance 0, sideways only).
    func testAHoldWithOnlyTheSpacesSwipeIsTheReleasedSessionBitForBit() {
        var compared = 0
        var holdsThatSwiped = 0
        var holdsThatSwipedAfterAVerticalLock = 0
        var holdsThatRanAnAction = 0
        for seed in UInt64(1)...30_000 {
            var generator = SeededGenerator(state: seed)
            let invert = Bool.random(using: &generator)
            let progressPerPoint = Double.random(in: 0.0002...0.01, using: &generator)
            let limit = Double.random(in: 0.5...2, using: &generator)
            let style = Int.random(in: 0..<4, using: &generator)
            let lockDistance: CGFloat = style == 3 ? 0 : 8
            let window = style == 2 ? Double.random(in: 0.02...0.2, using: &generator) : 0.08
            let timeout = style == 2 ? Double.random(in: 1...10, using: &generator) : 10
            var released = ReleasedInteractiveGestureSession(
                configuration: ReleasedInteractiveGestureSession.Configuration(
                    progressPerPoint: progressPerPoint, maximumProgress: limit, invertHorizontal: invert,
                    lockDistance: lockDistance, velocityWindow: window, watchdogTimeout: timeout
                ),
                startTime: 0
            )
            var session = Session(
                configuration: Session.Configuration(
                    progressPerPoint: progressPerPoint, maximumProgress: limit, invertHorizontal: invert,
                    lockDistance: lockDistance, velocityWindow: window, watchdogTimeout: timeout
                ),
                startTime: 0
            )
            var time: TimeInterval = 0
            var sawBegin = false
            var sawDiscretePhase = false
            let count = Int.random(in: 0...60, using: &generator)
            for index in 0...count {
                time += Double.random(in: 0...(style == 2 ? 0.4 : 0.03), using: &generator)
                var before: [ReleasedInteractiveGestureSession.Command] = []
                var after: [Command] = []
                // Every hold ends: a release, or the cancel path.
                let roll = index == count
                    ? (Bool.random(using: &generator) ? 2 : 0)
                    : Int.random(in: 0..<40, using: &generator)
                switch roll {
                case 0:
                    before = released.cancel()
                    after = session.cancel()
                case 1:
                    before = released.expire()
                    after = session.expire()
                case 2:
                    let pendingX = CGFloat(Int.random(in: -30...30, using: &generator))
                    let pendingY = CGFloat(Int.random(in: -30...30, using: &generator))
                    before = released.release(pendingDeltaX: pendingX, pendingDeltaY: pendingY, at: time)
                    after = session.release(pendingDeltaX: pendingX, pendingDeltaY: pendingY, at: time)
                default:
                    let deltaX: CGFloat
                    let deltaY: CGFloat
                    switch style {
                    case 0:
                        let horizontal = Int.random(in: 0..<4, using: &generator) != 0
                        deltaX = CGFloat(Int.random(in: horizontal ? -60...60 : -3...3, using: &generator))
                        deltaY = CGFloat(Int.random(in: horizontal ? -3...3 : -60...60, using: &generator))
                    case 1 where index == 0:
                        deltaX = CGFloat(Int.random(in: -3...3, using: &generator))
                        deltaY = CGFloat(Int.random(in: -39...39, using: &generator))
                    case 1:
                        deltaX = CGFloat(Int.random(in: -40...15, using: &generator))
                        deltaY = CGFloat(Int.random(in: -4...4, using: &generator))
                    case 3:
                        deltaX = CGFloat(Double.random(in: -40...40, using: &generator))
                        deltaY = 0
                    default:
                        // Half points too: a hold tracked by the device counts in halves.
                        deltaX = CGFloat(Int.random(in: -80...80, using: &generator)) * 0.5
                        deltaY = CGFloat(Int.random(in: -80...80, using: &generator)) * 0.5
                    }
                    before = released.move(deltaX: deltaX, deltaY: deltaY, at: time)
                    after = session.move(deltaX: deltaX, deltaY: deltaY, at: time)
                }
                if released.phase == .discrete { sawDiscretePhase = true }
                if before.contains(where: { if case .begin = $0 { return true } else { return false } }) {
                    sawBegin = true
                    if sawDiscretePhase { holdsThatSwipedAfterAVerticalLock += 1 }
                }
                if before.contains(where: { if case .discrete = $0 { return true } else { return false } }) {
                    holdsThatRanAnAction += 1
                }
                compared += 1
                let isSame = before.map { bits($0) } == after.map { bits($0) }
                    && "\(released.phase)" == "\(session.phase)"
                    && released.progress.bitPattern == session.progress.bitPattern
                    && released.isExpectedToSwitch(releaseVelocity: 0.7) == session.isExpectedToSwitch(releaseVelocity: 0.7)
                    && released.isExpectedToSwitch(releaseVelocity: -3) == session.isExpectedToSwitch(releaseVelocity: -3)
                guard isSame else {
                    XCTFail("""
                        seed \(seed), step \(index): 1.1.1 gave \(before) (\(released.phase), \(released.progress)), \
                        now \(after) (\(session.phase), \(session.progress))
                        """)
                    break
                }
            }
            if sawBegin { holdsThatSwiped += 1 }
        }
        // The comparison saw what it is for.
        XCTAssertGreaterThan(compared, 900_000)
        XCTAssertGreaterThan(holdsThatSwiped, 20_000)
        XCTAssertGreaterThan(holdsThatSwipedAfterAVerticalLock, 5_000)
        XCTAssertGreaterThan(holdsThatRanAnAction, 3_000)
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

// MARK: - The session of 1.1.1

/// `InteractiveGestureSession` as 1.1.1 has it (commit ad99ff6b), its code copied unchanged
/// and only renamed: what `testAHoldWithOnlyTheSpacesSwipeIsTheReleasedSessionBitForBit`
/// compares with. It goes, with that test, one release after up and down began to follow.
private struct ReleasedInteractiveGestureSession {

    struct Configuration: Equatable {
        var progressPerPoint: Double
        var maximumProgress: Double
        var invertHorizontal: Bool
        var lockDistance: CGFloat = 8
        var dominanceRatio: CGFloat = MouseGestureRecognizer.defaultDominanceRatio
        var velocityWindow: TimeInterval = 0.08
        var watchdogTimeout: TimeInterval = 10
    }

    enum Command: Equatable {
        case begin(DockSwipeAxis)
        case update(Double)
        case end(velocity: Double)
        case cancel
        case discrete(MouseGestureDirection)
        case click

        var isSwipeCommand: Bool {
            switch self {
            case .begin, .update, .end, .cancel: return true
            case .discrete, .click: return false
            }
        }
    }

    enum Phase: Equatable {
        case armed
        case swiping
        case discrete
        case finished
    }

    private static let minimumVelocityInterval: TimeInterval = 1.0 / 60.0

    let configuration: Configuration
    let startTime: TimeInterval

    private(set) var phase = Phase.armed
    private(set) var progress: Double = 0
    private var handProgress: Double = 0
    private var samples: [(time: TimeInterval, progress: Double)] = []
    private var recognizer = MouseGestureRecognizer()

    init(configuration: Configuration, startTime: TimeInterval) {
        self.configuration = configuration
        self.startTime = startTime
    }


    mutating func move(deltaX: CGFloat, deltaY: CGFloat, at time: TimeInterval) -> [Command] {
        guard phase != .finished else { return [] }
        if hasExpired(at: time) { return abandon() }
        guard deltaX != 0 || deltaY != 0 else { return [] }

        let recognized = recognizer.append(deltaX: deltaX, deltaY: deltaY)
        switch phase {
        case .armed:
            return lockAxisIfPossible(deltaX: deltaX, recognized: recognized, time: time)
        case .swiping:
            return advance(byPoints: deltaX, at: time)
        case .discrete:
            return discreteOrSwipeCommands(deltaX: deltaX, recognized: recognized, time: time)
        case .finished:
            return []
        }
    }

    mutating func release(pendingDeltaX: CGFloat = 0, pendingDeltaY: CGFloat = 0, at time: TimeInterval) -> [Command] {
        guard phase != .finished else { return [] }
        if hasExpired(at: time) { return abandon() }

        var commands: [Command] = []
        if phase == .swiping {
            if pendingDeltaX != 0 || pendingDeltaY != 0 {
                _ = recognizer.append(deltaX: pendingDeltaX, deltaY: pendingDeltaY)
                recordHandMovement(byPoints: pendingDeltaX, at: time)
            }
        } else {
            commands = move(deltaX: pendingDeltaX, deltaY: pendingDeltaY, at: time)
        }

        switch phase {
        case .armed, .discrete:
            if recognizer.shouldReplayClick {
                commands.append(.click)
            }
        case .swiping:
            commands.append(terminalCommand(at: time))
        case .finished:
            break
        }
        phase = .finished
        return commands
    }

    mutating func cancel() -> [Command] {
        return abandon()
    }

    mutating func expire() -> [Command] {
        return abandon()
    }


    private mutating func lockAxisIfPossible(
        deltaX: CGFloat,
        recognized: MouseGestureDirection?,
        time: TimeInterval
    ) -> [Command] {
        let horizontal = abs(recognizer.displacement.x)
        let vertical = abs(recognizer.displacement.y)
        guard max(horizontal, vertical) >= configuration.lockDistance else { return [] }

        if horizontal >= vertical * configuration.dominanceRatio {
            phase = .swiping
            samples = [(time, 0)]
            return [.begin(.horizontal)] + advance(byPoints: deltaX, at: time)
        }
        if vertical >= horizontal * configuration.dominanceRatio {
            phase = .discrete
            return discreteCommands(for: recognized)
        }
        return []
    }

    private func discreteCommands(for recognized: MouseGestureDirection?) -> [Command] {
        guard let recognized, recognized == .up || recognized == .down else { return [] }
        return [.discrete(recognized)]
    }

    private mutating func discreteOrSwipeCommands(
        deltaX: CGFloat,
        recognized: MouseGestureDirection?,
        time: TimeInterval
    ) -> [Command] {
        guard let recognized, recognized == .left || recognized == .right else {
            return discreteCommands(for: recognized)
        }
        phase = .swiping
        samples = [(time, 0)]
        return [.begin(.horizontal)] + advance(byPoints: deltaX, at: time)
    }


    private func progressStep(forPoints points: CGFloat) -> Double {
        let direction: Double = configuration.invertHorizontal ? 1 : -1
        return Double(points) * direction * configuration.progressPerPoint
    }

    private mutating func recordHandMovement(byPoints points: CGFloat, at time: TimeInterval) {
        handProgress += progressStep(forPoints: points)
        samples.append((time, handProgress))
        let windowStart = time - configuration.velocityWindow
        while samples.count >= 2, samples[1].time <= windowStart {
            samples.removeFirst()
        }
    }

    private mutating func advance(byPoints points: CGFloat, at time: TimeInterval) -> [Command] {
        recordHandMovement(byPoints: points, at: time)
        let limit = configuration.maximumProgress
        let next = min(max(progress + progressStep(forPoints: points), -limit), limit)
        guard next != progress else { return [] }
        progress = next
        return [.update(progress)]
    }

    private func terminalCommand(at time: TimeInterval) -> Command {
        let windowStart = time - configuration.velocityWindow
        let baseline = samples.last { $0.time <= windowStart } ?? samples.first ?? (time, handProgress)
        let recentMovement = handProgress - baseline.progress

        if progress == 0 || recentMovement * progress < 0 {
            return .cancel
        }
        let elapsed = min(configuration.velocityWindow, time - baseline.time)
        return .end(velocity: recentMovement / max(elapsed, Self.minimumVelocityInterval))
    }


    static let switchProgressShare: Double = 0.5
    static let switchSpacesPerSecond: Double = 1

    func isExpectedToSwitch(releaseVelocity: Double) -> Bool {
        let space = configuration.maximumProgress
        guard progress != 0, space > 0 else { return false }
        let towardsSwitch: Double = progress > 0 ? 1 : -1
        let share = abs(progress) / space
        let spacesPerSecond = releaseVelocity * towardsSwitch / space
        return share >= Self.switchProgressShare || spacesPerSecond >= Self.switchSpacesPerSecond
    }


    private func hasExpired(at time: TimeInterval) -> Bool {
        return time - startTime >= configuration.watchdogTimeout
    }

    private mutating func abandon() -> [Command] {
        guard phase != .finished else { return [] }
        let wasSwiping = phase == .swiping
        phase = .finished
        return wasSwiping ? [.cancel] : []
    }
}
