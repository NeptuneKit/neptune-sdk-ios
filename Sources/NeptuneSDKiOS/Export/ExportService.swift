import Foundation

public struct NeptuneExportService: Sendable {
    public static let version = "2.0.0-alpha.1"

    private let queue: NeptuneLogQueue

    public init(queue: NeptuneLogQueue = NeptuneLogQueue()) {
        self.queue = queue
    }

    public func health() async -> NeptuneHealthSnapshot {
        NeptuneHealthSnapshot(version: Self.version)
    }

    public func metrics() async -> NeptuneMetricsSnapshot {
        await queue.metrics()
    }

    public func logs(cursor: Int64? = nil, limit: Int = 100) async -> NeptuneLogsPage {
        await queue.page(cursor: cursor, limit: limit)
    }

    public func ingest(_ record: NeptuneIngestLogRecord) async -> NeptuneLogRecord {
        await queue.append(record)
    }

    public func ingest(_ records: [NeptuneIngestLogRecord]) async -> [NeptuneLogRecord] {
        await queue.append(contentsOf: records)
    }
}
