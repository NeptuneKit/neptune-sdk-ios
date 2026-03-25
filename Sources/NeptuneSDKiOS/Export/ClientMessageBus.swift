import Foundation
import Vapor

public enum BusDirection: String, Codable, Sendable, Equatable {
    case cliToClient = "cli_to_client"
    case clientToCLI = "client_to_cli"
}

public enum BusKind: String, Codable, Sendable, Equatable {
    case command
    case event
    case log
}

public enum BusAckStatus: String, Codable, Sendable, Equatable {
    case ok
    case error
}

public struct ClientBusEvent: Codable, Sendable, Equatable {
    public var name: String
    public var attributes: [String: String]?

    public init(name: String, attributes: [String: String]? = nil) {
        self.name = name
        self.attributes = attributes
    }
}

public struct BusEnvelope: Content, Sendable, Equatable {
    public var requestId: String?
    public var direction: BusDirection
    public var kind: BusKind
    public var command: String?
    public var logRecord: NeptuneIngestLogRecord?
    public var event: ClientBusEvent?
    public var timestamp: String?

    public init(
        requestId: String? = nil,
        direction: BusDirection,
        kind: BusKind,
        command: String? = nil,
        logRecord: NeptuneIngestLogRecord? = nil,
        event: ClientBusEvent? = nil,
        timestamp: String? = nil
    ) {
        self.requestId = requestId
        self.direction = direction
        self.kind = kind
        self.command = command
        self.logRecord = logRecord
        self.event = event
        self.timestamp = timestamp
    }
}

public struct BusAck: Content, Sendable, Equatable {
    public var requestId: String?
    public var direction: BusDirection
    public var command: String?
    public var status: BusAckStatus
    public var message: String?
    public var timestamp: String

    public init(
        requestId: String?,
        direction: BusDirection = .clientToCLI,
        command: String?,
        status: BusAckStatus,
        message: String?,
        timestamp: String
    ) {
        self.requestId = requestId
        self.direction = direction
        self.command = command
        self.status = status
        self.message = message
        self.timestamp = timestamp
    }
}

public struct ClientMessageBus: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func makeLogEnvelope(_ record: NeptuneIngestLogRecord, requestId: String? = nil) -> BusEnvelope {
        BusEnvelope(
            requestId: requestId,
            direction: .clientToCLI,
            kind: .log,
            logRecord: record,
            timestamp: timestampString()
        )
    }

    public func makeEventEnvelope(
        name: String,
        attributes: [String: String]? = nil,
        requestId: String? = nil
    ) -> BusEnvelope {
        BusEnvelope(
            requestId: requestId,
            direction: .clientToCLI,
            kind: .event,
            event: ClientBusEvent(name: name, attributes: attributes),
            timestamp: timestampString()
        )
    }

    public func acknowledgeInboundCommand(_ envelope: BusEnvelope) -> BusAck {
        guard envelope.direction == .cliToClient else {
            return makeAck(for: envelope, status: .error, message: "unsupported direction")
        }

        guard envelope.kind == .command else {
            return makeAck(for: envelope, status: .error, message: "unsupported message kind")
        }

        guard let command = normalizedCommand(from: envelope.command) else {
            return makeAck(for: envelope, status: .error, message: "missing command")
        }

        guard command == "ping" else {
            return makeAck(for: envelope, command: command, status: .error, message: "unsupported command")
        }

        return makeAck(for: envelope, command: command, status: .ok, message: nil)
    }

    private func makeAck(
        for envelope: BusEnvelope,
        command: String? = nil,
        status: BusAckStatus,
        message: String?
    ) -> BusAck {
        BusAck(
            requestId: envelope.requestId,
            direction: .clientToCLI,
            command: command ?? normalizedCommand(from: envelope.command),
            status: status,
            message: message,
            timestamp: timestampString()
        )
    }

    private func normalizedCommand(from command: String?) -> String? {
        guard let command else {
            return nil
        }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func timestampString() -> String {
        ISO8601DateFormatter().string(from: now())
    }
}
