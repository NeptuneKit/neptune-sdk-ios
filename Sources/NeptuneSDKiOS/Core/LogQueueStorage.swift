import Foundation

protocol NeptuneLogQueueBackingStore: AnyObject {
    func append(_ record: NeptuneIngestLogRecord) -> NeptuneLogRecord
    func append(contentsOf records: [NeptuneIngestLogRecord]) -> [NeptuneLogRecord]
    func snapshot() -> [NeptuneLogRecord]
    func metrics() -> NeptuneMetricsSnapshot
    func page(cursor: Int64?, limit: Int) -> NeptuneLogsPage
}

final class NeptuneInMemoryLogQueueStorage: NeptuneLogQueueBackingStore {
    private let capacity: Int
    private var records: [NeptuneLogRecord] = []
    private var nextID: Int64 = 1
    private var droppedOverflowCount: Int = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func append(_ record: NeptuneIngestLogRecord) -> NeptuneLogRecord {
        let stored = NeptuneLogRecord(id: nextID, ingest: record)
        nextID += 1
        records.append(stored)
        trimOverflowIfNeeded()
        return stored
    }

    func append(contentsOf records: [NeptuneIngestLogRecord]) -> [NeptuneLogRecord] {
        records.map(append)
    }

    func snapshot() -> [NeptuneLogRecord] {
        records
    }

    func metrics() -> NeptuneMetricsSnapshot {
        NeptuneMetricsSnapshot(
            totalRecords: records.count,
            droppedOverflow: droppedOverflowCount,
            oldestRecordId: records.first?.id,
            newestRecordId: records.last?.id
        )
    }

    func page(cursor: Int64?, limit: Int) -> NeptuneLogsPage {
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
        return NeptuneLogsPage(records: pageRecords, nextCursor: pageRecords.last?.id, hasMore: hasMore)
    }

    private func trimOverflowIfNeeded() {
        let overflow = records.count - capacity
        guard overflow > 0 else {
            return
        }

        records.removeFirst(overflow)
        droppedOverflowCount += overflow
    }
}
