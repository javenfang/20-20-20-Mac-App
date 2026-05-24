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

    func testPostponeExpiryClosesPostponeAndFinalBreakCompletesSameOpportunity() throws {
        let databaseURL = temporaryDirectory().appendingPathComponent("stats.db")
        let database = StatsDatabase(databaseURL: databaseURL, registersForAppTermination: false)
        defer { database.closeForTesting() }

        let workStart = Date(timeIntervalSince1970: 1_779_421_512)
        XCTAssertNotNil(database.startWorkSession(plannedDuration: 1_800, startTime: workStart))

        database.startBreak(plannedDuration: 180)
        database.waitForIdleForTesting()

        database.recordPostpone(minutes: 5)
        database.waitForIdleForTesting()

        database.startBreak(plannedDuration: 180)
        database.waitForIdleForTesting()

        database.completeBreak()
        database.waitForIdleForTesting()

        let records = try database.sessionRecordsSinceForTesting(workStart.addingTimeInterval(-1))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].recordedPostponeCount, 1)
        XCTAssertEqual(records[0].postpones.first?.status, .completed)
        XCTAssertNotNil(records[0].postpones.first?.endTime)
        XCTAssertEqual(records[0].breakRecord?.status, .completed)
        XCTAssertEqual(records[0].breakCompleted, true)
    }

    func testStartingNewWorkSessionInterruptsOpenBreakAndPostponeRecords() throws {
        let databaseURL = temporaryDirectory().appendingPathComponent("stats.db")
        let database = StatsDatabase(databaseURL: databaseURL, registersForAppTermination: false)
        defer { database.closeForTesting() }

        let workStart = Date(timeIntervalSince1970: 1_779_421_512)
        XCTAssertNotNil(database.startWorkSession(plannedDuration: 1_800, startTime: workStart))

        database.startBreak(plannedDuration: 180)
        database.waitForIdleForTesting()

        database.recordPostpone(minutes: 5)
        database.waitForIdleForTesting()

        XCTAssertNotNil(database.startWorkSession(
            plannedDuration: 1_800,
            startTime: workStart.addingTimeInterval(2_400)
        ))
        database.waitForIdleForTesting()

        let records = try database.sessionRecordsSinceForTesting(workStart.addingTimeInterval(-1))

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].breakRecord?.status, .interrupted)
        XCTAssertEqual(records[0].postpones.first?.status, .interrupted)
        XCTAssertNotNil(records[0].postpones.first?.endTime)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
