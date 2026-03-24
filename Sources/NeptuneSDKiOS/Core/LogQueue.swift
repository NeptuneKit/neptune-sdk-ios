import Foundation

public actor NeptuneLogQueue {
    public static let capacity = 2000

    public enum Storage: Sendable, Equatable {
        case memory
        case sqlite(path: String)
    }

    private let storage: any NeptuneLogQueueBackingStore

    public init() {
        storage = NeptuneInMemoryLogQueueStorage(capacity: Self.capacity)
    }

    public init(capacity: Int = NeptuneLogQueue.capacity, storage: Storage) throws {
        switch storage {
        case .memory:
            self.storage = NeptuneInMemoryLogQueueStorage(capacity: capacity)
        case let .sqlite(path):
            self.storage = try NeptuneSQLiteLogQueueStorage(path: path, defaultCapacity: capacity)
        }
    }

    @discardableResult
    public func append(_ record: NeptuneIngestLogRecord) -> NeptuneLogRecord {
        storage.append(record)
    }

    public func append(contentsOf records: [NeptuneIngestLogRecord]) -> [NeptuneLogRecord] {
        storage.append(contentsOf: records)
    }

    public func snapshot() -> [NeptuneLogRecord] {
        storage.snapshot()
    }

    public func metrics() -> NeptuneMetricsSnapshot {
        storage.metrics()
    }

    public func page(cursor: Int64? = nil, limit: Int = 100) -> NeptuneLogsPage {
        storage.page(cursor: cursor, limit: limit)
    }
}
