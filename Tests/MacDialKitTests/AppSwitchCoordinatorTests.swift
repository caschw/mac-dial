import XCTest
import MacDialKit

final class AppSwitchCoordinatorTests: XCTestCase {
    func testOlderQueuedSwitchCannotTimeOutANewerSwitch() {
        let harness = AppSwitchHarness()
        harness.enqueueBacklog(4095)
        XCTAssertEqual(harness.otherEffects, 512)
        XCTAssertTrue(harness.rotate(1))
        XCTAssertTrue(harness.switcher.finish())
        XCTAssertTrue(harness.rotate(-1))

        for _ in 0..<7 { harness.runNextTurn() }
        XCTAssertEqual(harness.events, [.command(true), .tab(true)])
        XCTAssertEqual(harness.clock.pendingCount, 0)
        harness.clock.advance(by: 1)
        harness.runNextTurn()
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .command(false), .command(true), .tab(false)])
        XCTAssertEqual(harness.clock.pendingCount, 1)

        harness.clock.advance(by: 0.89)
        XCTAssertEqual(harness.events.last, .tab(false))
        harness.clock.advance(by: 0.02)
        XCTAssertEqual(harness.events.last, .command(false))
    }

    func testNewRequestCancelsAnOlderTimerWhileItsOutputIsQueued() {
        let harness = AppSwitchHarness()
        XCTAssertTrue(harness.rotate(1))
        harness.enqueueBacklog(4095)
        XCTAssertTrue(harness.rotate(-1))
        XCTAssertEqual(harness.clock.pendingCount, 0)

        harness.clock.advance(by: 1)
        XCTAssertEqual(harness.events, [.command(true), .tab(true)])
        while !harness.turns.isEmpty { harness.runNextTurn() }
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .tab(false)])
        harness.clock.advance(by: 0.89)
        XCTAssertEqual(harness.events.last, .tab(false))
        harness.clock.advance(by: 0.02)
        XCTAssertEqual(harness.events.last, .command(false))
    }

    func testSplitSwitchRequestStartsReleaseDelayAfterItsFinalTab() {
        let harness = AppSwitchHarness()
        harness.enqueueBacklog(1023)
        XCTAssertTrue(harness.rotate(2))
        harness.runNextTurn()
        XCTAssertEqual(harness.events, [.command(true), .tab(true)])
        XCTAssertEqual(harness.clock.pendingCount, 0)

        harness.clock.advance(by: 1)
        harness.runNextTurn()
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .tab(true)])
        XCTAssertEqual(harness.clock.pendingCount, 1)
        harness.clock.advance(by: 0.89)
        XCTAssertEqual(harness.events.last, .tab(true))
        harness.clock.advance(by: 0.02)
        XCTAssertEqual(harness.events.last, .command(false))
    }

    func testCancellingAPartiallyDeliveredSwitchBalancesCommandAndAllowsReuse() {
        let harness = AppSwitchHarness()
        harness.enqueueBacklog(1023)
        XCTAssertTrue(harness.rotate(2))
        harness.runNextTurn()
        XCTAssertEqual(harness.events, [.command(true), .tab(true)])
        XCTAssertEqual(harness.clock.pendingCount, 0)

        harness.output.cancelPending()
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .command(false)])
        XCTAssertFalse(harness.switcher.finish())
        harness.runNextTurn()
        harness.clock.advance(by: 10)
        XCTAssertTrue(harness.rotate(-1))
        harness.clock.advance(by: 0.91)
        XCTAssertEqual(harness.events, [
            .command(true), .tab(true), .command(false),
            .command(true), .tab(false), .command(false)
        ])
    }

    func testCancellingTheQueueAlsoCancelsAnActiveSwitchTimer() {
        let harness = AppSwitchHarness()
        XCTAssertTrue(harness.rotate(1))
        XCTAssertEqual(harness.clock.pendingCount, 1)

        harness.output.cancelPending()
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .command(false)])
        XCTAssertEqual(harness.clock.pendingCount, 0)
        XCTAssertFalse(harness.switcher.finish())
        harness.clock.advance(by: 1)
        XCTAssertEqual(harness.events.count, 3)
    }

    func testCancellingAQueuedSwitchReleaseBalancesCommand() {
        let harness = AppSwitchHarness()
        XCTAssertTrue(harness.rotate(1))
        harness.enqueueBacklog(513)
        XCTAssertTrue(harness.switcher.finish())
        XCTAssertEqual(harness.events, [.command(true), .tab(true)])

        harness.output.cancelPending()
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .command(false)])
        harness.runNextTurn()
        XCTAssertEqual(harness.events.count, 3)
    }

    func testQueueCancellationDuringCommandDownDoesNotSendTab() throws {
        var commands: [Bool] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        let switcher = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock, postCommand: { down in
            commands.append(down)
            if down { output.cancelPending() }
        }, postTab: { _ in XCTFail("Tab must not follow cancellation") }))
        let binding = RotationBinding(.switchApps, steps: 1)
        XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: 2, at: 0), for: binding))
        XCTAssertEqual(commands, [true, false])
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertFalse(switcher.finish())
    }

    func testQueueCancellationDuringTabBalancesCommandForFinalAndNonfinalEffects() throws {
        for count in [1, 2] {
            var events: [AppSwitchHarness.Event] = []
            let clock = TestClock()
            let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                             perform: { _, _ in XCTFail("Unexpected default effect") })
            let switcher = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock,
                                                              postCommand: { events.append(.command($0)) },
                                                              postTab: { forward in
                events.append(.tab(forward))
                output.cancelPending()
            }))
            let binding = RotationBinding(.switchApps, steps: 1)
            XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: count, at: 0),
                                          for: binding))
            XCTAssertEqual(events, [.command(true), .tab(true), .command(false)])
            XCTAssertEqual(clock.pendingCount, 0)
            XCTAssertFalse(switcher.finish())
        }
    }

    func testSwitchRequestedDuringCancellationIsNotCancelled() throws {
        var events: [AppSwitchHarness.Event] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        let binding = RotationBinding(.switchApps, steps: 1)
        var switcher: AppSwitchCoordinator!
        var retried = false
        switcher = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock, postCommand: { down in
            events.append(.command(down))
            if !down, !retried {
                retried = true
                XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: -1, at: 0),
                                              for: binding))
            }
        }, postTab: { forward in
            events.append(.tab(forward))
            if forward { output.cancelPending() }
        }))
        XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0), for: binding))
        XCTAssertEqual(events, [.command(true), .tab(true), .command(false), .command(true), .tab(false)])
        XCTAssertEqual(clock.pendingCount, 1)
        clock.advance(by: 0.91)
        XCTAssertEqual(events.last, .command(false))
        switcher = nil
    }

    func testReentrantMousePressFollowsAllCancellationReleases() throws {
        var mouseEvents: [String] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        output.enqueueMouseButton(.leftClick, down: true) { mouseEvents.append($0 ? "old down" : "old up") }
        let switcher = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock, postCommand: { down in
            if !down {
                output.enqueueMouseButton(.leftClick, down: true) {
                    mouseEvents.append($0 ? "new down" : "new up")
                }
            }
        }, postTab: { _ in }))
        let binding = RotationBinding(.switchApps, steps: 1)
        XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0), for: binding))

        output.cancelPending()
        XCTAssertEqual(mouseEvents, ["old down", "old up", "new down"])
        output.enqueueMouseButton(.leftClick, down: false) { mouseEvents.append($0 ? "new down" : "new up") }
        XCTAssertEqual(mouseEvents, ["old down", "old up", "new down", "new up"])
    }

    func testQueueRejectsASecondCoordinatorAndAllowsAReplacement() throws {
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        let binding = RotationBinding(.switchApps, steps: 1)
        var events: [AppSwitchHarness.Event] = []
        let postCommand: (Bool) -> Void = { events.append(.command($0)) }
        let postTab: (Bool) -> Void = { events.append(.tab($0)) }
        var first: AppSwitchCoordinator? = try XCTUnwrap(AppSwitchCoordinator(
            output: output, scheduler: clock, postCommand: postCommand, postTab: postTab))
        XCTAssertTrue(first?.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0), for: binding) == true)
        clock.advance(by: 0.5)
        XCTAssertNil(AppSwitchCoordinator(output: output, scheduler: clock,
                                         postCommand: postCommand, postTab: postTab))
        XCTAssertEqual(events, [.command(true), .tab(true)])

        first = nil
        XCTAssertEqual(events, [.command(true), .tab(true), .command(false)])
        let second = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock,
                                                        postCommand: postCommand, postTab: postTab))
        XCTAssertTrue(second.enqueue(RotationInterpreter().rotate(binding, delta: -1, at: clock.now),
                                     for: binding))
        clock.advance(by: 0.41)
        XCTAssertEqual(events, [.command(true), .tab(true), .command(false), .command(true), .tab(false)])
        XCTAssertEqual(clock.pendingCount, 1)
        clock.advance(by: 0.5)
        XCTAssertEqual(events.last, .command(false))
    }

    func testQueueRemainsReservedUntilCoordinatorDeinitializationFinishes() throws {
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        let binding = RotationBinding(.switchApps, steps: 1)
        var attemptedReplacement = false
        var replacement: AppSwitchCoordinator?
        var first: AppSwitchCoordinator? = try XCTUnwrap(AppSwitchCoordinator(
            output: output, scheduler: clock, postCommand: { down in
                if !down {
                    attemptedReplacement = true
                    replacement = AppSwitchCoordinator(output: output, scheduler: clock,
                                                       postCommand: { _ in }, postTab: { _ in })
                }
            }, postTab: { _ in }))
        XCTAssertTrue(first?.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0), for: binding) == true)

        first = nil
        XCTAssertTrue(attemptedReplacement)
        XCTAssertNil(replacement)
        replacement = AppSwitchCoordinator(output: output, scheduler: clock,
                                           postCommand: { _ in }, postTab: { _ in })
        XCTAssertNotNil(replacement)
    }

    func testRejectedCoordinatorDoesNotStealCancellationOwnership() throws {
        var commands: [Bool] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        let binding = RotationBinding(.switchApps, steps: 1)
        let first = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock,
                                                       postCommand: { commands.append($0) },
                                                       postTab: { _ in }))
        XCTAssertTrue(first.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0), for: binding))
        XCTAssertNil(AppSwitchCoordinator(output: output, scheduler: clock,
                                         postCommand: { _ in }, postTab: { _ in }))
        output.cancelPending()
        XCTAssertEqual(commands, [true, false])
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertFalse(first.finish())
    }

    func testQueueDoesNotRetainItsSwitchCoordinator() throws {
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        weak var coordinator: AppSwitchCoordinator?
        do {
            let switcher = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: TestClock(),
                                                              postCommand: { _ in }, postTab: { _ in }))
            coordinator = switcher
            XCTAssertNotNil(coordinator)
        }
        XCTAssertNil(coordinator)
        output.cancelPending()
    }

    func testDeallocationBalancesCommandAndCancelsAnActiveTimer() {
        var events: [AppSwitchHarness.Event] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        let binding = RotationBinding(.switchApps, steps: 1)
        var switcher: AppSwitchCoordinator? = AppSwitchCoordinator(
            output: output, scheduler: clock,
            postCommand: { events.append(.command($0)) },
            postTab: { events.append(.tab($0)) })
        XCTAssertTrue(switcher?.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0),
                                        for: binding) == true)
        XCTAssertEqual(clock.pendingCount, 1)

        switcher = nil
        XCTAssertEqual(events, [.command(true), .tab(true), .command(false)])
        XCTAssertEqual(clock.pendingCount, 0)
        clock.advance(by: 1)
        XCTAssertEqual(events.count, 3)
    }

    func testQueuedFinishKeepsCoordinatorAliveUntilCommandRelease() {
        var events: [AppSwitchHarness.Event] = []
        var turns: [() -> Void] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { turns.append($0) }, perform: { _, _ in })
        let binding = RotationBinding(.switchApps, steps: 1)
        var switcher: AppSwitchCoordinator? = AppSwitchCoordinator(
            output: output, scheduler: clock,
            postCommand: { events.append(.command($0)) },
            postTab: { events.append(.tab($0)) })
        XCTAssertTrue(switcher?.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0),
                                        for: binding) == true)
        let zoom = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(output.enqueue(RotationInterpreter().rotate(zoom, delta: 1024, at: 0), for: zoom))
        XCTAssertTrue(switcher?.finish() == true)
        XCTAssertEqual(events, [.command(true), .tab(true)])

        weak var retainedSwitcher: AppSwitchCoordinator?
        retainedSwitcher = switcher
        switcher = nil
        XCTAssertNotNil(retainedSwitcher)
        XCTAssertEqual(events, [.command(true), .tab(true)])
        while !turns.isEmpty { turns.removeFirst()() }
        XCTAssertNil(retainedSwitcher)
        output.cancelPending()
        XCTAssertEqual(events, [.command(true), .tab(true), .command(false)])
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testCommittedPartialSwitchCompletesBeforeCoordinatorDeallocation() {
        var events: [AppSwitchHarness.Event] = []
        var turns: [() -> Void] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { turns.append($0) }, perform: { _, _ in })
        let binding = RotationBinding(.switchApps, steps: 1)
        var switcher: AppSwitchCoordinator? = AppSwitchCoordinator(
            output: output, scheduler: clock,
            postCommand: { events.append(.command($0)) },
            postTab: { events.append(.tab($0)) })
        let zoom = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(output.enqueue(RotationInterpreter().rotate(zoom, delta: 1023, at: 0), for: zoom))
        XCTAssertTrue(switcher?.enqueue(RotationInterpreter().rotate(binding, delta: 2, at: 0),
                                        for: binding) == true)
        turns.removeFirst()()
        XCTAssertEqual(events, [.command(true), .tab(true)])
        XCTAssertTrue(switcher?.finish() == true)

        weak var retainedSwitcher: AppSwitchCoordinator?
        retainedSwitcher = switcher
        switcher = nil
        XCTAssertNotNil(retainedSwitcher)
        XCTAssertEqual(events, [.command(true), .tab(true)])
        while !turns.isEmpty { turns.removeFirst()() }
        XCTAssertEqual(events, [.command(true), .tab(true), .tab(true), .command(false)])
        XCTAssertNil(retainedSwitcher)
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testCancellingCommittedSwitchAfterOwnerReleaseBalancesCommand() {
        var events: [AppSwitchHarness.Event] = []
        var turns: [() -> Void] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { turns.append($0) }, perform: { _, _ in })
        let binding = RotationBinding(.switchApps, steps: 1)
        var switcher: AppSwitchCoordinator? = AppSwitchCoordinator(
            output: output, scheduler: clock,
            postCommand: { down in
                events.append(.command(down))
                if !down { output.enqueueAction { events.append(.tab(false)) } }
            },
            postTab: { events.append(.tab($0)) })
        let zoom = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(output.enqueue(RotationInterpreter().rotate(zoom, delta: 1023, at: 0), for: zoom))
        XCTAssertTrue(switcher?.enqueue(RotationInterpreter().rotate(binding, delta: 2, at: 0),
                                        for: binding) == true)
        turns.removeFirst()()
        XCTAssertTrue(switcher?.finish() == true)

        weak var retainedSwitcher: AppSwitchCoordinator?
        retainedSwitcher = switcher
        switcher = nil
        XCTAssertNotNil(retainedSwitcher)
        output.cancelPending()
        XCTAssertEqual(events, [.command(true), .tab(true), .command(false), .tab(false)])
        XCTAssertNil(retainedSwitcher)
        turns.removeFirst()()
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testFinishOrdersReleaseBeforeSwitchRequestedByTimerCancellation() throws {
        for backlog in [0, 513] {
            var events: [AppSwitchHarness.Event] = []
            var turns: [() -> Void] = []
            let clock = CancelHookScheduler()
            let output = RotationEffectQueue(scheduleNext: { turns.append($0) }, perform: { _, _ in })
            let binding = RotationBinding(.switchApps, steps: 1)
            let switcher = try XCTUnwrap(AppSwitchCoordinator(
                output: output, scheduler: clock,
                postCommand: { events.append(.command($0)) },
                postTab: { events.append(.tab($0)) }))
            XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0),
                                          for: binding))
            if backlog > 0 {
                let zoom = RotationBinding(.zoom, steps: 1)
                XCTAssertTrue(output.enqueue(RotationInterpreter().rotate(zoom, delta: backlog, at: 0),
                                             for: zoom))
            }
            clock.tasks[0].onCancel = {
                XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: -1, at: 0),
                                              for: binding))
            }

            XCTAssertTrue(switcher.finish())
            while !turns.isEmpty { turns.removeFirst()() }
            XCTAssertEqual(events, [.command(true), .tab(true), .command(false), .command(true), .tab(false)])
            XCTAssertEqual(clock.tasks.filter { !$0.cancelled }.count, 1)
            clock.tasks.last?.fire()
            XCTAssertEqual(events.last, .command(false))
        }
    }

    func testReplacementFollowsADeallocatedPartialSwitch() throws {
        var events: [AppSwitchHarness.Event] = []
        var turns: [() -> Void] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { turns.append($0) }, perform: { _, _ in })
        let binding = RotationBinding(.switchApps, steps: 1)
        let postCommand: (Bool) -> Void = { events.append(.command($0)) }
        let postTab: (Bool) -> Void = { events.append(.tab($0)) }
        var first: AppSwitchCoordinator? = try XCTUnwrap(AppSwitchCoordinator(
            output: output, scheduler: clock, postCommand: postCommand, postTab: postTab))
        let zoom = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(output.enqueue(RotationInterpreter().rotate(zoom, delta: 1023, at: 0), for: zoom))
        XCTAssertTrue(first?.enqueue(RotationInterpreter().rotate(binding, delta: 2, at: 0), for: binding) == true)
        turns.removeFirst()()
        XCTAssertEqual(events, [.command(true), .tab(true)])
        XCTAssertEqual(clock.pendingCount, 0)

        first = nil
        let second = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock,
                                                        postCommand: postCommand, postTab: postTab))
        XCTAssertTrue(second.enqueue(RotationInterpreter().rotate(binding, delta: -1, at: 0), for: binding))
        turns.removeFirst()()
        XCTAssertEqual(events, [.command(true), .tab(true), .command(false), .command(true), .tab(false)])
        clock.advance(by: 0.91)
        XCTAssertEqual(events.last, .command(false))
    }

    func testSubsequentRotationResetsTheReleaseDelay() {
        let harness = AppSwitchHarness()
        XCTAssertTrue(harness.rotate(1))
        harness.clock.advance(by: 0.5)
        XCTAssertTrue(harness.rotate(-1))
        harness.clock.advance(by: 0.5)
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .tab(false)])
        harness.clock.advance(by: 0.41)
        XCTAssertEqual(harness.events.last, .command(false))
        XCTAssertFalse(harness.switcher.finish())
    }

    func testRejectedSwitchPreservesTheExistingRequestAndTimer() {
        let harness = AppSwitchHarness()
        XCTAssertTrue(harness.rotate(1))
        XCTAssertFalse(harness.rotate(4097))
        XCTAssertEqual(harness.clock.pendingCount, 1)
        harness.clock.advance(by: 0.91)
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .command(false)])
        XCTAssertFalse(harness.switcher.finish())
    }

    func testEmptyAndInvalidSwitchEffectsDoNotCreateARequest() {
        let harness = AppSwitchHarness()
        let rotation = RotationInterpreter()
        XCTAssertFalse(harness.switcher.finish())
        XCTAssertTrue(harness.switcher.enqueue(rotation.rotate(harness.binding, delta: 0, at: 0),
                                              for: harness.binding))

        let zoom = RotationBinding(.zoom, steps: 1)
        XCTAssertFalse(harness.switcher.enqueue(rotation.rotate(zoom, delta: 1, at: 0), for: zoom))
        let volume = RotationBinding(.volume)
        XCTAssertFalse(harness.switcher.enqueue(rotation.rotate(volume, delta: 1, at: 0), for: harness.binding))
        XCTAssertFalse(harness.switcher.finish())
        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(harness.clock.pendingCount, 0)
    }

    func testShutdownBalancesCommandAndDropsQueuedSwitches() {
        let harness = AppSwitchHarness()
        XCTAssertTrue(harness.rotate(1))
        harness.enqueueBacklog(513)
        XCTAssertTrue(harness.rotate(-1))
        harness.switcher.shutdown()
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .command(false)])
        XCTAssertFalse(harness.switcher.finish())
        XCTAssertFalse(harness.rotate(1))
        harness.runNextTurn()
        harness.clock.advance(by: 1)
        XCTAssertEqual(harness.events, [.command(true), .tab(true), .command(false)])
        XCTAssertEqual(harness.clock.pendingCount, 0)
    }

    func testShutdownDuringCommandDownDoesNotSendTab() throws {
        var commands: [Bool] = []
        let clock = TestClock()
        let output = RotationEffectQueue(scheduleNext: { _ in XCTFail("Unexpected queued turn") },
                                         perform: { _, _ in XCTFail("Unexpected default effect") })
        var switcher: AppSwitchCoordinator!
        switcher = try XCTUnwrap(AppSwitchCoordinator(output: output, scheduler: clock, postCommand: { down in
            commands.append(down)
            if down { switcher.shutdown() }
        }, postTab: { _ in XCTFail("Tab must not follow shutdown") }))
        let binding = RotationBinding(.switchApps, steps: 1)
        XCTAssertTrue(switcher.enqueue(RotationInterpreter().rotate(binding, delta: 1, at: 0), for: binding))
        XCTAssertEqual(commands, [true, false])
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertFalse(switcher.finish())
        switcher = nil
    }
}

