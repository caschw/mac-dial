import Foundation
import MacDialKit

struct MainRunLoopScheduler: GestureScheduler {
    var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledGesture {
        TimerGesture(timer: Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() })
    }
}

private struct TimerGesture: ScheduledGesture {
    let timer: Timer
    func cancel() { timer.invalidate() }
}
