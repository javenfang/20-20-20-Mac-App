import XCTest
@testable import TwentyGuard

final class LogManagerDebugEventTests: XCTestCase {
    func testSessionDebugEventEncodesActionContext() throws {
        let event = LogEvent(
            timestamp: Date(timeIntervalSince1970: 1_779_600_000),
            eventType: .sessionDebug,
            duration: nil,
            context: [
                "action": "restore_reused_active_work_session",
                "session_id": "42"
            ]
        )

        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains(#""eventType":"session_debug""#))
        XCTAssertTrue(json.contains(#""action":"restore_reused_active_work_session""#))
        XCTAssertTrue(json.contains(#""session_id":"42""#))
    }
}
