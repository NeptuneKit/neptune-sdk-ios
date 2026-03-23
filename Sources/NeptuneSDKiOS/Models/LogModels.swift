import Foundation

public enum NeptuneLogLevel: String, Codable, Sendable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical
}

public struct NeptuneLogSource: Codable, Sendable, Equatable {
    public var sdkName: String?
    public var sdkVersion: String?
    public var file: String?
    public var function: String?
    public var line: Int?

    public init(
        sdkName: String? = nil,
        sdkVersion: String? = nil,
        file: String? = nil,
        function: String? = nil,
        line: Int? = nil
    ) {
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
        self.file = file
        self.function = function
        self.line = line
    }
}

public struct NeptuneIngestLogRecord: Codable, Sendable, Equatable {
    public var timestamp: String
    public var level: NeptuneLogLevel
    public var message: String
    public var platform: String
    public var appId: String
    public var sessionId: String
    public var deviceId: String
    public var category: String
    public var attributes: [String: String]?
    public var source: NeptuneLogSource?

    public init(
        timestamp: String,
        level: NeptuneLogLevel,
        message: String,
        platform: String,
        appId: String,
        sessionId: String,
        deviceId: String,
        category: String,
        attributes: [String: String]? = nil,
        source: NeptuneLogSource? = nil
    ) {
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

public struct NeptuneLogRecord: Codable, Sendable, Equatable {
    public var id: Int64
    public var timestamp: String
    public var level: NeptuneLogLevel
    public var message: String
    public var platform: String
    public var appId: String
    public var sessionId: String
    public var deviceId: String
    public var category: String
    public var attributes: [String: String]?
    public var source: NeptuneLogSource?

    public init(id: Int64, ingest: NeptuneIngestLogRecord) {
        self.id = id
        self.timestamp = ingest.timestamp
        self.level = ingest.level
        self.message = ingest.message
        self.platform = ingest.platform
        self.appId = ingest.appId
        self.sessionId = ingest.sessionId
        self.deviceId = ingest.deviceId
        self.category = ingest.category
        self.attributes = ingest.attributes
        self.source = ingest.source
    }
}

public struct NeptuneLogsPage: Codable, Sendable, Equatable {
    public var records: [NeptuneLogRecord]
    public var nextCursor: Int64?
    public var hasMore: Bool

    public init(records: [NeptuneLogRecord], nextCursor: Int64?, hasMore: Bool) {
        self.records = records
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct NeptuneHealthSnapshot: Codable, Sendable, Equatable {
    public var ok: Bool
    public var version: String

    public init(ok: Bool = true, version: String) {
        self.ok = ok
        self.version = version
    }
}

public struct NeptuneMetricsSnapshot: Codable, Sendable, Equatable {
    public var totalRecords: Int
    public var droppedOverflow: Int
    public var oldestRecordId: Int64?
    public var newestRecordId: Int64?

    public init(totalRecords: Int, droppedOverflow: Int, oldestRecordId: Int64?, newestRecordId: Int64?) {
        self.totalRecords = totalRecords
        self.droppedOverflow = droppedOverflow
        self.oldestRecordId = oldestRecordId
        self.newestRecordId = newestRecordId
    }
}
