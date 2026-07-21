import XCTest
@testable import N1KOState

final class RingBufferTests: XCTestCase {
    func testAppendMaintainsCapacityAndOrder() {
        let buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.append(4)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.elements, [2, 3, 4])
    }

    func testInitializingFromOversizedArrayKeepsNewestElements() {
        let buffer = RingBuffer(capacity: 2, elements: [1, 2, 3, 4])
        XCTAssertEqual(buffer.elements, [3, 4])
    }
}
