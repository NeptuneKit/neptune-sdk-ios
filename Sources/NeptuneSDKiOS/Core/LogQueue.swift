import Foundation

public actor NeptuneLogQueue {
    public static let capacity = 2000

    private var records: [NeptuneLogRecord] = []
    private var nextID: Int64 = 1
    private var droppedOverflowCount: Int = 0

    public init() {}

    @discardableResult
    public func append(_ record: NeptuneIngestLogRecord) -> NeptuneLogRecord {
        let stored = NeptuneLogRecord(id: nextID, ingest: record)
        nextID += 1
        records.append(stored)
        if records.count > Self.capacity {
            records.removeFirst(records.count - Self.capacity)
            droppedOverflowCount += 1
        }
        return stored
    }

    public func append(contentsOf records: [NeptuneIngestLogRecord]) -> [NeptuneLogRecord] {
        records.map { appendSynchronously($0) }
    }

    public func snapshot() -> [NeptuneLogRecord] {
        records
    }

    public func metrics() -> NeptuneMetricsSnapshot {
        NeptuneMetricsSnapshot(
            totalRecords: records.count,
            droppedOverflow: droppedOverflowCount,
            oldestRecordId: records.first?.id,
            newestRecordId: records.last?.id
        )
    }

    public func page(cursor: Int64? = nil, limit: Int = 100) -> NeptuneLogsPage {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else {
            return NeptuneLogsPage(records: [], nextCursor: cursor, hasMore: !records.isEmpty)
        }

        let filtered = records.filter { record in
            guard let cursor else { return true }
            return record.id > cursor
        }

        let pageRecords = Array(filtered.prefix(safeLimit))
        let hasMore = filtered.count > pageRecords.count
        let nextCursor = pageRecords.last?.id
        return NeptuneLogsPage(records: pageRecords, nextCursor: nextCursor, hasMore: hasMore)
    }

    private func appendSynchronously(_ record: NeptuneIngestLogRecord) -> NeptuneLogRecord {
        let stored = NeptuneLogRecord(id: nextID, ingest: record)
        nextID += 1
        records.append(stored)
        if records.count > Self.capacity {
            records.removeFirst(records.count - Self.capacity)
            droppedOverflowCount += 1
        }
        return stored
    }
}