private final class CancelHookScheduler: GestureScheduler {
    final class Task: ScheduledGesture {
        let action: () -> Void
        var onCancel: (() -> Void)?
        private(set) var cancelled = false

        init(action: @escaping () -> Void) { self.action = action }

        func cancel() {
            guard !cancelled else { return }
            cancelled = true
            let callback = onCancel
            onCancel = nil
            callback?()
        }

        func fire() {
            guard !cancelled else { return }
            cancelled = true
            action()
        }
    }

    var now: TimeInterval { 0 }
    private(set) var tasks: [Task] = []

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledGesture {
        let task = Task(action: action)
        tasks.append(task)
        return task
    }
}

private final class AppSwitchHarness {
    enum Event: Equatable {
        case command(Bool)
        case tab(Bool)
    }

    let binding = RotationBinding(.switchApps, steps: 1)
    let clock = TestClock()
    let rotation = RotationInterpreter()
    var turns: [() -> Void] = []
    var events: [Event] = []
    var otherEffects = 0

    lazy var output = RotationEffectQueue(scheduleNext: { [unowned self] in self.turns.append($0) },
                                          perform: { [unowned self] _, _ in self.otherEffects += 1 })
    lazy var switcher: AppSwitchCoordinator! = AppSwitchCoordinator(
        output: output, scheduler: clock,
        postCommand: { [unowned self] in self.events.append(.command($0)) },
        postTab: { [unowned self] in self.events.append(.tab($0)) })

    @discardableResult
    func rotate(_ delta: Int) -> Bool {
        rotation.rotate(binding, delta: delta, at: clock.now) { switcher.enqueue($0, for: binding) }
    }

    func enqueueBacklog(_ count: Int) {
        let zoom = RotationBinding(.zoom, steps: 1)
        XCTAssertTrue(output.enqueue(RotationInterpreter().rotate(zoom, delta: count, at: clock.now), for: zoom))
    }

    func runNextTurn() {
        XCTAssertFalse(turns.isEmpty)
        if !turns.isEmpty { turns.removeFirst()() }
    }
}
