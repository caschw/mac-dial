/// Validates and interprets the bytes supplied by the native HID callback.
public enum DialInputReport {
    public enum Event: Equatable {
        case button(isPressed: Bool)
        case rotation(Int)
    }

    public enum Failure: Error, Equatable {
        case callbackFailed
        case invalidLength
        case shortReport
        case unsupportedHeader(UInt8)
    }

    /// `buffer` describes the registered buffer's capacity, not the reported length.
    public static func decode(succeeded: Bool, buffer: UnsafeBufferPointer<UInt8>,
                              length: Int, wasPressed: Bool) -> Result<[Event], Failure> {
        guard succeeded else { return .failure(.callbackFailed) }
        guard length >= 0, length <= buffer.count else { return .failure(.invalidLength) }
        guard length >= 3 else { return .failure(.shortReport) }
        guard buffer[0] == 1 else { return .failure(.unsupportedHeader(buffer[0])) }

        let isPressed = buffer[1] & 1 == 1
        let rotation = Int(Int8(bitPattern: buffer[2]))
        var events: [Event] = []
        if isPressed != wasPressed { events.append(.button(isPressed: isPressed)) }
        if rotation != 0 { events.append(.rotation(rotation)) }
        return .success(events)
    }
}
