import Foundation
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Gateway WebSocket")
struct GatewayWebSocketClientTests {
    @Test("Startup connects to /v2/ws and sends hello with identity fields")
    func startupConnectsAndSendsHello() async throws {
        let endpoint = URL(string: "http://127.0.0.1:18765")!
        let configuration = NeptuneGatewayWebSocketConfiguration(
            appId: "com.neptune.smoke.demo",
            sessionId: "session-123",
            deviceId: "device-456",
            heartbeatInterval: 5,
            lossTimeout: 30,
            discoveryRefreshInterval: 5,
            reconnectDelays: [0.01]
        )
        let discovery = MockGatewayDiscoveryClient(
            results: [
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: endpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                )
            ]
        )
        let session = MockGatewayWebSocketSession()
        let transport = MockGatewayWebSocketTransport(sessions: [session])
        let client = NeptuneGatewayWebSocketClient(
            discovery: discovery,
            transport: transport,
            configuration: configuration,
            output: { _ in }
        )

        await client.start()

        #expect(await eventually(timeout: 1) {
            await transport.requestedURLsSnapshot().count == 1
        })
        let startupURLs = await transport.requestedURLsSnapshot()
        #expect(startupURLs.first?.absoluteString == "ws://127.0.0.1:18765/v2/ws")

        #expect(await eventually(timeout: 1) {
            await session.sentTextsSnapshot().count >= 1
        })

        let sentTexts = await session.sentTextsSnapshot()
        let sent = try #require(sentTexts.first)
        let payload = try #require(sent.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: payload)
        let dictionary = try #require(json as? [String: Any])

        #expect(dictionary["type"] as? String == "hello")
        #expect(dictionary["role"] as? String == "sdk")
        #expect(dictionary["platform"] as? String == "ios")
        #expect(dictionary["appId"] as? String == "com.neptune.smoke.demo")
        #expect(dictionary["sessionId"] as? String == "session-123")
        #expect(dictionary["deviceId"] as? String == "device-456")

        await client.stop()
    }

    @Test("Heartbeat is sent while the connection stays alive")
    func heartbeatIsSent() async throws {
        let endpoint = URL(string: "http://127.0.0.1:18765")!
        let discovery = MockGatewayDiscoveryClient(
            results: [
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: endpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                )
            ]
        )
        let session = MockGatewayWebSocketSession()
        let transport = MockGatewayWebSocketTransport(sessions: [session])
        let client = NeptuneGatewayWebSocketClient(
            discovery: discovery,
            transport: transport,
            configuration: .init(
                heartbeatInterval: 0.03,
                lossTimeout: 1,
                discoveryRefreshInterval: 1,
                reconnectDelays: [0.01]
            ),
            output: { _ in }
        )

        await client.start()

        #expect(await eventually(timeout: 1) {
            await session.sentTextsSnapshot().count >= 1
        })

        #expect(await eventually(timeout: 1) {
            await session.sentTextsSnapshot().contains(where: { $0.contains(#""type":"heartbeat""#) })
        })

        await client.stop()
    }

    @Test("command.dispatch(ping) is acknowledged immediately")
    func pingDispatchIsAcknowledged() async throws {
        let endpoint = URL(string: "http://127.0.0.1:18765")!
        let discovery = MockGatewayDiscoveryClient(
            results: [
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: endpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                )
            ]
        )
        let session = MockGatewayWebSocketSession()
        let transport = MockGatewayWebSocketTransport(sessions: [session])
        let client = NeptuneGatewayWebSocketClient(
            discovery: discovery,
            transport: transport,
            configuration: .init(
                heartbeatInterval: 5,
                lossTimeout: 30,
                discoveryRefreshInterval: 5,
                reconnectDelays: [0.01]
            ),
            output: { _ in }
        )

        await client.start()

        #expect(await eventually(timeout: 1) {
            await session.sentTextsSnapshot().count >= 1
        })

        await session.pushInbound(
            #"{"type":"command.dispatch","command":"ping","requestId":"req-1"}"#
        )

        #expect(await eventually(timeout: 1) {
            await session.sentTextsSnapshot().contains(where: { $0.contains(#""type":"command.ack""#) })
        })

        let ackTexts = await session.sentTextsSnapshot()
        let ackText = try #require(ackTexts.last)
        let ackData = try #require(ackText.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: ackData)
        let dictionary = try #require(json as? [String: Any])

        #expect(dictionary["type"] as? String == "command.ack")
        #expect(dictionary["command"] as? String == "ping")
        #expect(dictionary["status"] as? String == "ok")
        #expect((dictionary["timestamp"] as? String)?.isEmpty == false)
        #expect(dictionary["requestId"] as? String == "req-1")

        await client.stop()
    }

    @Test("失联后会按退避序列重连")
    func staleConnectionTriggersReconnect() async throws {
        let endpoint = URL(string: "http://127.0.0.1:18765")!
        let discovery = MockGatewayDiscoveryClient(
            results: [
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: endpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                ),
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: endpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                )
            ]
        )
        let firstSession = MockGatewayWebSocketSession()
        let secondSession = MockGatewayWebSocketSession()
        let transport = MockGatewayWebSocketTransport(sessions: [firstSession, secondSession])
        let client = NeptuneGatewayWebSocketClient(
            discovery: discovery,
            transport: transport,
            configuration: .init(
                heartbeatInterval: 0.02,
                lossTimeout: 0.05,
                discoveryRefreshInterval: 1,
                reconnectDelays: [0.01, 0.02, 0.04]
            ),
            output: { _ in }
        )

        await client.start()

        #expect(await eventually(timeout: 1) {
            await transport.requestedURLsSnapshot().count >= 2
        })

        let staleURLs = await transport.requestedURLsSnapshot()
        #expect(staleURLs[0].absoluteString == "ws://127.0.0.1:18765/v2/ws")
        #expect(staleURLs[1].absoluteString == "ws://127.0.0.1:18765/v2/ws")
        #expect(await firstSession.isCancelledSnapshot())

        await client.stop()
    }

    @Test("Discovery endpoint changes trigger reconnect to the new websocket URL")
    func discoveryEndpointChangeTriggersReconnect() async throws {
        let firstEndpoint = URL(string: "http://127.0.0.1:18765")!
        let secondEndpoint = URL(string: "http://127.0.0.1:18766")!
        let discovery = MockGatewayDiscoveryClient(
            results: [
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: firstEndpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                ),
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: secondEndpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18766,
                        version: "2.0.0-alpha.2"
                    )
                )
            ]
        )
        let firstSession = MockGatewayWebSocketSession()
        let secondSession = MockGatewayWebSocketSession()
        let transport = MockGatewayWebSocketTransport(sessions: [firstSession, secondSession])
        let client = NeptuneGatewayWebSocketClient(
            discovery: discovery,
            transport: transport,
            configuration: .init(
                heartbeatInterval: 0.02,
                lossTimeout: 1,
                discoveryRefreshInterval: 0.02,
                reconnectDelays: [0.01]
            ),
            output: { _ in }
        )

        await client.start()

        #expect(await eventually(timeout: 1) {
            await transport.requestedURLsSnapshot().count >= 2
        })

        let changedURLs = await transport.requestedURLsSnapshot()
        #expect(changedURLs[0].absoluteString == "ws://127.0.0.1:18765/v2/ws")
        #expect(changedURLs[1].absoluteString == "ws://127.0.0.1:18766/v2/ws")
        #expect(await firstSession.isCancelledSnapshot())
        #expect(await secondSession.sentTextsSnapshot().contains(where: { $0.contains(#""type":"hello""#) }))

        await client.stop()
    }

    @Test("Retry policy uses 0.5/1/2/4/8s backoff")
    func retryPolicyUsesExpectedBackoff() {
        let policy = NeptuneGatewayWebSocketRetryPolicy(delays: [0.5, 1, 2, 4, 8])

        #expect(policy.delay(forAttempt: 1) == 0.5)
        #expect(policy.delay(forAttempt: 2) == 1)
        #expect(policy.delay(forAttempt: 3) == 2)
        #expect(policy.delay(forAttempt: 4) == 4)
        #expect(policy.delay(forAttempt: 5) == 8)
        #expect(policy.delay(forAttempt: 6) == 8)
    }
}

