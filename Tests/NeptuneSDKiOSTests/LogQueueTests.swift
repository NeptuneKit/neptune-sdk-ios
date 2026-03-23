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
}
