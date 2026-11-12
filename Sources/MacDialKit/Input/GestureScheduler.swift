import Foundation

/// Scheduling and callbacks must run on the same serial context as dial input.
public protocol GestureScheduler {
    var now: TimeInterval { get }
    /// GestureInterpreter supplies finite, nonnegative intervals. The action
    /// runs at most once and may run before this method returns for zero delay.
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledGesture
}

public protocol ScheduledGesture {
    /// Prevents an action that has not started from running.
    func cancel()
}

public protocol DialActions: AnyObject {
    func perform(_ binding: ClickBinding)
    /// GestureInterpreter supplies a nonzero signed detent count.
    func rotate(_ binding: RotationBinding, delta: Int)
    func mouse(_ action: ClickAction, down: Bool)
    @discardableResult func finishAppSwitch() -> Bool
}

public protocol DialMenu: AnyObject {
    var isVisible: Bool { get }
    /// GestureInterpreter supplies a nonzero signed detent count.
    func move(by delta: Int) -> Bool
    func confirm()
    func dismiss()
}
