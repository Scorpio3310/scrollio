//
//  ScrollPhaseTests.swift
//  MosTests
//
//  ScrollPhase 状态机完整转换测试 (Task 5)
//

import XCTest
@testable import Scrollio_Debug

final class ScrollPhaseTests: XCTestCase {

    var sut: ScrollPhase!

    override func setUp() {
        super.setUp()
        sut = ScrollPhase()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialPhaseIsIdle() {
        XCTAssertEqual(sut.phase, .Idle)
    }

    // MARK: - reset

    func testResetBringsBackToIdle() {
        // 先推进到非 Idle 状态
        // isSeparated=true 从 Idle 返回 queue (非 target), 需要应用 queue 中的条目
        let plan = sut.onManualInputDetected(isSeparated: true)
        for entry in plan.queue {
            sut.apply(phase: entry.0, autoAdvance: entry.1)
        }
        if let target = plan.target {
            sut.apply(phase: target.0, autoAdvance: target.1)
        }
        XCTAssertNotEqual(sut.phase, .Idle)
        sut.reset()
        XCTAssertEqual(sut.phase, .Idle)
    }

    // MARK: - onManualInputDetected: 首次输入 (Idle -> TrackingBegin)

    func testFirstSeparatedInput_emitsTrackingBeginInQueue() {
        let plan = sut.onManualInputDetected(isSeparated: true)
        // isSeparated=true 时, queue 包含 TrackingBegin (作为额外帧)
        XCTAssertFalse(plan.queue.isEmpty, "separated input from Idle should produce queue with TrackingBegin")
        XCTAssertEqual(plan.queue.first?.0, .TrackingBegin)
        XCTAssertEqual(plan.queue.first?.1, .TrackingOngoing)
    }

    func testFirstNonSeparatedInput_targetIsTrackingBegin() {
        let plan = sut.onManualInputDetected(isSeparated: false)
        // isSeparated=false, 从 Idle -> TrackingBegin
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .TrackingBegin)
        XCTAssertEqual(plan.target?.1, .TrackingOngoing)
    }

    // MARK: - onManualInputDetected: 连续输入 (TrackingOngoing)

    func testContinuousInput_staysTrackingOngoing() {
        // 推进到 TrackingOngoing
        sut.apply(phase: .TrackingBegin, autoAdvance: .TrackingOngoing)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .TrackingOngoing)

