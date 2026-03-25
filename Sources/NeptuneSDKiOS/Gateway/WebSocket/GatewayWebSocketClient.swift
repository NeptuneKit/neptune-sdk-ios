import Foundation

public actor NeptuneGatewayWebSocketClient {
    private let discovery: any NeptuneGatewayDiscovering
    private let transport: any NeptuneGatewayWebSocketTransport
    private let configuration: NeptuneGatewayWebSocketConfiguration
    private let retryPolicy: NeptuneGatewayWebSocketRetryPolicy
    private let output: @Sendable (String) -> Void
    private var runTask: Task<Void, Never>?
    private var currentSession: (any NeptuneGatewayWebSocketSession)?

    public init(
        discovery: any NeptuneGatewayDiscovering = NeptuneGatewayDiscoveryClient(),
        transport: any NeptuneGatewayWebSocketTransport = NeptuneURLSessionGatewayWebSocketTransport(),
        configuration: NeptuneGatewayWebSocketConfiguration = .init(),
        output: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.discovery = discovery
        self.transport = transport
        self.configuration = configuration
        self.retryPolicy = NeptuneGatewayWebSocketRetryPolicy(delays: configuration.reconnectDelays)
        self.output = output
    }

    public func start() {
        guard runTask == nil else {
            return
        }

        runTask = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }
    }

    public func stop() async {
        let task = runTask
        runTask = nil
        currentSession?.cancel()
        currentSession = nil
        task?.cancel()
        await task?.value
    }

    private func run() async {
        var reconnectAttempt = 0
        var discoveryState = await refreshDiscovery(fallback: nil)

        while !Task.isCancelled {
            guard let currentDiscovery = discoveryState else {
                reconnectAttempt += 1
                await backoff(reconnectAttempt, reason: "discovery unavailable")
                discoveryState = await refreshDiscovery(fallback: nil)
                continue
            }

            guard let websocketURL = Self.makeWebSocketURL(from: currentDiscovery.endpoint) else {
                emit(NeptuneGatewayWebSocketOutputFormatter.connectFailed(
                    endpoint: currentDiscovery.endpoint,
                    error: NeptuneGatewayWebSocketClientError.invalidWebSocketURL
                ))
                reconnectAttempt += 1
                await backoff(reconnectAttempt, reason: "invalid websocket url")
                discoveryState = await refreshDiscovery(fallback: currentDiscovery)
                continue
            }

            do {
                let session = try await transport.connect(to: websocketURL)
                currentSession = session
                reconnectAttempt = 0
                emit(NeptuneGatewayWebSocketOutputFormatter.connected(endpoint: websocketURL))

                try await session.send(text: Self.helloJSON(configuration: configuration))
                emit(NeptuneGatewayWebSocketOutputFormatter.helloSent(endpoint: websocketURL))

                let outcome = await connectionLoop(
                    session: session,
                    currentDiscovery: currentDiscovery
                )

                session.cancel()
                currentSession = nil

                switch outcome {
                case .stopped:
                    return
                case let .endpointChanged(newDiscovery):
                    emit(NeptuneGatewayWebSocketOutputFormatter.endpointChanged(
                        from: currentDiscovery.endpoint,
                        to: newDiscovery.endpoint
                    ))
                    reconnectAttempt = 0
                    discoveryState = newDiscovery
                    continue
                case let .connectionLost(reason):
                    reconnectAttempt += 1
                    emit(NeptuneGatewayWebSocketOutputFormatter.reconnectScheduled(
                        after: retryPolicy.delay(forAttempt: reconnectAttempt),
                        reason: reason
                    ))
                    await backoff(reconnectAttempt, reason: reason)
                    discoveryState = await refreshDiscovery(fallback: currentDiscovery)
                    continue
                }
            } catch {
                currentSession = nil
                reconnectAttempt += 1
                emit(NeptuneGatewayWebSocketOutputFormatter.connectFailed(endpoint: currentDiscovery.endpoint, error: error))
                emit(NeptuneGatewayWebSocketOutputFormatter.reconnectScheduled(
                    after: retryPolicy.delay(forAttempt: reconnectAttempt),
                    reason: error.localizedDescription
                ))
                await backoff(reconnectAttempt, reason: error.localizedDescription)
                discoveryState = await refreshDiscovery(fallback: currentDiscovery)
            }
        }
    }

    private func connectionLoop(
        session: any NeptuneGatewayWebSocketSession,
        currentDiscovery: NeptuneGatewayDiscoveryResult
    ) async -> NeptuneGatewayWebSocketConnectionOutcome {
        let state = ConnectionState(
            lastInboundAt: Date(),
            lastDiscoveryCheckAt: Date()
        )

        return await withTaskGroup(of: NeptuneGatewayWebSocketConnectionOutcome?.self) { group in
            group.addTask { [state, weak self] in
                guard let self else {
                    return .stopped
                }

                return await withTaskCancellationHandler(operation: {
                    while !Task.isCancelled {
                        do {
                            guard let text = try await session.receiveText() else {
                                return .connectionLost(reason: "websocket closed")
                            }

                            await state.markInbound()
                            await self.handleInbound(text, session: session)
                        } catch {
                            return .connectionLost(reason: error.localizedDescription)
                        }
                    }

                    return .stopped
                }, onCancel: {
                    session.cancel()
                })
            }

            group.addTask { [configuration, state, weak self] in
                guard let self else {
                    return .stopped
                }

                while !Task.isCancelled {
                    try? await self.sleep(seconds: configuration.heartbeatInterval)
                    if Task.isCancelled {
                        return .stopped
                    }

                    let now = Date()
                    if configuration.lossTimeout > 0 {
                        let lastInboundAt = await state.getLastInboundAt()
                        if now.timeIntervalSince(lastInboundAt) >= configuration.lossTimeout {
                            return .connectionLost(reason: "heartbeat timeout")
                        }
                    }

                    do {
                        let timestamp = Self.timestampString(from: now)
                        let heartbeatText = try Self.encodeMessage(
                            NeptuneGatewayWebSocketHeartbeatMessage(timestamp: timestamp)
                        )
                        try await session.send(text: heartbeatText)
                        await self.emit(NeptuneGatewayWebSocketOutputFormatter.heartbeatSent(timestamp: timestamp))
                    } catch {
                        return .connectionLost(reason: error.localizedDescription)
                    }

                    if configuration.discoveryRefreshInterval > 0 {
                        let lastDiscoveryCheckAt = await state.getLastDiscoveryCheckAt()
                        if now.timeIntervalSince(lastDiscoveryCheckAt) >= configuration.discoveryRefreshInterval {
                            do {
                                let refreshed = try await self.discovery.discover()
                                await state.markDiscoveryCheck(now)
                                if refreshed.endpoint != currentDiscovery.endpoint {
                                    return .endpointChanged(refreshed)
                                }
                            } catch {
                                await state.markDiscoveryCheck(now)
                                await self.emit(NeptuneGatewayWebSocketOutputFormatter.discoveryCheckFailed(error: error))
                            }
                        }
                    }
                }

                return .stopped
            }

            for await outcome in group {
                if let outcome {
                    group.cancelAll()
                    return outcome
                }
            }

            return .stopped
        }
    }

    private func handleInbound(_ text: String, session: any NeptuneGatewayWebSocketSession) async {
        let message: NeptuneGatewayWebSocketInboundMessage
        do {
            message = try Self.decodeInboundMessage(text)
        } catch {
            return
        }

        switch message.type {
        case "command.dispatch":
            guard message.command == "ping" else {
                return
            }

            let now = Self.timestampString(from: Date())
            let ack = NeptuneGatewayWebSocketCommandAckMessage(
                command: "ping",
                timestamp: now,
                requestId: message.requestId
            )

            do {
                let ackText = try Self.encodeMessage(ack)
                try await session.send(text: ackText)
                emit(NeptuneGatewayWebSocketOutputFormatter.commandDispatchPingAck(timestamp: now))
            } catch {
                return
            }
        default:
            return
        }
    }

    private func refreshDiscovery(fallback: NeptuneGatewayDiscoveryResult?) async -> NeptuneGatewayDiscoveryResult? {
        do {
            return try await discovery.discover()
        } catch {
            if let fallback {
                emit(NeptuneGatewayWebSocketOutputFormatter.discoveryCheckFailed(error: error))
                return fallback
            }

            emit(NeptuneGatewayWebSocketOutputFormatter.discoveryCheckFailed(error: error))
            return nil
        }
    }

    private func backoff(_ attempt: Int, reason: String) async {
        let seconds = retryPolicy.delay(forAttempt: attempt)
        guard seconds > 0 else {
            return
        }

        do {
            try await sleep(seconds: seconds)
        } catch {
            return
        }
    }

    private func emit(_ line: String) {
        output(line)
    }

    private func sleep(seconds: TimeInterval) async throws {
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }

    private static func makeWebSocketURL(from endpoint: URL) -> URL? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            return nil
        }

        let baseURL = components.url ?? endpoint
        return baseURL
            .appendingPathComponent("v2")
            .appendingPathComponent("ws")
    }

    private static func helloJSON(configuration: NeptuneGatewayWebSocketConfiguration) throws -> String {
        try encodeMessage(NeptuneGatewayWebSocketHelloMessage(
            platform: configuration.platform,
            appId: configuration.appId,
            sessionId: configuration.sessionId,
            deviceId: configuration.deviceId
        ))
    }

    private static func encodeMessage<T: Encodable>(_ message: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NeptuneGatewayWebSocketClientError.invalidMessageEncoding
        }
        return text
    }

    private static func decodeInboundMessage(_ text: String) throws -> NeptuneGatewayWebSocketInboundMessage {
        guard let data = text.data(using: .utf8) else {
            throw NeptuneGatewayWebSocketClientError.invalidMessageEncoding
        }

        return try JSONDecoder().decode(NeptuneGatewayWebSocketInboundMessage.self, from: data)
    }

    private static func timestampString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private actor ConnectionState {
    private var lastInboundAt: Date
    private var lastDiscoveryCheckAt: Date

    init(lastInboundAt: Date, lastDiscoveryCheckAt: Date) {
        self.lastInboundAt = lastInboundAt
        self.lastDiscoveryCheckAt = lastDiscoveryCheckAt
    }

    func markInbound(_ date: Date = Date()) {
        lastInboundAt = date
    }

    func markDiscoveryCheck(_ date: Date = Date()) {
        lastDiscoveryCheckAt = date
    }

    func getLastInboundAt() -> Date {
        lastInboundAt
    }

    func getLastDiscoveryCheckAt() -> Date {
        lastDiscoveryCheckAt
    }
}

public enum NeptuneGatewayWebSocketClientError: Error, Sendable, Equatable, LocalizedError {
    case invalidWebSocketURL
    case invalidMessageEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidWebSocketURL:
            return "Unable to convert discovery endpoint into a websocket URL."
        case .invalidMessageEncoding:
            return "Unable to encode or decode websocket payload."
        }
    }
}
