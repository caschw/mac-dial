import Foundation

/// Scheduling and callbacks must run on the same serial context as dial input.
public protocol GestureScheduler {
    var now: TimeInterval { get }
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledGesture
}

public protocol ScheduledGesture {
    func cancel()
}

public protocol DialActions: AnyObject {
    func perform(_ binding: ClickBinding)
    func rotate(_ binding: RotationBinding, delta: Int)
    func mouse(_ action: ClickAction, down: Bool)
    @discardableResult func finishAppSwitch() -> Bool
}

public protocol DialMenu: AnyObject {
    var isVisible: Bool { get }
    func move(by delta: Int) -> Bool
    func confirm()
    func dismiss()
}
