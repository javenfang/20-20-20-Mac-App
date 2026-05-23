import Foundation
import SQLite3
import AppKit
import TwentyGuardCore

// MARK: - Data Models

// Postpone record in JSON
struct PostponeRecord: Codable {
    let duration: Int               // seconds: 60/120/300
    let start_time: Double          // Unix timestamp
    var end_time: Double?           // Unix timestamp or nil
    var status: String              // "active" | "completed" | "interrupted"
}

// Break info in JSON
struct BreakInfo: Codable {
    let planned_duration: Int       // seconds, usually 180
    var actual_duration: Int?       // seconds
    let start_time: Double          // Unix timestamp
    var end_time: Double?           // Unix timestamp or nil
    var status: String              // "active" | "completed" | "interrupted"
}

struct SessionRecord {
    let id: Int64
    let type: SessionType
    let startTime: Date
    let endTime: Date?
    let plannedDuration: Int
    let actualWorkDuration: Int?
    let postponeCount: Int
    let postponeTotalDuration: Int
    let postpones: [PostponeRecord]
    let breakInfo: BreakInfo?
    let breakCompleted: Bool
    let status: SessionStatus

    enum SessionType: String {
        case work = "work"
    }

    enum SessionStatus: String {
        case active = "active"
        case completed = "completed"
        case interrupted = "interrupted"
    }
}

struct DailyStats {
    let date: Date
    let workSessions: Int
    let breakSessions: Int
    let totalPostpones: Int
    let postpone1MinCount: Int
    let postpone2MinCount: Int
    let postpone5MinCount: Int
    let totalWorkMinutes: Int
    let totalBreakMinutes: Int
    let longestWorkMinutes: Int
    let avgPostponesPerSession: Double
}

struct StatsEventInput {
    let type: StatsEventType
    let timestamp: Date
    let durationSeconds: Int?
    let endTime: Date?
    let nightKey: String?
    let context: [String: String]

    init(
        type: StatsEventType,
        timestamp: Date = Date(),
        durationSeconds: Int? = nil,
        endTime: Date? = nil,
        nightKey: String? = nil,
        context: [String: String] = [:]
    ) {
        self.type = type
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.endTime = endTime
        self.nightKey = nightKey
        self.context = context
    }
}

// MARK: - Database Errors

enum DatabaseError: Error {
    case connectionFailed
    case queryFailed(String)
    case transactionFailed
    case invalidState
}

// MARK: - StatsDatabase

class StatsDatabase {
    static let shared = StatsDatabase()

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.javengroup.twentyguard.database", qos: .userInitiated)
    private let fileManager = FileManager.default
    private let databaseURLOverride: URL?
    private var isValid = false

    private var databaseURL: URL {
        if let databaseURLOverride {
            try? fileManager.createDirectory(at: databaseURLOverride.deletingLastPathComponent(), withIntermediateDirectories: true)
            return databaseURLOverride
        }

        let paths = AppDataPaths.live(fileManager: fileManager)
        try? fileManager.createDirectory(at: paths.appSupportURL, withIntermediateDirectories: true)
        return paths.databaseURL
    }

    init(databaseURL: URL? = nil, registersForAppTermination: Bool = true) {
        self.databaseURLOverride = databaseURL
        setupDatabase()
        if registersForAppTermination {
            registerForAppTermination()
        }
    }

    deinit {
        closeDatabase()
    }

    func waitForIdleForTesting() {
        dbQueue.sync {}
    }

    func closeForTesting() {
        dbQueue.sync {
            closeDatabase()
        }
    }

    func sessionRecordsSinceForTesting(_ startDate: Date) throws -> [StatsSessionRecord] {
        var result: Result<[StatsSessionRecord], Error>!
        dbQueue.sync {
            result = Result { try self.getSessionRecordsSince(startDate) }
        }
        return try result.get()
    }

    // MARK: - Database Setup

    private func setupDatabase() {
        do {
            try openDatabase()
            try createTables()
            isValid = true
            print("✅ Database setup completed successfully")
        } catch {
            print("❌ Database setup failed: \(error)")
            // Try to recover by creating tables manually
            if db != nil {
                createTablesManually()
            }
        }
    }

