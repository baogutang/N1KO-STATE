import XCTest
@testable import N1KOState

final class ProcessMonitorTests: XCTestCase {
    private struct ComparisonRecord: Codable {
        let elapsedSeconds: Double
        let cpuOverlap: Double
        let memoryOverlap: Double
        let libprocCPU: [ProcSample]
        let referenceCPU: [ProcSample]
        let libprocMemory: [ProcSample]
        let referenceMemory: [ProcSample]
    }

    private struct ComparisonReport: Codable {
        let durationSeconds: Double
        let sampleIntervalSeconds: Double
        let sampleCount: Int
        let medianCPUOverlap: Double
        let medianMemoryOverlap: Double
        let records: [ComparisonRecord]
    }
    func testMemoryRankingUsesTheCompleteSampleSet() {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Performance/process-ranking.json")
        let data = try! Data(contentsOf: fixtureURL)
        let samples = try! JSONDecoder().decode([ProcSample].self, from: data)

        let ranked = ProcessMonitor.rank(samples: samples, limit: 2)
        XCTAssertEqual(ranked.cpu.map(\.id), [1, 2])
        XCTAssertEqual(ranked.memory.map(\.id), [3, 2])
    }

    func testLibprocCPUTimeDeltaUsesNanoseconds() {
        let percent = ProcessMonitor.cpuPercent(
            previousCPUTimeNanoseconds: 1_000_000_000,
            currentCPUTimeNanoseconds: 1_250_000_000,
            previousUptimeNanoseconds: 10_000_000_000,
            currentUptimeNanoseconds: 11_000_000_000
        )
        XCTAssertEqual(percent, 25, accuracy: 0.0001)
    }

    func testLibprocSamplerReturnsCurrentProcess() {
        let samples = ProcessMonitor.sample()
        XCTAssertTrue(samples.contains { $0.id == Int(getpid()) })
        XCTAssertTrue(samples.allSatisfy { $0.memBytes >= 0 && $0.cpu >= 0 })
    }

    func testSustainedLibprocComparisonWhenRequested() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawDuration = environment["N1KO_PROCESS_COMPARISON_SECONDS"],
              let duration = Double(rawDuration), duration > 0 else {
            throw XCTSkip("Set N1KO_PROCESS_COMPARISON_SECONDS for the sustained comparison gate.")
        }
        let interval = max(Double(environment["N1KO_PROCESS_COMPARISON_INTERVAL"] ?? "2") ?? 2, 0.5)
        let output = environment["N1KO_PROCESS_COMPARISON_OUTPUT"]
        let sampler = LibprocProcessSampler()
        _ = sampler.sample()
        let started = Date()
        var records: [ComparisonRecord] = []

        while Date().timeIntervalSince(started) < duration {
            Thread.sleep(forTimeInterval: interval)
            let libproc = sampler.sample().filter { $0.name != "ps" }
            let reference = ProcessMonitor.psFallback().filter { $0.name != "ps" }
            let libprocRank = ProcessMonitor.rank(samples: libproc, limit: 10)
            let referenceRank = ProcessMonitor.rank(samples: reference, limit: 10)
            records.append(ComparisonRecord(
                elapsedSeconds: Date().timeIntervalSince(started),
                cpuOverlap: overlap(libprocRank.cpu, referenceRank.cpu),
                memoryOverlap: overlap(libprocRank.memory, referenceRank.memory),
                libprocCPU: libprocRank.cpu,
                referenceCPU: referenceRank.cpu,
                libprocMemory: libprocRank.memory,
                referenceMemory: referenceRank.memory
            ))
            if records.count % max(Int(30 / interval), 1) == 0 {
                FileHandle.standardError.write(Data("process comparison: \(Int(Date().timeIntervalSince(started)))s\n".utf8))
            }
        }

        let cpuMedian = median(records.map(\.cpuOverlap))
        let memoryMedian = median(records.map(\.memoryOverlap))
        let report = ComparisonReport(durationSeconds: Date().timeIntervalSince(started),
                                      sampleIntervalSeconds: interval,
                                      sampleCount: records.count,
                                      medianCPUOverlap: cpuMedian,
                                      medianMemoryOverlap: memoryMedian,
                                      records: records)
        if let output {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: URL(fileURLWithPath: output), options: .atomic)
        }

        // Reference process launch/collection adds a small amount of wall time
        // to each interval; require sustained coverage without assuming zero
        // collection overhead.
        XCTAssertGreaterThanOrEqual(records.count, max(Int(duration / interval * 0.9), 1))
        XCTAssertGreaterThanOrEqual(cpuMedian, 0.3)
        XCTAssertGreaterThanOrEqual(memoryMedian, 0.5)
    }

    private func overlap(_ lhs: [ProcSample], _ rhs: [ProcSample]) -> Double {
        let left = Set(lhs.map(\.id))
        let right = Set(rhs.map(\.id))
        let denominator = max(min(left.count, right.count), 1)
        return Double(left.intersection(right).count) / Double(denominator)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }
}
