import XCTest
import MacDialKit

final class DialInputReportTests: XCTestCase {
    func testFailedCallbackIsRejectedBeforeExaminingBytes() {
        XCTAssertEqual(decode([], length: Int.max, succeeded: false), .failure(.callbackFailed))
    }

    func testInvalidLengthsAreRejectedBeforeReadingBuffer() {
        for length in [Int.min, -1, 4, Int.max] {
            XCTAssertEqual(decode([1, 0, 0], length: length), .failure(.invalidLength), "length \(length)")
        }
    }

    func testShortReportsAndUnsupportedHeadersAreRejected() {
        for length in 0...2 {
            XCTAssertEqual(decode([1, 0, 0], length: length), .failure(.shortReport), "length \(length)")
        }
        for header: UInt8 in [0, 2, 255] {
            XCTAssertEqual(decode([header, 0, 0]), .failure(.unsupportedHeader(header)))
        }
    }

    func testButtonTransitionsPrecedeRotationAndUnchangedButtonsAreOmitted() {
        XCTAssertEqual(decode([1, 1, 128], wasPressed: false),
                       .success([.button(isPressed: true), .rotation(-128)]))
        XCTAssertEqual(decode([1, 0, 127], wasPressed: true),
                       .success([.button(isPressed: false), .rotation(127)]))
        XCTAssertEqual(decode([1, 255, 0], wasPressed: true), .success([]))
        XCTAssertEqual(decode([1, 254, 0], wasPressed: false), .success([]))
    }

    func testEveryRotationByteUsesSignedReportSemantics() {
        for value in UInt8.min...UInt8.max {
            let delta = Int(Int8(bitPattern: value))
            let expected: [DialInputReport.Event] = delta == 0 ? [] : [.rotation(delta)]
            XCTAssertEqual(decode([1, 0, value, 99]), .success(expected), "byte \(value)")
        }
    }

    private func decode(_ bytes: [UInt8], length: Int? = nil, succeeded: Bool = true,
                        wasPressed: Bool = false) -> Result<[DialInputReport.Event], DialInputReport.Failure> {
        bytes.withUnsafeBufferPointer {
            DialInputReport.decode(succeeded: succeeded, buffer: $0, length: length ?? bytes.count,
                                   wasPressed: wasPressed)
        }
    }
}
