import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Log Queue")
struct LogQueueTests {
    @Test("Overflow drops oldest records and increments counter")
    func overflowDropsOldest() async throws {
        let queue = NeptuneLogQueue()
        for index in 0..<(NeptuneLogQueue.capacity + 3) {
            _ = await queue.append(Self.makeRecord(index: index))
        }

        let snapshot = await queue.snapshot()
        let metrics = await queue.metrics()

        #expect(snapshot.count == NeptuneLogQueue.capacity)
        #expect(metrics.droppedOverflow == 3)
        #expect(snapshot.first?.id == 4)
        #expect(snapshot.last?.id == Int64(NeptuneLogQueue.capacity + 3))
    }

    @Test("Cursor paging is stable")
    func cursorPagingIsStable() async throws {
        let queue = NeptuneLogQueue()
        for index in 0..<5 {
            _ = await queue.append(Self.makeRecord(index: index))
        }

        let firstPage = await queue.page(cursor: nil, limit: 2)
        #expect(firstPage.records.map(\.id) == [1, 2])
        #expect(firstPage.nextCursor == 2)
        #expect(firstPage.hasMore)

        let secondPage = await queue.page(cursor: firstPage.nextCursor, limit: 2)
        #expect(secondPage.records.map(\.id) == [3, 4])
        #expect(secondPage.nextCursor == 4)
        #expect(secondPage.hasMore)

        let finalPage = await queue.page(cursor: secondPage.nextCursor, limit: 2)
        #expect(finalPage.records.map(\.id) == [5])
        #expect(finalPage.nextCursor == 5)
        #expect(!finalPage.hasMore)
    }

    @Test("SQLite mode persists records and cursor paging across queue recreation")
    func sqliteModePersistsRecordsAndPaging() async throws {
        let databasePath = Self.makeTemporarySQLitePath()
        defer { Self.removeSQLiteArtifacts(at: databasePath) }

        let queue = try NeptuneLogQueue(storage: .sqlite(path: databasePath))
        for index in 0..<4 {
            _ = await queue.append(Self.makeRecord(index: index))
        }

        let reopenedQueue = try NeptuneLogQueue(storage: .sqlite(path: databasePath))
        let firstPage = await reopenedQueue.page(cursor: nil, limit: 2)
        #expect(firstPage.records.map(\.id) == [1, 2])
        #expect(firstPage.nextCursor == 2)
        #expect(firstPage.hasMore)

        let secondPage = await reopenedQueue.page(cursor: firstPage.nextCursor, limit: 2)
        #expect(secondPage.records.map(\.id) == [3, 4])
        #expect(secondPage.nextCursor == 4)
        #expect(!secondPage.hasMore)
    }

    @Test("SQLite mode persists capacity and overflow count")
    func sqliteModePersistsCapacityAndOverflowCount() async throws {
        let databasePath = Self.makeTemporarySQLitePath()
        defer { Self.removeSQLiteArtifacts(at: databasePath) }

        let queue = try NeptuneLogQueue(capacity: 3, storage: .sqlite(path: databasePath))
        for index in 0..<5 {
            _ = await queue.append(Self.makeRecord(index: index))
        }

        let initialMetrics = await queue.metrics()
        #expect(initialMetrics.totalRecords == 3)
        #expect(initialMetrics.droppedOverflow == 2)
        #expect(initialMetrics.oldestRecordId == 3)
        #expect(initialMetrics.newestRecordId == 5)

        let reopenedQueue = try NeptuneLogQueue(storage: .sqlite(path: databasePath))
        _ = await reopenedQueue.append(Self.makeRecord(index: 5))

        let reopenedSnapshot = await reopenedQueue.snapshot()
        let reopenedMetrics = await reopenedQueue.metrics()
        #expect(reopenedSnapshot.map(\.id) == [4, 5, 6])
        #expect(reopenedMetrics.totalRecords == 3)
        #expect(reopenedMetrics.droppedOverflow == 3)
        #expect(reopenedMetrics.oldestRecordId == 4)
        #expect(reopenedMetrics.newestRecordId == 6)
    }

    private static func makeRecord(index: Int) -> NeptuneIngestLogRecord {
        NeptuneIngestLogRecord(
            timestamp: "2026-03-23T12:34:56Z",
            level: .info,
            message: "message-\(index)",
            platform: "ios",
            appId: "app-1",
            sessionId: "session-1",
            deviceId: "device-1",
            category: "default",
            attributes: ["index": "\(index)"],
            source: NeptuneLogSource(sdkName: "sdk", sdkVersion: "1.0.0", file: "File.swift", function: "fn()", line: index)
        )
    }

    private static func makeTemporarySQLitePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NeptuneSDKiOSTests-\(UUID().uuidString).sqlite")
            .path
    }

    private static func removeSQLiteArtifacts(at databasePath: String) {
        let fileManager = FileManager.default
        let walPath = "\(databasePath)-wal"
        let shmPath = "\(databasePath)-shm"
        try? fileManager.removeItem(atPath: databasePath)
        try? fileManager.removeItem(atPath: walPath)
        try? fileManager.removeItem(atPath: shmPath)
    }
}
