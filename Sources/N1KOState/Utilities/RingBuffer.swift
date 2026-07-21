import Foundation

/// Fixed-capacity FIFO storage with O(1) append and no `removeFirst` copies.
final class RingBuffer<Element> {
    private var storage: [Element?]
    private var startIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    convenience init(capacity: Int, elements: [Element]) {
        self.init(capacity: capacity)
        for element in elements.suffix(capacity) {
            append(element)
        }
    }

    func append(_ element: Element) {
        if count < capacity {
            storage[(startIndex + count) % capacity] = element
            count += 1
        } else {
            storage[startIndex] = element
            startIndex = (startIndex + 1) % capacity
        }
    }

    func removeAll(keepingCapacity: Bool = true) {
        storage = Array(repeating: nil, count: capacity)
        startIndex = 0
        count = 0
    }

    var elements: [Element] {
        guard count > 0 else { return [] }
        return (0..<count).compactMap { storage[(startIndex + $0) % capacity] }
    }
}
