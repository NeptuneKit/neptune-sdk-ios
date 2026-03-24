import Foundation
@preconcurrency import GRDB

fileprivate enum NeptuneSQLiteLogQueueSchema {
    static let queueTable = "neptune_log_queue_records"
    static let stateTable = "neptune_log_queue_state"
    static let stateRowID: Int64 = 1

    enum RecordColumn {
        static let id = "id"
        static let timestamp = "timestamp"
        static let level = "level"
        static let message = "message"
        static let platform = "platform"
        static let appId = "appId"
        static let sessionId = "sessionId"
        static let deviceId = "deviceId"
        static let category = "category"
        static let attributesPayload = "attributesPayload"
        static let sourcePayload = "sourcePayload"
    }
}

final class NeptuneSQLiteLogQueueStorage: NeptuneLogQueueBackingStore {
    private let dbQueue: DatabaseQueue

    init(path: String, defaultCapacity: Int) throws {
        let parentDirectory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
        try dbQueue.write { db in
            if try NeptuneQueueState.fetchOne(db, key: NeptuneSQLiteLogQueueSchema.stateRowID) == nil {
                try NeptuneQueueState(
                    id: NeptuneSQLiteLogQueueSchema.stateRowID,
                    nextRecordID: 1,
                    capacity: max(1, defaultCapacity),
                    droppedOverflowCount: 0
                ).insert(db)
            }
        }
    }

    func append(_ record: NeptuneIngestLogRecord) -> NeptuneLogRecord {
        do {
            return try dbQueue.write { db in
                var state = try Self.fetchState(in: db)
                let stored = NeptuneLogRecord(id: state.nextRecordID, ingest: record)
                try NeptuneSQLiteLogRecord(stored).insert(db)
                state.nextRecordID += 1
                try Self.trimOverflowIfNeeded(in: db, state: &state)
                try state.update(db)
                return stored
            }
        } catch {
            preconditionFailure("NeptuneSQLiteLogQueueStorage append failed: \(error)")
        }
    }

    func append(contentsOf records: [NeptuneIngestLogRecord]) -> [NeptuneLogRecord] {
        records.map(append)
    }

    func snapshot() -> [NeptuneLogRecord] {
        do {
            return try dbQueue.read { db in
                try NeptuneSQLiteLogRecord
                    .order(Column(NeptuneSQLiteLogQueueSchema.RecordColumn.id))
                    .fetchAll(db)
                    .map(\.model)
            }
        } catch {
            preconditionFailure("NeptuneSQLiteLogQueueStorage snapshot failed: \(error)")
        }
    }

    func metrics() -> NeptuneMetricsSnapshot {
        do {
            return try dbQueue.read { db in
                let droppedOverflow = try Self.fetchState(in: db).droppedOverflowCount
                let totalRecords = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(NeptuneSQLiteLogQueueSchema.queueTable)") ?? 0
                let oldestRecordId = try Int64.fetchOne(db, sql: "SELECT id FROM \(NeptuneSQLiteLogQueueSchema.queueTable) ORDER BY id ASC LIMIT 1")
                let newestRecordId = try Int64.fetchOne(db, sql: "SELECT id FROM \(NeptuneSQLiteLogQueueSchema.queueTable) ORDER BY id DESC LIMIT 1")
                return NeptuneMetricsSnapshot(
                    totalRecords: totalRecords,
                    droppedOverflow: droppedOverflow,
                    oldestRecordId: oldestRecordId,
                    newestRecordId: newestRecordId
                )
            }
        } catch {
            preconditionFailure("NeptuneSQLiteLogQueueStorage metrics failed: \(error)")
        }
    }

    func page(cursor: Int64?, limit: Int) -> NeptuneLogsPage {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else {
            let hasRecords = !snapshot().isEmpty
            return NeptuneLogsPage(records: [], nextCursor: cursor, hasMore: hasRecords)
        }

        do {
            return try dbQueue.read { db in
                var request = NeptuneSQLiteLogRecord.order(Column(NeptuneSQLiteLogQueueSchema.RecordColumn.id))
                if let cursor {
                    request = request.filter(Column(NeptuneSQLiteLogQueueSchema.RecordColumn.id) > cursor)
                }

                let records = try request.limit(safeLimit + 1).fetchAll(db).map(\.model)
                let hasMore = records.count > safeLimit
                let pageRecords = Array(records.prefix(safeLimit))
                return NeptuneLogsPage(
                    records: pageRecords,
                    nextCursor: pageRecords.last?.id,
                    hasMore: hasMore
                )
            }
        } catch {
            preconditionFailure("NeptuneSQLiteLogQueueStorage page failed: \(error)")
        }
    }