    private func createTablesManually() {
        if needsSchemaReset() {
            resetOutdatedSchema()
        }

        // Direct table creation without error throwing
        let tables = [
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT CHECK(type IN ('work')) NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL,
                status TEXT CHECK(status IN ('active', 'completed', 'interrupted')) DEFAULT 'active',

                planned_duration INTEGER DEFAULT 1800,
                actual_work_duration INTEGER,
                postpone_count INTEGER DEFAULT 0,
                postpone_total_duration INTEGER DEFAULT 0,
                postpones TEXT,
                break_info TEXT,
                break_completed INTEGER DEFAULT 0,

                created_at REAL DEFAULT (strftime('%s', 'now'))
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS stats_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_type TEXT NOT NULL,
                timestamp REAL NOT NULL,
                duration_seconds INTEGER,
                end_timestamp REAL,
                night_key TEXT,
                context TEXT,
                created_at REAL DEFAULT (strftime('%s', 'now'))
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS daily_summary (
                date TEXT PRIMARY KEY,
                work_sessions INTEGER DEFAULT 0,
                break_sessions INTEGER DEFAULT 0,
                total_work_minutes INTEGER DEFAULT 0,
                total_break_minutes INTEGER DEFAULT 0,
                total_postpones INTEGER DEFAULT 0,
                postpone_1min_count INTEGER DEFAULT 0,
                postpone_2min_count INTEGER DEFAULT 0,
                postpone_5min_count INTEGER DEFAULT 0,
                longest_work_minutes INTEGER DEFAULT 0,
                longest_break_minutes INTEGER DEFAULT 0,
                updated_at REAL DEFAULT (strftime('%s', 'now'))
            )
            """
        ]

        for sql in tables {
            sqlite3_exec(db, sql, nil, nil, nil)
        }

        isValid = true
        print("✅ Database tables created (v1.2.0), database is now valid")
    }

    private func needsSchemaReset() -> Bool {
        // Check if sessions table has the new JSON fields
        var stmt: OpaquePointer?
        let query = "PRAGMA table_info(sessions)"

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }

        var hasSessionsTable = false
        var hasPostponesField = false
        var hasBreakInfoField = false

        while sqlite3_step(stmt) == SQLITE_ROW {
            hasSessionsTable = true
            if let namePtr = sqlite3_column_text(stmt, 1) {
                let columnName = String(cString: namePtr)
                if columnName == "postpones" {
                    hasPostponesField = true
                }
                if columnName == "break_info" {
                    hasBreakInfoField = true
                }
            }
        }

        sqlite3_finalize(stmt)

        // Reset if a local development database exists without the current JSON fields.
        return hasSessionsTable && (!hasPostponesField || !hasBreakInfoField)
    }

    private func resetOutdatedSchema() {
        print("⚠️ Detected outdated local database schema, resetting tables...")

        // Rename old table
        sqlite3_exec(db, "ALTER TABLE sessions RENAME TO sessions_v1_backup", nil, nil, nil)

        // Clear daily summary
        sqlite3_exec(db, "DELETE FROM daily_summary", nil, nil, nil)

        // Drop old postpone_events table if exists
        sqlite3_exec(db, "DROP TABLE IF EXISTS postpone_events", nil, nil, nil)

        print("✅ Schema reset completed: previous sessions table backed up to sessions_v1_backup")
    }

    private func openDatabase() throws {
        let dbPath = databaseURL.path

        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Unable to open database: \(errorMessage)")
            throw DatabaseError.connectionFailed
        }

        // Enable foreign keys and WAL mode for better concurrency
        try executeSQL("PRAGMA foreign_keys = ON")
        try executeSQL("PRAGMA journal_mode = WAL")

        print("✅ Database opened successfully at \(dbPath)")
    }

    // MARK: - JSON Helper Methods

    private func parsePostpones(_ jsonString: String?) -> [PostponeRecord] {
        guard let jsonString = jsonString,
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PostponeRecord].self, from: data)
        } catch {
            print("⚠️ Failed to parse postpones JSON: \(error)")
            return []
        }
    }

    private func serializePostpones(_ postpones: [PostponeRecord]) -> String {
        do {
            let data = try JSONEncoder().encode(postpones)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            print("⚠️ Failed to serialize postpones: \(error)")
            return "[]"
        }
    }

    private func parseBreakInfo(_ jsonString: String?) -> BreakInfo? {
        guard let jsonString = jsonString,
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(BreakInfo.self, from: data)
        } catch {
            print("⚠️ Failed to parse break_info JSON: \(error)")
            return nil
        }
    }

    private func serializeBreakInfo(_ breakInfo: BreakInfo?) -> String? {
        guard let breakInfo = breakInfo else {
            return nil
        }

        do {
            let data = try JSONEncoder().encode(breakInfo)
            return String(data: data, encoding: .utf8)
        } catch {
            print("⚠️ Failed to serialize break_info: \(error)")
            return nil
        }
    }

    private func serializeContext(_ context: [String: String]) -> String {
        guard !context.isEmpty else { return "{}" }
        do {
            let data = try JSONEncoder().encode(context)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            print("⚠️ Failed to serialize stats event context: \(error)")
            return "{}"
        }
    }

    private func parseContext(_ jsonString: String?) -> [String: String] {
        guard let jsonString,
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            isValid = false
            print("📊 Database closed")
        }
    }

    private func registerForAppTermination() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleAppTermination() {
        closeDatabase()
    }

    private func createTables() throws {
        if needsSchemaReset() {
            resetOutdatedSchema()
        }

        let createSessionsTable = """
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT CHECK(type IN ('work')) NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL,
                status TEXT CHECK(status IN ('active', 'completed', 'interrupted')) DEFAULT 'active',

                planned_duration INTEGER DEFAULT 1800,
                actual_work_duration INTEGER,
                postpone_count INTEGER DEFAULT 0,
                postpone_total_duration INTEGER DEFAULT 0,
                postpones TEXT,
                break_info TEXT,
                break_completed INTEGER DEFAULT 0,

                created_at REAL DEFAULT (strftime('%s', 'now'))
            )
        """

        let createDailySummaryTable = """
            CREATE TABLE IF NOT EXISTS daily_summary (
                date TEXT PRIMARY KEY,
                work_sessions INTEGER DEFAULT 0,
                break_sessions INTEGER DEFAULT 0,
                total_postpones INTEGER DEFAULT 0,
                postpone_1min_count INTEGER DEFAULT 0,
                postpone_2min_count INTEGER DEFAULT 0,
                postpone_5min_count INTEGER DEFAULT 0,
                total_work_minutes INTEGER DEFAULT 0,
                total_break_minutes INTEGER DEFAULT 0,
                longest_work_minutes INTEGER DEFAULT 0,
                longest_break_minutes INTEGER DEFAULT 0,
                updated_at REAL DEFAULT (strftime('%s', 'now'))
            )
        """

        let createStatsEventsTable = """
            CREATE TABLE IF NOT EXISTS stats_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_type TEXT NOT NULL,
                timestamp REAL NOT NULL,
                duration_seconds INTEGER,
                end_timestamp REAL,
                night_key TEXT,
                context TEXT,
                created_at REAL DEFAULT (strftime('%s', 'now'))
            )
        """

        // Create indices
        let indices = [
            "CREATE INDEX IF NOT EXISTS idx_sessions_date ON sessions(date(start_time, 'unixepoch'))",
            "CREATE INDEX IF NOT EXISTS idx_sessions_type ON sessions(type)",
            "CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status)",
            "CREATE INDEX IF NOT EXISTS idx_sessions_start_time ON sessions(start_time)",
            "CREATE INDEX IF NOT EXISTS idx_stats_events_timestamp ON stats_events(timestamp)",
            "CREATE INDEX IF NOT EXISTS idx_stats_events_type ON stats_events(event_type)",
            "CREATE INDEX IF NOT EXISTS idx_stats_events_night_key ON stats_events(night_key)"
        ]

        try dbQueue.sync {
            try executeSQL(createSessionsTable)
            try executeSQL(createStatsEventsTable)
            try executeSQL(createDailySummaryTable)

            for index in indices {
                try executeSQL(index)
            }
        }
    }

    private func executeSQL(_ sql: String) throws {
        guard db != nil else { throw DatabaseError.invalidState }

        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ SQL Error: \(errorMessage)")
            print("   SQL: \(sql)")
            throw DatabaseError.queryFailed(errorMessage)
        }
    }

    // MARK: - Transaction Support

    private func withTransaction<T>(_ block: () throws -> T) throws -> T {
        try executeSQL("BEGIN TRANSACTION")
        do {
            let result = try block()
            try executeSQL("COMMIT")
            return result
        } catch {
            try executeSQL("ROLLBACK")
            throw error
        }
    }

    // MARK: - Core Session Management

    func startWorkSession(plannedDuration: Int, startTime: Date? = nil, completion: @escaping (Result<Int64, Error>) -> Void) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else {
                completion(.failure(DatabaseError.invalidState))
                return
            }

            do {
                let sessionId = try self.withTransaction {
                    // End any active sessions first
                    try self.endActiveSessionInternal()

                    let sql = """
                        INSERT INTO sessions (type, start_time, planned_duration, status, postpones, break_info, break_completed)
                        VALUES ('work', ?, ?, 'active', '[]', NULL, 0)
                    """

                    var statement: OpaquePointer?
                    defer { sqlite3_finalize(statement) }

                    guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                        throw DatabaseError.queryFailed("Failed to prepare work session insert")
                    }

                    let sessionStartTime = startTime?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                    sqlite3_bind_double(statement, 1, sessionStartTime)
                    sqlite3_bind_int(statement, 2, Int32(plannedDuration))

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw DatabaseError.queryFailed("Failed to insert work session")
                    }

                    let sessionId = sqlite3_last_insert_rowid(self.db)
                    print("📊 Started work session #\(sessionId) (v1.2.0)")
                    return sessionId
                }
                completion(.success(sessionId))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func startWorkSession(plannedDuration: Int, startTime: Date? = nil) -> Int64? {
        var result: Int64?
        let semaphore = DispatchSemaphore(value: 0)

        startWorkSession(plannedDuration: plannedDuration, startTime: startTime) { res in
            switch res {
            case .success(let id):
                result = id
                let timeDesc = startTime != nil ? "at \(startTime!)" : "now"
                print("✅ Database: Work session created with id \(id) starting \(timeDesc)")
            case .failure(let error):
                print("❌ Database: Failed to create work session - \(error)")
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // Start break - creates break_info JSON in the work session
    func startBreak(plannedDuration: Int) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else { return }

            do {
                try self.withTransaction {
                    // Attach the break to the latest work session. Manual breaks may have already
                    // completed the work session before the overlay is shown.
                    guard let sessionId = try self.getLatestWorkSessionForBreakInternal() else {
                        print("⚠️ No work session available to start break")
                        return
                    }

                    let now = Date().timeIntervalSince1970
                    try self.endSessionInternal(sessionId: sessionId, at: now)

                    // Create break_info JSON
                    let breakInfo = BreakInfo(
                        planned_duration: plannedDuration,
                        actual_duration: nil,
                        start_time: now,
                        end_time: nil,
                        status: "active"
                    )

                    let breakInfoJSON = self.serializeBreakInfo(breakInfo)

                    let updateSQL = """
                        UPDATE sessions
                        SET break_info = ?
                        WHERE id = ?
                    """

                    var statement: OpaquePointer?
                    defer { sqlite3_finalize(statement) }

                    guard sqlite3_prepare_v2(self.db, updateSQL, -1, &statement, nil) == SQLITE_OK else {
                        throw DatabaseError.queryFailed("Failed to prepare start break")
                    }

                    if let json = breakInfoJSON {
                        sqlite3_bind_text(statement, 1, (json as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statement, 1)
                    }
                    sqlite3_bind_int64(statement, 2, sessionId)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw DatabaseError.queryFailed("Failed to start break")
                    }

                    print("📊 Started break for session #\(sessionId) (v1.2.0)")
                }
            } catch {
                print("❌ Failed to start break: \(error)")
            }
        }
    }

    // Complete break - updates break_info and marks work session as completed
    func completeBreak() {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else { return }

            do {
                try self.withTransaction {
                    // Find session with incomplete break (not necessarily active)
                    let findSQL = """
                        SELECT id FROM sessions
                        WHERE break_info IS NOT NULL
                          AND break_completed = 0
                          AND type = 'work'
                        ORDER BY start_time DESC
                        LIMIT 1
                    """

                    var findStmt: OpaquePointer?
                    defer { sqlite3_finalize(findStmt) }

                    guard sqlite3_prepare_v2(self.db, findSQL, -1, &findStmt, nil) == SQLITE_OK,
                          sqlite3_step(findStmt) == SQLITE_ROW else {
                        print("⚠️ No session with incomplete break found")
                        return
                    }

                    let sessionId = sqlite3_column_int64(findStmt, 0)
                    print("📊 Found session #\(sessionId) with incomplete break")

                    // Read current break_info
                    let selectSQL = "SELECT break_info FROM sessions WHERE id = ?"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }

                    guard sqlite3_prepare_v2(self.db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
                        throw DatabaseError.queryFailed("Failed to prepare select break_info")
                    }

                    sqlite3_bind_int64(selectStmt, 1, sessionId)

                    var breakInfo: BreakInfo?
                    if sqlite3_step(selectStmt) == SQLITE_ROW {
                        if let jsonPtr = sqlite3_column_text(selectStmt, 0) {
                            let jsonString = String(cString: jsonPtr)
                            breakInfo = self.parseBreakInfo(jsonString)
                        }
                    }

                    guard var breakInfo = breakInfo else {
                        print("⚠️ No active break to complete")
                        return
                    }

                    // Update break_info
                    let now = Date().timeIntervalSince1970
                    breakInfo.end_time = now
                    breakInfo.actual_duration = Int(now - breakInfo.start_time)
                    breakInfo.status = "completed"

                    let breakInfoJSON = self.serializeBreakInfo(breakInfo)

                    // Update session - only update break fields, don't modify work session status/end_time
                    let updateSQL = """
                        UPDATE sessions
                        SET break_info = ?,
                            break_completed = 1
                        WHERE id = ?
                    """

                    var statement: OpaquePointer?
                    defer { sqlite3_finalize(statement) }

                    guard sqlite3_prepare_v2(self.db, updateSQL, -1, &statement, nil) == SQLITE_OK else {
                        throw DatabaseError.queryFailed("Failed to prepare complete break")
                    }

                    if let json = breakInfoJSON {
                        sqlite3_bind_text(statement, 1, (json as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statement, 1)
                    }
                    sqlite3_bind_int64(statement, 2, sessionId)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw DatabaseError.queryFailed("Failed to complete break")
                    }

                    print("📊 Completed break for session #\(sessionId) (v1.2.0)")
                }
            } catch {
                print("❌ Failed to complete break: \(error)")
            }
        }
    }

    func recordPostpone(minutes: Int) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else { return }

            do {
                try self.withTransaction {
                    // Postpone happens while the break overlay is active, after the
                    // work session has already been completed and linked to break_info.
                    guard let sessionId = try self.getPostponeTargetSessionIdInternal() else {
                        print("⚠️ No work or break session to postpone")
                        return
                    }

                    // 1. Read current postpones JSON
                    let selectSQL = "SELECT postpones FROM sessions WHERE id = ?"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }

                    guard sqlite3_prepare_v2(self.db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
                        throw DatabaseError.queryFailed("Failed to prepare select postpones")
                    }

                    sqlite3_bind_int64(selectStmt, 1, sessionId)

                    var currentPostpones: [PostponeRecord] = []
                    if sqlite3_step(selectStmt) == SQLITE_ROW {
                        if let jsonPtr = sqlite3_column_text(selectStmt, 0) {
                            let jsonString = String(cString: jsonPtr)
                            currentPostpones = self.parsePostpones(jsonString)
                        }
                    }

                    // 2. Add new postpone record
                    let newPostpone = PostponeRecord(
                        duration: minutes * 60,
                        start_time: Date().timeIntervalSince1970,
                        end_time: nil,
                        status: "active"
                    )
                    currentPostpones.append(newPostpone)

                    // 3. Update database
                    let updateSQL = """
                        UPDATE sessions
                        SET postpone_count = postpone_count + 1,
                            postpone_total_duration = postpone_total_duration + ?,
                            postpones = ?
                        WHERE id = ?
                    """

                    var statement: OpaquePointer?
                    defer { sqlite3_finalize(statement) }

                    guard sqlite3_prepare_v2(self.db, updateSQL, -1, &statement, nil) == SQLITE_OK else {
                        throw DatabaseError.queryFailed("Failed to prepare postpone update")
                    }

                    let jsonString = self.serializePostpones(currentPostpones)
                    sqlite3_bind_int(statement, 1, Int32(minutes * 60))
                    sqlite3_bind_text(statement, 2, (jsonString as NSString).utf8String, -1, nil)
                    sqlite3_bind_int64(statement, 3, sessionId)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw DatabaseError.queryFailed("Failed to update postpone")
                    }

                    print("📊 Recorded \(minutes) minute postpone for session #\(sessionId) (v1.2.0)")
                }
            } catch {
                print("❌ Failed to record postpone: \(error)")
            }
        }
    }

    func endActiveSession() {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else { return }

            do {
                try self.endActiveSessionInternal()
            } catch {
                print("❌ Failed to end active session: \(error)")
            }
        }
    }

    private func endActiveSessionInternal() throws {
        let sql = """
            UPDATE sessions
            SET end_time = ?,
                actual_work_duration = CAST((? - start_time) AS INTEGER),
                status = 'completed'
            WHERE status = 'active'
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed("Failed to prepare session end update")
        }

        let now = Date().timeIntervalSince1970
        sqlite3_bind_double(statement, 1, now)
        sqlite3_bind_double(statement, 2, now)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed("Failed to end active session")
        }

        let changes = sqlite3_changes(db)
        if changes > 0 {
            print("📊 Ended \(changes) active session(s) (v1.2.0)")
        }
    }

    private func endSessionInternal(sessionId: Int64, at endTime: TimeInterval) throws {
        let sql = """
            UPDATE sessions
            SET end_time = ?,
                actual_work_duration = CAST((? - start_time) AS INTEGER),
                status = 'completed'
            WHERE id = ? AND status = 'active'
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed("Failed to prepare session end update")
        }

        sqlite3_bind_double(statement, 1, endTime)
        sqlite3_bind_double(statement, 2, endTime)
        sqlite3_bind_int64(statement, 3, sessionId)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed("Failed to end session")
        }

        if sqlite3_changes(db) > 0 {
            print("📊 Ended work session #\(sessionId) before break")
        }
    }

    private func getActiveWorkSessionIdInternal() throws -> Int64? {
        let sql = """
            SELECT id FROM sessions
            WHERE status = 'active' AND type = 'work'
            ORDER BY start_time DESC
            LIMIT 1
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed("Failed to prepare active session query")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func getPostponeTargetSessionIdInternal() throws -> Int64? {
        let sql = """
            SELECT id FROM sessions
            WHERE type = 'work'
              AND (
                (break_info IS NOT NULL AND break_completed = 0)
                OR status = 'active'
              )
            ORDER BY
              CASE WHEN break_info IS NOT NULL AND break_completed = 0 THEN 0 ELSE 1 END,
              start_time DESC
            LIMIT 1
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed("Failed to prepare postpone target query")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func getLatestWorkSessionForBreakInternal() throws -> Int64? {
        let sql = """
            SELECT id FROM sessions
            WHERE type = 'work'
              AND break_info IS NULL
              AND status IN ('active', 'completed')
            ORDER BY start_time DESC
            LIMIT 1
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed("Failed to prepare break session query")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return sqlite3_column_int64(statement, 0)
    }

    // MARK: - Long-Lived Stats Events

    func recordStatsEvent(_ input: StatsEventInput) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else { return }

            let sql = """
                INSERT INTO stats_events (
                    event_type,
                    timestamp,
                    duration_seconds,
                    end_timestamp,
                    night_key,
                    context
                )
                VALUES (?, ?, ?, ?, ?, ?)
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                print("❌ Failed to prepare stats event insert")
                return
            }

            sqlite3_bind_text(statement, 1, (input.type.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 2, input.timestamp.timeIntervalSince1970)
            if let durationSeconds = input.durationSeconds {
                sqlite3_bind_int(statement, 3, Int32(durationSeconds))
            } else {
                sqlite3_bind_null(statement, 3)
            }
            if let endTime = input.endTime {
                sqlite3_bind_double(statement, 4, endTime.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            if let nightKey = input.nightKey {
                sqlite3_bind_text(statement, 5, (nightKey as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            let context = self.serializeContext(input.context)
            sqlite3_bind_text(statement, 6, (context as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ Failed to insert stats event: \(input.type.rawValue)")
            }
        }
    }

    // MARK: - Async Query Methods

    func getTodayStats(completion: @escaping (Result<DailyStats, Error>) -> Void) {
        dbQueue.async { [weak self] in
            guard let self = self else {
                print("❌ Database: getTodayStats - self is nil")
                completion(.failure(DatabaseError.invalidState))
                return
            }
            guard self.isValid else {
                print("❌ Database: getTodayStats - database is invalid")
                completion(.failure(DatabaseError.invalidState))
                return
            }
            print("✅ Database: getTodayStats - starting query")

            // Step 1: Get all today's sessions with JSON fields for detailed parsing.
            // Filter out sessions < 60 seconds (app restart artifacts), while still
            // counting the current active session once it has lasted at least a minute.
            let sql = """
                SELECT id,
                       postpones,
                       break_info,
                       effective_work_duration,
                       postpone_count,
                       break_completed
                FROM (
                    SELECT id,
                           postpones,
                           break_info,
                           CASE
                               WHEN status = 'active' THEN CAST((strftime('%s', 'now') - start_time) AS INTEGER)
                               WHEN actual_work_duration IS NOT NULL THEN actual_work_duration
                               WHEN end_time IS NOT NULL THEN CAST((end_time - start_time) AS INTEGER)
                               ELSE 0
                           END AS effective_work_duration,
                           postpone_count,
                           break_completed
                    FROM sessions
                    WHERE date(start_time, 'unixepoch', 'localtime') = date('now', 'localtime')
                      AND type = 'work'
                )
                WHERE effective_work_duration >= 60
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                completion(.failure(DatabaseError.queryFailed("Failed to prepare today stats query")))
                return
            }

            // Accumulators for statistics
            var workSessions = 0
            var breakSessions = 0
            var totalPostpones = 0
            var postpone1MinCount = 0
            var postpone2MinCount = 0
            var postpone5MinCount = 0
            var totalWorkMinutes = 0
            var totalBreakMinutes = 0
            var longestWorkMinutes = 0

            while sqlite3_step(statement) == SQLITE_ROW {
                workSessions += 1

                // Parse postpones JSON
                if let jsonPtr = sqlite3_column_text(statement, 1) {
                    let jsonString = String(cString: jsonPtr)
                    let postpones = self.parsePostpones(jsonString)
                    totalPostpones += postpones.count

                    for postpone in postpones {
                        let minutes = postpone.duration / 60
                        if minutes == 1 {
                            postpone1MinCount += 1
                        } else if minutes == 2 {
                            postpone2MinCount += 1
                        } else if minutes == 5 {
                            postpone5MinCount += 1
                        }
                    }
                }

                // Parse break_info JSON
                if let jsonPtr = sqlite3_column_text(statement, 2) {
                    let jsonString = String(cString: jsonPtr)
                    if let breakInfo = self.parseBreakInfo(jsonString) {
                        if let actualDuration = breakInfo.actual_duration {
                            totalBreakMinutes += actualDuration / 60
                        }
                    }
                }

                // Check if break was completed
                let breakCompleted = sqlite3_column_int(statement, 5)
                if breakCompleted == 1 {
                    breakSessions += 1
                }

                // Work duration
                let workDuration = Int(sqlite3_column_int(statement, 3))
                if workDuration > 0 {
                    let workMinutes = workDuration / 60
                    totalWorkMinutes += workMinutes
                    if workMinutes > longestWorkMinutes {
                        longestWorkMinutes = workMinutes
                    }
                }
            }

            let avgPostpones = workSessions > 0 ? Double(totalPostpones) / Double(workSessions) : 0.0

            let stats = DailyStats(
                date: Date(),
                workSessions: workSessions,
                breakSessions: breakSessions,
                totalPostpones: totalPostpones,
                postpone1MinCount: postpone1MinCount,
                postpone2MinCount: postpone2MinCount,
                postpone5MinCount: postpone5MinCount,
                totalWorkMinutes: totalWorkMinutes,
                totalBreakMinutes: totalBreakMinutes,
                longestWorkMinutes: longestWorkMinutes,
                avgPostponesPerSession: avgPostpones
            )

            print("📊 Database: getTodayStats success - work:\(stats.workSessions) breaks:\(stats.breakSessions) postpones:\(stats.totalPostpones)")
            completion(.success(stats))
        }
    }

    // Synchronous wrapper for backward compatibility
    func getTodayStats() -> DailyStats? {
        var result: DailyStats?
        let semaphore = DispatchSemaphore(value: 0)

        getTodayStats { res in
            switch res {
            case .success(let stats):
                result = stats
                print("📊 Database: getTodayStats success - work:\(stats.workSessions) postpones:\(stats.totalPostpones)")
            case .failure(let error):
                print("❌ Database: getTodayStats failed - \(error)")
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    func getWeeklyStats(completion: @escaping (Result<[(Date, DailyStats)], Error>) -> Void) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else {
                completion(.failure(DatabaseError.invalidState))
                return
            }

            // Get sessions from last 7 days.
            // Filter out sessions < 60 seconds (app restart artifacts), while still
            // counting active sessions once they have lasted at least a minute.
            let sevenDaysAgo = Date().timeIntervalSince1970 - (7 * 24 * 3600)
            let sql = """
                SELECT date(start_time, 'unixepoch', 'localtime') as day,
                       id,
                       postpones,
                       break_info,
                       effective_work_duration,
                       break_completed
                FROM (
                    SELECT start_time,
                           id,
                           postpones,
                           break_info,
                           CASE
                               WHEN status = 'active' THEN CAST((strftime('%s', 'now') - start_time) AS INTEGER)
                               WHEN actual_work_duration IS NOT NULL THEN actual_work_duration
                               WHEN end_time IS NOT NULL THEN CAST((end_time - start_time) AS INTEGER)
                               ELSE 0
                           END AS effective_work_duration,
                           break_completed
                    FROM sessions
                    WHERE start_time > ?
                      AND type = 'work'
                )
                WHERE effective_work_duration >= 60
                ORDER BY day DESC
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                completion(.failure(DatabaseError.queryFailed("Failed to prepare weekly stats query")))
                return
            }

            sqlite3_bind_double(statement, 1, sevenDaysAgo)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current

            // Group results by day
            var dailyData: [String: (workSessions: Int, breakSessions: Int, totalPostpones: Int, p1: Int, p2: Int, p5: Int, workMin: Int, breakMin: Int, longestWork: Int)] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let dateString = sqlite3_column_text(statement, 0) else { continue }
                let day = String(cString: dateString)

                // Initialize day if not exists
                if dailyData[day] == nil {
                    dailyData[day] = (0, 0, 0, 0, 0, 0, 0, 0, 0)
                }

                var data = dailyData[day]!
                data.workSessions += 1

                // Parse postpones JSON
                if let jsonPtr = sqlite3_column_text(statement, 2) {
                    let jsonString = String(cString: jsonPtr)
                    let postpones = self.parsePostpones(jsonString)
                    data.totalPostpones += postpones.count

                    for postpone in postpones {
                        let minutes = postpone.duration / 60
                        if minutes == 1 { data.p1 += 1 }
                        else if minutes == 2 { data.p2 += 1 }
                        else if minutes == 5 { data.p5 += 1 }
                    }
                }

                // Parse break_info JSON
                if let jsonPtr = sqlite3_column_text(statement, 3) {
                    let jsonString = String(cString: jsonPtr)
                    if let breakInfo = self.parseBreakInfo(jsonString),
                       let actualDuration = breakInfo.actual_duration {
                        data.breakMin += actualDuration / 60
                    }
                }

                // Check if break was completed
                if sqlite3_column_int(statement, 5) == 1 {
                    data.breakSessions += 1
                }

                // Work duration
                let workDuration = Int(sqlite3_column_int(statement, 4))
                if workDuration > 0 {
                    let workMinutes = workDuration / 60
                    data.workMin += workMinutes
                    if workMinutes > data.longestWork {
                        data.longestWork = workMinutes
                    }
                }

                dailyData[day] = data
            }

            // Convert to result format
            var results: [(Date, DailyStats)] = []
            for (dayString, data) in dailyData {
                guard let date = dateFormatter.date(from: dayString) else { continue }

                let avgPostpones = data.workSessions > 0 ? Double(data.totalPostpones) / Double(data.workSessions) : 0.0

                let stats = DailyStats(
                    date: date,
                    workSessions: data.workSessions,
                    breakSessions: data.breakSessions,
                    totalPostpones: data.totalPostpones,
                    postpone1MinCount: data.p1,
                    postpone2MinCount: data.p2,
                    postpone5MinCount: data.p5,
                    totalWorkMinutes: data.workMin,
                    totalBreakMinutes: data.breakMin,
                    longestWorkMinutes: data.longestWork,
                    avgPostponesPerSession: avgPostpones
                )

                results.append((date, stats))
            }

            // Sort by date descending
            results.sort { $0.0 > $1.0 }

            completion(.success(results))
        }
    }

    // Synchronous wrapper for backward compatibility
    func getWeeklyStats() -> [(Date, DailyStats)] {
        var result: [(Date, DailyStats)] = []
        let semaphore = DispatchSemaphore(value: 0)

        getWeeklyStats { res in
            if case .success(let stats) = res {
                result = stats
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    func getDashboardSnapshot(now: Date = Date(), completion: @escaping (Result<StatsDashboardSnapshot, Error>) -> Void) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else {
                completion(.failure(DatabaseError.invalidState))
                return
            }

            do {
                let calendar = Calendar.current
                let todayStart = calendar.startOfDay(for: now)
                let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
                let monthComponents = calendar.dateComponents([.year, .month], from: now)
                let monthStart = calendar.date(from: monthComponents) ?? todayStart
                let startDate = min(weekStart, monthStart)
                let records = try self.getSessionRecordsSince(startDate)
                let events = try self.getStatsEventRecordsSince(startDate)
                let engine = StatsEngine(calendar: calendar, now: now)
                completion(.success(engine.dashboard(from: records, events: events)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func getDashboardSnapshot(now: Date = Date()) -> StatsDashboardSnapshot? {
        var result: StatsDashboardSnapshot?
        let semaphore = DispatchSemaphore(value: 0)

        getDashboardSnapshot(now: now) { response in
            if case .success(let snapshot) = response {
                result = snapshot
            } else if case .failure(let error) = response {
                print("❌ Database: getDashboardSnapshot failed - \(error)")
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    func getMonthSnapshot(monthContaining: Date, now: Date = Date(), completion: @escaping (Result<StatsMonthSnapshot, Error>) -> Void) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else {
                completion(.failure(DatabaseError.invalidState))
                return
            }

            do {
                let calendar = Calendar.current
                let components = calendar.dateComponents([.year, .month], from: monthContaining)
                let monthStart = calendar.date(from: components) ?? calendar.startOfDay(for: monthContaining)
                let records = try self.getSessionRecordsSince(monthStart)
                let events = try self.getStatsEventRecordsSince(monthStart)
                let engine = StatsEngine(calendar: calendar, now: now)
                completion(.success(engine.monthSnapshot(for: monthContaining, from: records, events: events)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func getSessionRecordsSince(_ startDate: Date) throws -> [StatsSessionRecord] {
        let sql = """
            SELECT id,
                   start_time,
                   end_time,
                   planned_duration,
                   actual_work_duration,
                   postpone_count,
                   postpone_total_duration,
                   postpones,
                   break_info,
                   break_completed,
                   status
            FROM sessions
            WHERE start_time >= ?
              AND type = 'work'
            ORDER BY start_time ASC
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed("Failed to prepare dashboard stats query")
        }

        sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)

        var records: [StatsSessionRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let startTime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let endTime = optionalDate(statement, column: 2)
            let plannedDuration = Int(sqlite3_column_int(statement, 3))
            let actualWorkDuration = optionalInt(statement, column: 4)
            let postponeCount = Int(sqlite3_column_int(statement, 5))
            let postponeTotalDuration = Int(sqlite3_column_int(statement, 6))
            let postpones = parsePostpones(optionalString(statement, column: 7)).map { record in
                StatsPostponeRecord(
                    durationSeconds: record.duration,
                    startTime: Date(timeIntervalSince1970: record.start_time),
                    endTime: record.end_time.map { Date(timeIntervalSince1970: $0) },
                    status: StatsRecordStatus(rawValue: record.status) ?? .unknown
                )
            }
            let breakRecord = parseBreakInfo(optionalString(statement, column: 8)).map { record in
                StatsBreakRecord(
                    plannedDurationSeconds: record.planned_duration,
                    actualDurationSeconds: record.actual_duration,
                    startTime: Date(timeIntervalSince1970: record.start_time),
                    endTime: record.end_time.map { Date(timeIntervalSince1970: $0) },
                    status: StatsRecordStatus(rawValue: record.status) ?? .unknown
                )
            }
            let breakCompleted = sqlite3_column_int(statement, 9) == 1
            let statusString = optionalString(statement, column: 10) ?? "unknown"

            records.append(
                StatsSessionRecord(
                    id: id,
                    startTime: startTime,
                    endTime: endTime,
                    plannedDurationSeconds: plannedDuration,
                    actualWorkDurationSeconds: actualWorkDuration,
                    recordedPostponeCount: postponeCount,
                    postponeTotalDurationSeconds: postponeTotalDuration,
                    postpones: postpones,
                    breakRecord: breakRecord,
                    breakCompleted: breakCompleted,
                    status: StatsSessionStatus(rawValue: statusString) ?? .unknown
                )
            )
        }

        return records
    }

    private func getStatsEventRecordsSince(_ startDate: Date) throws -> [StatsEventRecord] {
        let sql = """
            SELECT id,
                   event_type,
                   timestamp,
                   duration_seconds,
                   end_timestamp,
                   night_key,
                   context
            FROM stats_events
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed("Failed to prepare stats event query")
        }

        sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)

        var records: [StatsEventRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let eventTypeString = optionalString(statement, column: 1) ?? "unknown"
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let durationSeconds = optionalInt(statement, column: 3)
            let endTime = optionalDate(statement, column: 4)
            let nightKey = optionalString(statement, column: 5)
            let context = parseContext(optionalString(statement, column: 6))

            records.append(StatsEventRecord(
                id: id,
                type: StatsEventType(rawValue: eventTypeString) ?? .unknown,
                timestamp: timestamp,
                durationSeconds: durationSeconds,
                endTime: endTime,
                nightKey: nightKey,
                context: context
            ))
        }

        return records
    }

    private func optionalString(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: text)
    }

    private func optionalInt(_ statement: OpaquePointer?, column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int(statement, column))
    }

    private func optionalDate(_ statement: OpaquePointer?, column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
    }

    // MARK: - Maintenance

    func updateDailySummary() {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else { return }

            // Note: This method is deprecated since stats are now computed on-demand from sessions table
            // Kept for compatibility but uses simplified aggregation without JSON parsing
            let sql = """
                INSERT OR REPLACE INTO daily_summary (
                    date, work_sessions, break_sessions, total_postpones,
                    postpone_1min_count, postpone_2min_count, postpone_5min_count,
                    total_work_minutes, total_break_minutes, longest_work_minutes,
                    updated_at
                )
                SELECT
                    date(start_time, 'unixepoch', 'localtime') as day,
                    COUNT(*),
                    COALESCE(SUM(break_completed), 0),
                    COALESCE(SUM(postpone_count), 0),
                    0,
                    0,
                    0,
                    COALESCE(SUM(actual_work_duration) / 60, 0),
                    0,
                    COALESCE(MAX(actual_work_duration) / 60, 0),
                    strftime('%s', 'now')
                FROM sessions
                WHERE date(start_time, 'unixepoch', 'localtime') = date('now', 'localtime')
                AND type = 'work'
                GROUP BY day
            """

            do {
                try self.executeSQL(sql)
                print("📊 Daily summary updated (simplified, use getTodayStats for accurate data)")
            } catch {
                print("❌ Failed to update daily summary: \(error)")
            }
        }
    }

    func cleanOldData(keepDays: Int = 90) {
        dbQueue.async { [weak self] in
            guard let self = self, self.isValid else { return }

            let cutoffTime = Date().timeIntervalSince1970 - Double(keepDays * 24 * 3600)

            for (table, column) in [("sessions", "start_time"), ("stats_events", "timestamp")] {
                let sql = "DELETE FROM \(table) WHERE \(column) < ?"
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }

                guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                    continue
                }

                sqlite3_bind_double(statement, 1, cutoffTime)

                if sqlite3_step(statement) == SQLITE_DONE {
                    let deleted = sqlite3_changes(self.db)
                    if deleted > 0 {
                        print("🗑️ Cleaned up \(deleted) old \(table) records")
                    }
                }
            }
        }
    }

    // MARK: - Debug Methods

    func exportDatabase() -> URL? {
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats_export_\(Date().timeIntervalSince1970).db")

        do {
            try FileManager.default.copyItem(at: databaseURL, to: exportURL)
            print("📊 Database exported to: \(exportURL.path)")
            return exportURL
        } catch {
            print("❌ Failed to export database: \(error)")
            return nil
        }
    }

    // MARK: - Health Check

    func isDatabaseHealthy() -> Bool {
        return isValid && db != nil
    }

    func repairDatabaseIfNeeded() {
        if !isDatabaseHealthy() {
            print("🔧 Attempting to repair database...")
            closeDatabase()
            setupDatabase()
        }
    }
}
