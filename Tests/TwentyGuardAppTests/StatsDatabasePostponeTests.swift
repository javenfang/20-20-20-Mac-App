import XCTest
@testable import TwentyGuard

final class StatsDatabasePostponeTests: XCTestCase {
    func testPostponeDuringActiveBreakAttachesToBreakSession() throws {
        let databaseURL = temporaryDirectory().appendingPathComponent("stats.db")
        let database = StatsDatabase(databaseURL: databaseURL, registersForAppTermination: false)
        defer { database.closeForTesting() }

        let workStart = Date(timeIntervalSince1970: 1_779_421_512)
        XCTAssertNotNil(database.startWorkSession(plannedDuration: 1_800, startTime: workStart))

        database.startBreak(plannedDuration: 180)
        database.waitForIdleForTesting()

        database.recordPostpone(minutes: 5)
        database.waitForIdleForTesting()

        let records = try database.sessionRecordsSinceForTesting(workStart.addingTimeInterval(-1))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].recordedPostponeCount, 1)
        XCTAssertEqual(records[0].postponeTotalDurationSeconds, 300)
        XCTAssertEqual(records[0].postpones.map { $0.durationSeconds }, [300])
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