        let plan = sut.onManualInputDetected(isSeparated: false)
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .TrackingOngoing)
    }

    // MARK: - onManualInputDetected: 惯性中断 (MomentumOngoing -> 补发 MomentumEnd + TrackingBegin)

    func testInterruptMomentum_separated_emitsExtraFrames() {
        sut.apply(phase: .MomentumOngoing)
        let plan = sut.onManualInputDetected(isSeparated: true)
        // 应该补发 MomentumEnd + TrackingBegin
        XCTAssertEqual(plan.queue.count, 2, "interrupting momentum with separated should produce 2 extra frames")
        XCTAssertEqual(plan.queue[0].0, .MomentumEnd)
        XCTAssertEqual(plan.queue[1].0, .TrackingBegin)
    }

    func testInterruptMomentum_notSeparated_emitsExtraMomentumEnd() {
        sut.apply(phase: .MomentumOngoing)
        let plan = sut.onManualInputDetected(isSeparated: false)
        // 补发 MomentumEnd, target 为 TrackingBegin
        XCTAssertEqual(plan.queue.count, 1)
        XCTAssertEqual(plan.queue[0].0, .MomentumEnd)
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .TrackingBegin)
    }

    // MARK: - onManualInputEnded

    func testManualInputEnded_fromTracking_producesTrackingEnd() {
        sut.apply(phase: .TrackingOngoing)
        let plan = sut.onManualInputEnded()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .TrackingEnd)
    }

    func testManualInputEnded_fromIdle_producesNoPlan() {
        XCTAssertEqual(sut.phase, .Idle)
        let plan = sut.onManualInputEnded()
        XCTAssertNil(plan.target)
        XCTAssertTrue(plan.queue.isEmpty)
    }

    func testManualInputEnded_fromTrackingBegin_producesTrackingEnd() {
        sut.apply(phase: .TrackingBegin)
        let plan = sut.onManualInputEnded()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .TrackingEnd)
    }

    // MARK: - onMomentumStart

    func testMomentumStart_fromTrackingEnd() {
        sut.apply(phase: .TrackingEnd)
        let plan = sut.onMomentumStart()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .MomentumBegin)
        XCTAssertEqual(plan.target?.1, .MomentumOngoing)
    }

    func testMomentumStart_fromMomentumEnd() {
        sut.apply(phase: .MomentumEnd)
        let plan = sut.onMomentumStart()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .MomentumBegin)
    }

    func testMomentumStart_fromMomentumBegin_advancesToOngoing() {
        sut.apply(phase: .MomentumBegin)
        let plan = sut.onMomentumStart()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .MomentumOngoing)
    }

    func testMomentumStart_fromIdle_producesNoPlan() {
        let plan = sut.onMomentumStart()
        XCTAssertNil(plan.target)
        XCTAssertTrue(plan.queue.isEmpty)
    }

    // MARK: - onMomentumOngoing

    func testMomentumOngoing_fromMomentumBegin() {
        sut.apply(phase: .MomentumBegin)
        let plan = sut.onMomentumOngoing()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .MomentumOngoing)
    }

    func testMomentumOngoing_fromOtherPhase_noPlan() {
        sut.apply(phase: .TrackingOngoing)
        let plan = sut.onMomentumOngoing()
        XCTAssertNil(plan.target)
    }

    // MARK: - onMomentumFinish

    func testMomentumFinish_fromMomentumOngoing() {
        sut.apply(phase: .MomentumOngoing)
        let plan = sut.onMomentumFinish()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .MomentumEnd)
        XCTAssertEqual(plan.target?.1, .Idle)
    }

    func testMomentumFinish_fromMomentumBegin() {
        sut.apply(phase: .MomentumBegin)
        let plan = sut.onMomentumFinish()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .MomentumEnd)
        XCTAssertEqual(plan.target?.1, .Idle)
    }

    func testMomentumFinish_fromTracking_producesTrackingEnd() {
        sut.apply(phase: .TrackingOngoing)
        let plan = sut.onMomentumFinish()
        XCTAssertNotNil(plan.target)
        XCTAssertEqual(plan.target?.0, .TrackingEnd)
        XCTAssertEqual(plan.target?.1, .Idle)
    }

    func testMomentumFinish_fromIdle_noPlan() {
        let plan = sut.onMomentumFinish()
        XCTAssertNil(plan.target)
        XCTAssertTrue(plan.queue.isEmpty)
    }

    // MARK: - didDeliverFrame (autoAdvance)

    func testDidDeliverFrame_appliesAutoAdvance() {
        sut.apply(phase: .TrackingBegin, autoAdvance: .TrackingOngoing)
        XCTAssertEqual(sut.phase, .TrackingBegin)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .TrackingOngoing)
    }

    func testDidDeliverFrame_withoutAutoAdvance_noChange() {
        sut.apply(phase: .TrackingOngoing, autoAdvance: nil)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .TrackingOngoing)
    }

    func testDidDeliverFrame_clearsAutoAdvance() {
        sut.apply(phase: .MomentumBegin, autoAdvance: .MomentumOngoing)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .MomentumOngoing)
        // 第二次调用不应该再切换
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .MomentumOngoing)
    }

    // MARK: - PhaseValueMapping

    func testPhaseValueMapping_idle() {
        let values = PhaseValueMapping[.Idle]
        XCTAssertNotNil(values)
        XCTAssertEqual(values?[.Scroll], 0.0)
        XCTAssertEqual(values?[.Momentum], 0.0)
    }

    func testPhaseValueMapping_trackingBegin() {
        let values = PhaseValueMapping[.TrackingBegin]
        XCTAssertNotNil(values)
        XCTAssertEqual(values?[.Scroll], 1.0)
        XCTAssertEqual(values?[.Momentum], 0.0)
    }

    func testPhaseValueMapping_momentumOngoing() {
        let values = PhaseValueMapping[.MomentumOngoing]
        XCTAssertNotNil(values)
        XCTAssertEqual(values?[.Scroll], 0.0)
        XCTAssertEqual(values?[.Momentum], 2.0)
    }

    func testPhaseValueMapping_allPhasesHaveEntries() {
        let allPhases: [Phase] = [.Idle, .TrackingBegin, .TrackingOngoing, .TrackingEnd,
                                   .MomentumBegin, .MomentumOngoing, .MomentumEnd]
        for phase in allPhases {
            XCTAssertNotNil(PhaseValueMapping[phase], "Missing mapping for \(phase)")
        }
    }

    // MARK: - 完整流程测试: 非惯性滚动

    func testFullFlow_nonInertialScroll() {
        // 首次输入 (separated) -> TrackingBegin
        let plan1 = sut.onManualInputDetected(isSeparated: true)
        XCTAssertFalse(plan1.queue.isEmpty)
        // 应用 queue 中的 TrackingBegin
        sut.apply(phase: plan1.queue[0].0, autoAdvance: plan1.queue[0].1)
        XCTAssertEqual(sut.phase, .TrackingBegin)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .TrackingOngoing)

        // 连续输入
        let plan2 = sut.onManualInputDetected(isSeparated: false)
        if let target = plan2.target {
            sut.apply(phase: target.0, autoAdvance: target.1)
        }
        XCTAssertEqual(sut.phase, .TrackingOngoing)

        // 输入结束
        let plan3 = sut.onManualInputEnded()
        if let target = plan3.target {
            sut.apply(phase: target.0, autoAdvance: target.1)
        }
        XCTAssertEqual(sut.phase, .TrackingEnd)
    }

    // MARK: - 完整流程测试: 惯性滚动

    func testFullFlow_inertialScroll() {
        // TrackingBegin -> TrackingOngoing -> TrackingEnd
        sut.apply(phase: .TrackingBegin, autoAdvance: .TrackingOngoing)
        sut.didDeliverFrame()
        let planEnd = sut.onManualInputEnded()
        if let target = planEnd.target {
            sut.apply(phase: target.0, autoAdvance: target.1)
        }
        XCTAssertEqual(sut.phase, .TrackingEnd)

        // MomentumBegin
        let planMB = sut.onMomentumStart()
        if let target = planMB.target {
            sut.apply(phase: target.0, autoAdvance: target.1)
        }
        XCTAssertEqual(sut.phase, .MomentumBegin)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .MomentumOngoing)

        // MomentumFinish
        let planMF = sut.onMomentumFinish()
        if let target = planMF.target {
            sut.apply(phase: target.0, autoAdvance: target.1)
        }
        XCTAssertEqual(sut.phase, .MomentumEnd)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .Idle)
    }

    // MARK: - 完整流程测试: 惯性中断

    func testFullFlow_momentumInterrupt() {
        // 进入 MomentumOngoing
        sut.apply(phase: .MomentumOngoing)
        XCTAssertEqual(sut.phase, .MomentumOngoing)

        // 新的 separated 输入中断
        let plan = sut.onManualInputDetected(isSeparated: true)
        // 应该有 2 个 queue 条目: MomentumEnd + TrackingBegin
        XCTAssertEqual(plan.queue.count, 2)

        // 应用 MomentumEnd
        sut.apply(phase: plan.queue[0].0, autoAdvance: plan.queue[0].1)
        XCTAssertEqual(sut.phase, .MomentumEnd)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .Idle)

        // 应用 TrackingBegin
        sut.apply(phase: plan.queue[1].0, autoAdvance: plan.queue[1].1)
        XCTAssertEqual(sut.phase, .TrackingBegin)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .TrackingOngoing)
    }

    // MARK: - A stop after the touch has ended

    /// In TrackingEnd the touch's "ended" has gone out: a stop then sends nothing more. It
    /// used to plan a second "ended" ("began, ended, ended" for the app).
    func testMomentumFinish_fromTrackingEnd_sendsNothing() {
        sut.apply(phase: .TrackingEnd)
        let plan = sut.onMomentumFinish()
        XCTAssertNil(plan.target)
        XCTAssertTrue(plan.queue.isEmpty)
        // While the touch lasts, a stop still ends it.
        sut.apply(phase: .TrackingBegin, autoAdvance: .TrackingOngoing)
        XCTAssertEqual(sut.onMomentumFinish().target?.0, .TrackingEnd)
    }

    /// A glide of which nothing went out is not ended, in both forms of trackpad-style
    /// events (`holdsWaitingMomentumBegan`); with it off the phases run as they always did.
    func testMomentumFinish_whileMomentumBeganWaits() {
        sut.holdsWaitingMomentumBegan = true
        sut.apply(phase: .MomentumBegin, autoAdvance: .MomentumOngoing)
        XCTAssertTrue(sut.momentumBeganIsWaiting)
        XCTAssertNil(sut.onMomentumFinish().target, "no \"momentum ended\" without its \"began\"")
        XCTAssertNil(sut.onMomentumOngoing().target, "\"momentum began\" waits for the frame that carries it")
        sut.didDeliverFrame()
        XCTAssertEqual(sut.onMomentumFinish().target?.0, .MomentumEnd)

        sut.holdsWaitingMomentumBegan = false
        sut.apply(phase: .MomentumBegin, autoAdvance: .MomentumOngoing)
        XCTAssertEqual(sut.onMomentumFinish().target?.0, .MomentumEnd)
        XCTAssertEqual(sut.onMomentumOngoing().target?.0, .MomentumOngoing)
    }

    // MARK: - With trackpad-style events (the mode whose phases reach an app)
    //
    // The tests above run the machine as it runs with the switch off: its phases reach no app
    // then, they only time the end of a scroll. With the switch on (`holdsWaitingMomentumBegan`)
    // the same calls have to keep what an app gets whole.

    /// A whole scroll with a glide: "momentum began" stays until the frame that carries it has
    /// gone out, however many frames post nothing before that.
    func testFullFlow_withTrackpadStyle_momentumBeganWaitsForItsFrame() {
        sut.holdsWaitingMomentumBegan = true
        let begin = sut.onManualInputDetected(isSeparated: true)
        XCTAssertTrue(begin.beginsTouch)
        sut.apply(phase: begin.queue[0].0, autoAdvance: begin.queue[0].1)
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .TrackingOngoing)
        XCTAssertEqual(sut.onManualInputEnded().target?.0, .TrackingEnd)
        sut.apply(phase: .TrackingEnd)

        let start = sut.onMomentumStart()
        XCTAssertEqual(start.target?.0, .MomentumBegin)
        sut.apply(phase: .MomentumBegin, autoAdvance: .MomentumOngoing)
        // Frames that come to no whole pixel: nothing is posted, the phase stays.
        for _ in 0..<5 {
            XCTAssertNil(sut.onMomentumOngoing().target)
            XCTAssertNil(sut.onMomentumStart().target)
            XCTAssertEqual(sut.phase, .MomentumBegin)
        }
        // The frame that carries it goes out; from then on the glide runs and can be ended.
        sut.didDeliverFrame()
        XCTAssertEqual(sut.phase, .MomentumOngoing)
        XCTAssertFalse(sut.momentumBeganIsWaiting)
        XCTAssertEqual(sut.onMomentumFinish().target?.0, .MomentumEnd)
    }

    /// A wheel event while "momentum began" still waits: the glide is taken back (the app has
    /// the touch and its "ended", nothing of a glide), and the new touch begins without a
    /// "momentum ended" in between.
    func testDropWaitingMomentumBegan_takesBackAGlideOfWhichNothingWentOut() {
        sut.holdsWaitingMomentumBegan = true
        sut.apply(phase: .MomentumBegin, autoAdvance: .MomentumOngoing)
        XCTAssertTrue(sut.momentumBeganIsWaiting)

        sut.dropWaitingMomentumBegan()

        XCTAssertEqual(sut.phase, .TrackingEnd)
        let next = sut.onManualInputDetected(isSeparated: true)
        XCTAssertEqual(next.queue.map { $0.0 }, [.TrackingBegin], "\"began\" alone, no \"momentum ended\"")

        // A glide that has begun for the app is not taken back: it is ended.
        sut.apply(phase: .MomentumBegin, autoAdvance: .MomentumOngoing)
        sut.didDeliverFrame()
        sut.dropWaitingMomentumBegan()
        XCTAssertEqual(sut.phase, .MomentumOngoing)
        XCTAssertEqual(sut.onManualInputDetected(isSeparated: true).queue.map { $0.0 }, [.MomentumEnd, .TrackingBegin])
    }

    /// As a flick "began" waits for the first frame that moves the page. While it waits the
    /// app has nothing of the touch: a wheel event goes on with it, and nothing is ended.
    func testWaitingBegan_takesWheelEventsAndIsNotEnded() {
        sut.holdsWaitingBegan = true
        sut.apply(phase: .TrackingBegin, autoAdvance: .TrackingOngoing)
        XCTAssertTrue(sut.beganIsWaiting)

        for separated in [true, false] {
            let plan = sut.onManualInputDetected(isSeparated: separated)
            XCTAssertTrue(plan.queue.isEmpty && plan.target == nil, "the touch that waits takes the wheel event")
            XCTAssertFalse(plan.beginsTouch)
            XCTAssertTrue(sut.beganIsWaiting)
        }
        let lifted = sut.onManualInputEnded()
        XCTAssertTrue(lifted.queue.isEmpty && lifted.target == nil, "no \"ended\" for a touch the app never got")
        XCTAssertTrue(sut.beganIsWaiting, "a frame that still comes carries \"began\"")

        let stopped = sut.onMomentumFinish()
        XCTAssertTrue(stopped.queue.isEmpty && stopped.target == nil, "nor at a stop")
        XCTAssertEqual(sut.phase, .Idle)

        // Once its frame has gone out the touch is the app's: it is ended as always.
        sut.apply(phase: .TrackingBegin, autoAdvance: .TrackingOngoing)
        sut.didDeliverFrame()
        XCTAssertFalse(sut.beganIsWaiting)
        XCTAssertEqual(sut.phase, .TrackingOngoing)
        XCTAssertEqual(sut.onManualInputEnded().target?.0, .TrackingEnd)
        XCTAssertEqual(sut.onMomentumFinish().target?.0, .TrackingEnd)
    }

    /// Without the flick's rule (every other form, and the switch off) the machine is what
    /// it was: a wheel event in that state moves it on, and a stop ends the touch.
    func testWithoutTheFlicksRule_theMachineIsWhatItWas() {
        XCTAssertFalse(sut.holdsWaitingBegan)
        sut.apply(phase: .TrackingBegin, autoAdvance: .TrackingOngoing)
        XCTAssertEqual(sut.onManualInputDetected(isSeparated: false).target?.0, .TrackingOngoing)
        XCTAssertEqual(sut.onManualInputDetected(isSeparated: true).queue.map { $0.0 }, [.TrackingBegin])
        XCTAssertEqual(sut.onManualInputEnded().target?.0, .TrackingEnd)
        XCTAssertEqual(sut.onMomentumFinish().target?.0, .TrackingEnd)
    }
}
