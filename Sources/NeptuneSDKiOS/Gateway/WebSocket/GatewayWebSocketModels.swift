import Foundation

public protocol NeptuneGatewayDiscovering: Sendable {
    func discover() async throws -> NeptuneGatewayDiscoveryResult
}

extension NeptuneGatewayDiscoveryClient: NeptuneGatewayDiscovering {}

public struct NeptuneGatewayWebSocketConfiguration: Sendable, Equatable {
    public var platform: String
    public var appId: String
    public var sessionId: String
    public var deviceId: String
    public var heartbeatInterval: TimeInterval
    public var lossTimeout: TimeInterval
    public var discoveryRefreshInterval: TimeInterval
    public var reconnectDelays: [TimeInterval]

    public init(
        platform: String = "ios",
        appId: String = "",
        sessionId: String = "",
        deviceId: String = "",
        heartbeatInterval: TimeInterval = 15,
        lossTimeout: TimeInterval = 45,
        discoveryRefreshInterval: TimeInterval = 15,
        reconnectDelays: [TimeInterval] = [0.5, 1, 2, 4, 8]
    ) {
        self.platform = platform
        self.appId = appId
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.heartbeatInterval = max(0, heartbeatInterval)
        self.lossTimeout = max(0, lossTimeout)
        self.discoveryRefreshInterval = max(0, discoveryRefreshInterval)
        self.reconnectDelays = reconnectDelays.map { max(0, $0) }
    }
}

public struct NeptuneGatewayWebSocketRetryPolicy: Sendable, Equatable {
    public var delays: [TimeInterval]

    public init(delays: [TimeInterval] = [0.5, 1, 2, 4, 8]) {
        self.delays = delays.map { max(0, $0) }
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else {
            return delays.first ?? 0
        }

        guard !delays.isEmpty else {
            return 0
        }

        return delays[min(attempt - 1, delays.count - 1)]
    }
}

struct NeptuneGatewayWebSocketInboundMessage: Decodable, Sendable {
    let type: String
    let command: String?
    let requestId: String?
    let timestamp: String?
}

struct NeptuneGatewayWebSocketHelloMessage: Encodable, Sendable {
    let type: String = "hello"
    let role: String = "sdk"
    let platform: String
    let appId: String
    let sessionId: String
    let deviceId: String
}

struct NeptuneGatewayWebSocketHeartbeatMessage: Encodable, Sendable {
    let type: String = "heartbeat"
    let role: String = "sdk"
    let timestamp: String
}

struct NeptuneGatewayWebSocketCommandAckMessage: Encodable, Sendable {
    let type: String = "command.ack"
    let command: String
    let status: String = "ok"
    let timestamp: String
    let requestId: String?
}

enum NeptuneGatewayWebSocketConnectionOutcome: Sendable, Equatable {
    case connectionLost(reason: String)
    case endpointChanged(NeptuneGatewayDiscoveryResult)
    case stopped
}
