import Foundation
import XCTest
@testable import N1KOState

final class HistoryStoreTests: XCTestCase {
    func testDownsampleLeavesSmallSeriesUntouched() {
        let values = [0.1, 0.2, 0.3]
        XCTAssertEqual(HistoryStore.downsampleForDisplay(values, maxSamples: 5), values)
    }

    func testDownsampleCapsDisplayPointCount() {
        let values = (0..<2880).map(Double.init)
        let sampled = HistoryStore.downsampleForDisplay(values, maxSamples: 180)
        XCTAssertEqual(sampled.count, 180)
    }

    func testDownsampleKeepsBucketPeaks() {
        let values = [1.0, 9.0, 2.0, 3.0, 8.0, 4.0]
        let sampled = HistoryStore.downsampleForDisplay(values, maxSamples: 3)
        XCTAssertEqual(sampled, [9.0, 3.0, 8.0])
    }

    func testHistoryPersistenceUsesPrivateDirectoryAndFilePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-history-permissions-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("nested/history.json")

        try HistoryStore.writePrivateHistoryData(Data("{}".utf8), to: url)
        XCTAssertEqual(permissions(url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(permissions(url), 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try HistoryStore.preparePrivateHistoryFile(at: url)
        XCTAssertEqual(permissions(url), 0o600)
    }

    private func permissions(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