private func eventually(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.01,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }

        let nanos = UInt64(max(pollInterval, 0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    return await condition()
}

private actor MockGatewayDiscoveryClient: NeptuneGatewayDiscovering {
    private var results: [Result<NeptuneGatewayDiscoveryResult, any Error>]

    init(results: [Result<NeptuneGatewayDiscoveryResult, any Error>]) {
        self.results = results
    }

    func discover() async throws -> NeptuneGatewayDiscoveryResult {
        guard !results.isEmpty else {
            throw NeptuneGatewayWebSocketTestError.discoveryUnavailable
        }

        let result = results.removeFirst()
        return try result.get()
    }
}

private actor MockGatewayWebSocketTransport: NeptuneGatewayWebSocketTransport {
    private var sessions: [MockGatewayWebSocketSession]
    private(set) var requestedURLs: [URL] = []

    init(sessions: [MockGatewayWebSocketSession]) {
        self.sessions = sessions
    }

    func connect(to url: URL) async throws -> any NeptuneGatewayWebSocketSession {
        requestedURLs.append(url)
        guard !sessions.isEmpty else {
            throw NeptuneGatewayWebSocketTestError.transportExhausted
        }

        return sessions.removeFirst()
    }

    func requestedURLsSnapshot() -> [URL] {
        requestedURLs
    }
}

private actor MockGatewayWebSocketSession: NeptuneGatewayWebSocketSession {
    private var sentTexts: [String] = []
    private var inboundQueue: [String?] = []
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var isCancelled = false

    func send(text: String) async throws {
        sentTexts.append(text)
    }

    func receiveText() async throws -> String? {
        if !inboundQueue.isEmpty {
            return inboundQueue.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func pushInbound(_ text: String?) async {
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: text)
        } else {
            inboundQueue.append(text)
        }
    }

    nonisolated func cancel() {
        Task { [weak self] in
            await self?.cancelImpl()
        }
    }

    private func cancelImpl() {
        isCancelled = true
        while !waiters.isEmpty {
            waiters.removeFirst().resume(returning: nil)
        }
    }

    func sentTextsSnapshot() -> [String] {
        sentTexts
    }

    func isCancelledSnapshot() -> Bool {
        isCancelled
    }
}

private enum NeptuneGatewayWebSocketTestError: Error {
    case discoveryUnavailable
    case transportExhausted
}
