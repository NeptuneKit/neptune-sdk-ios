import Foundation
import Vapor

public struct NeptuneExportHTTPServerConfiguration: Sendable, Equatable {
    public var hostname: String

    public init(hostname: String = "0.0.0.0") {
        let normalized = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostname = normalized.isEmpty ? "0.0.0.0" : normalized
    }
}

public struct NeptuneClientCommandRequest: Content, Sendable, Equatable {
    public var requestId: String?
    public var command: String

    public init(requestId: String? = nil, command: String) {
        self.requestId = requestId
        self.command = command
    }
}

public enum NeptuneClientCommandStatus: String, Codable, Sendable, Equatable {
    case ok
    case error
}

public struct NeptuneClientCommandAck: Content, Sendable, Equatable {
    public var requestId: String?
    public var command: String
    public var status: NeptuneClientCommandStatus
    public var message: String?
    public var timestamp: String

    public init(
        requestId: String?,
        command: String,
        status: NeptuneClientCommandStatus,
        message: String?,
        timestamp: String
    ) {
        self.requestId = requestId
        self.command = command
        self.status = status
        self.message = message
        self.timestamp = timestamp
    }
}
