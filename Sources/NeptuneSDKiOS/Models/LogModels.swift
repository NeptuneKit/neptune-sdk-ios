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

public struct NeptuneViewTreeNode: Codable, Sendable, Equatable {
    public struct Frame: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct Style: Codable, Sendable, Equatable {
        public var typographyUnit: String?
        public var sourceTypographyUnit: String?
        public var platformFontScale: Double?
        public var opacity: Double?
        public var backgroundColor: String?
        public var textColor: String?
        public var fontSize: Double?
        public var lineHeight: Double?
        public var letterSpacing: Double?
        public var fontWeight: String?
        public var fontWeightRaw: String?
        public var borderRadius: Double?
        public var borderWidth: Double?
        public var borderColor: String?
        public var zIndex: Double?
        public var textAlign: String?

        public init(
            typographyUnit: String? = nil,
            sourceTypographyUnit: String? = nil,
            platformFontScale: Double? = nil,
            opacity: Double? = nil,
            backgroundColor: String? = nil,
            textColor: String? = nil,
            fontSize: Double? = nil,
            lineHeight: Double? = nil,
            letterSpacing: Double? = nil,
            fontWeight: String? = nil,
            fontWeightRaw: String? = nil,
            borderRadius: Double? = nil,
            borderWidth: Double? = nil,
            borderColor: String? = nil,
            zIndex: Double? = nil,
            textAlign: String? = nil
        ) {
            self.typographyUnit = typographyUnit
            self.sourceTypographyUnit = sourceTypographyUnit
            self.platformFontScale = platformFontScale
            self.opacity = opacity
            self.backgroundColor = backgroundColor
            self.textColor = textColor
            self.fontSize = fontSize
            self.lineHeight = lineHeight
            self.letterSpacing = letterSpacing
            self.fontWeight = fontWeight
            self.fontWeightRaw = fontWeightRaw
            self.borderRadius = borderRadius
            self.borderWidth = borderWidth
            self.borderColor = borderColor
            self.zIndex = zIndex
            self.textAlign = textAlign
        }
    }

    public struct Constraint: Codable, Sendable, Equatable {
        public var id: String
        public var source: String
        public var relation: String
        public var firstAttribute: String
        public var secondAttribute: String?
        public var firstItem: String?
        public var secondItem: String?
        public var constant: Double
        public var multiplier: Double
        public var priority: Double
        public var isActive: Bool

        public init(
            id: String,
            source: String,
            relation: String,
            firstAttribute: String,
            secondAttribute: String? = nil,
            firstItem: String? = nil,
            secondItem: String? = nil,
            constant: Double,
            multiplier: Double,
            priority: Double,
            isActive: Bool
        ) {
            self.id = id
            self.source = source
            self.relation = relation
            self.firstAttribute = firstAttribute
            self.secondAttribute = secondAttribute
            self.firstItem = firstItem
            self.secondItem = secondItem
            self.constant = constant
            self.multiplier = multiplier
            self.priority = priority
            self.isActive = isActive
        }
    }

    public var id: String
    public var parentId: String?
    public var name: String
    public var frame: Frame?
    public var style: Style?
    public var constraints: [Constraint]?
    public var text: String?
    public var visible: Bool?
    public var children: [NeptuneViewTreeNode]

    public init(
        id: String,
        parentId: String?,
        name: String,
        frame: Frame? = nil,
        style: Style? = nil,
        constraints: [Constraint]? = nil,
        text: String? = nil,
        visible: Bool? = nil,
        children: [NeptuneViewTreeNode]
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.frame = frame
        self.style = style
        self.constraints = constraints
        self.text = text
        self.visible = visible
        self.children = children
    }
}

public struct NeptuneViewTreeSnapshot: Codable, Sendable, Equatable {
    public var snapshotId: String
    public var capturedAt: String
    public var platform: String
    public var roots: [NeptuneViewTreeNode]

    public init(snapshotId: String, capturedAt: String, platform: String, roots: [NeptuneViewTreeNode]) {
        self.snapshotId = snapshotId
        self.capturedAt = capturedAt
        self.platform = platform
        self.roots = roots
    }
}

public enum InspectorPayloadValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([InspectorPayloadValue])
    case object([String: InspectorPayloadValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }

        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let value = try? container.decode([InspectorPayloadValue].self) {
            self = .array(value)
            return
        }

        if let value = try? container.decode([String: InspectorPayloadValue].self) {
            self = .object(value)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON payload value."
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public struct InspectorSnapshot: Codable, Sendable, Equatable {
    public var snapshotId: String
    public var capturedAt: String
    public var platform: String
    public var available: Bool
    public var payload: InspectorPayloadValue?
    public var reason: String?

    public init(
        snapshotId: String,
        capturedAt: String,
        platform: String,
        available: Bool,
        payload: InspectorPayloadValue?,
        reason: String? = nil
    ) {
        self.snapshotId = snapshotId
        self.capturedAt = capturedAt
        self.platform = platform
        self.available = available
        self.payload = payload
        self.reason = reason
    }
}