    private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_log_queue") { db in
            try db.create(table: NeptuneSQLiteLogQueueSchema.queueTable) { table in
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.id, .integer).primaryKey(onConflict: .fail, autoincrement: false)
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.timestamp, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.level, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.message, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.platform, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.appId, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.sessionId, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.deviceId, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.category, .text).notNull()
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.attributesPayload, .blob)
                table.column(NeptuneSQLiteLogQueueSchema.RecordColumn.sourcePayload, .blob)
            }

            try db.create(table: NeptuneSQLiteLogQueueSchema.stateTable) { table in
                table.column("id", .integer).primaryKey(onConflict: .replace, autoincrement: false)
                table.column("nextRecordID", .integer).notNull()
                table.column("capacity", .integer).notNull()
                table.column("droppedOverflowCount", .integer).notNull()
            }
        }
        return migrator
    }()

    private static func fetchState(in db: Database) throws -> NeptuneQueueState {
        guard let state = try NeptuneQueueState.fetchOne(db, key: NeptuneSQLiteLogQueueSchema.stateRowID) else {
            throw DatabaseError(resultCode: .SQLITE_ERROR, message: "Queue state row is missing")
        }
        return state
    }

    private static func trimOverflowIfNeeded(in db: Database, state: inout NeptuneQueueState) throws {
        let totalRecords = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(NeptuneSQLiteLogQueueSchema.queueTable)") ?? 0
        let overflow = totalRecords - state.capacity
        guard overflow > 0 else {
            return
        }

        try db.execute(
            sql: "DELETE FROM \(NeptuneSQLiteLogQueueSchema.queueTable) WHERE id IN (SELECT id FROM \(NeptuneSQLiteLogQueueSchema.queueTable) ORDER BY id ASC LIMIT ?)",
            arguments: [overflow]
        )
        state.droppedOverflowCount += overflow
    }
}

private struct NeptuneSQLiteLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = NeptuneSQLiteLogQueueSchema.queueTable

    var id: Int64
    var timestamp: String
    var level: String
    var message: String
    var platform: String
    var appId: String
    var sessionId: String
    var deviceId: String
    var category: String
    var attributesPayload: Data?
    var sourcePayload: Data?

    init(_ model: NeptuneLogRecord) throws {
        id = model.id
        timestamp = model.timestamp
        level = model.level.rawValue
        message = model.message
        platform = model.platform
        appId = model.appId
        sessionId = model.sessionId
        deviceId = model.deviceId
        category = model.category
        attributesPayload = try model.attributes.map(Self.encoder.encode)
        sourcePayload = try model.source.map(Self.encoder.encode)
    }

    var model: NeptuneLogRecord {
        NeptuneLogRecord(
            id: id,
            timestamp: timestamp,
            level: NeptuneLogLevel(rawValue: level) ?? .info,
            message: message,
            platform: platform,
            appId: appId,
            sessionId: sessionId,
            deviceId: deviceId,
            category: category,
            attributes: attributesPayload.flatMap { try? Self.decoder.decode([String: String].self, from: $0) },
            source: sourcePayload.flatMap { try? Self.decoder.decode(NeptuneLogSource.self, from: $0) }
        )
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

private struct NeptuneQueueState: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = NeptuneSQLiteLogQueueSchema.stateTable

    var id: Int64
    var nextRecordID: Int64
    var capacity: Int
    var droppedOverflowCount: Int
}

private extension NeptuneLogRecord {
    init(
        id: Int64,
        timestamp: String,
        level: NeptuneLogLevel,
        message: String,
        platform: String,
        appId: String,
        sessionId: String,
        deviceId: String,
        category: String,
        attributes: [String: String]?,
        source: NeptuneLogSource?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.platform = platform
        self.appId = appId
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.category = category
        self.attributes = attributes
        self.source = source
    }
}
