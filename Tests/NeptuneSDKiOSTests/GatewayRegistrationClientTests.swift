import Foundation
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Gateway Registration")
struct GatewayRegistrationClientTests {
    @Test("Register request targets /v2/clients:register and includes the command URL")
    func registerRequestIncludesExpectedPayload() throws {
        let payload = NeptuneGatewayRegistrationPayload(
            platform: "ios",
            appId: "com.neptune.demo",
            sessionId: "session-123",
            deviceId: "device-456",
            commandUrl: URL(string: "http://127.0.0.1:19000/v2/client/command")!,
            sdkName: "neptune-sdk-ios",
            sdkVersion: "0.1.0"
        )

        let request = try NeptuneURLSessionGatewayRegistrationTransport.makeRequest(
            payload: payload,
            gatewayEndpoint: URL(string: "http://127.0.0.1:18765")!
        )

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString == "http://127.0.0.1:18765/v2/clients:register")

        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(NeptuneGatewayRegistrationPayload.self, from: body)

        #expect(decoded == payload)
    }

    @Test("Registration starts immediately and renews on the configured interval")
    func registrationStartsImmediatelyAndRenews() async throws {
        let gatewayEndpoint = URL(string: "http://127.0.0.1:18765")!
        let discovery = MockGatewayDiscoveryClient(
            results: [
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: gatewayEndpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                ),
                .success(
                    NeptuneGatewayDiscoveryResult(
                        endpoint: gatewayEndpoint,
                        source: .manualDSN,
                        host: "127.0.0.1",
                        port: 18765,
                        version: "2.0.0-alpha.1"
                    )
                )
            ]
        )
        let transport = MockGatewayRegistrationTransport()
        let sleeper = ControlledGatewayRegistrationSleeper()
        let client = NeptuneGatewayRegistrationClient(
            discovery: discovery,
            transport: transport,
            sleeper: sleeper,
            configuration: .init(
                appId: "com.neptune.demo",
                sessionId: "session-123",
                deviceId: "device-456",
                commandUrl: URL(string: "http://127.0.0.1:19000/v2/client/command")!,
                renewInterval: 30,
                sdkName: "neptune-sdk-ios",
                sdkVersion: "0.1.0"
            )
        )

        await client.start()

        #expect(await eventually(timeout: 1) {
            await transport.requestCount() == 1
        })

        let firstRequest = try #require(await transport.request(at: 0))
        #expect(firstRequest.payload.platform == "ios")
        #expect(firstRequest.payload.appId == "com.neptune.demo")
        #expect(firstRequest.payload.deviceId == "device-456")
        #expect(firstRequest.payload.sessionId == "session-123")
        #expect(firstRequest.payload.commandUrl.absoluteString == "http://127.0.0.1:19000/v2/client/command")

        #expect(await sleeper.sleepDurationsSnapshot() == [30])

        await sleeper.advance()

        #expect(await eventually(timeout: 1) {
            await transport.requestCount() == 2
        })

        let secondRequest = try #require(await transport.request(at: 1))
        #expect(secondRequest.payload == firstRequest.payload)

        await client.stop()
        #expect(await sleeper.pendingSleepCount() == 0)
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
            throw MockGatewayRegistrationError.discoveryUnavailable
        }

        let result = results.removeFirst()
        return try result.get()
    }
}

private actor MockGatewayRegistrationTransport: NeptuneGatewayRegistrationTransport {
    private var requests: [RecordedRequest] = []

    struct RecordedRequest: Sendable, Equatable {
        let endpoint: URL
        let payload: NeptuneGatewayRegistrationPayload
    }

    func send(payload: NeptuneGatewayRegistrationPayload, to gatewayEndpoint: URL) async throws {
        requests.append(.init(endpoint: gatewayEndpoint, payload: payload))
    }

    func requestCount() -> Int {
        requests.count
    }

    func request(at index: Int) -> RecordedRequest? {
        guard requests.indices.contains(index) else {
            return nil
        }
        return requests[index]
    }
}

private actor ControlledGatewayRegistrationSleeper: NeptuneGatewayRegistrationSleeping {
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var durations: [TimeInterval] = []

    func sleep(for seconds: TimeInterval) async throws {
        durations.append(seconds)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
        }, onCancel: { [weak self] in
            Task { await self?.cancelPendingSleeps() }
        })
    }

    func advance() {
        guard !waiters.isEmpty else {
            return
        }

        let waiter = waiters.removeFirst()
        waiter.resume()
    }

    func sleepDurationsSnapshot() -> [TimeInterval] {
        durations
    }

    func pendingSleepCount() -> Int {
        waiters.count
    }

    private func cancelPendingSleeps() {
        while !waiters.isEmpty {
            waiters.removeFirst().resume(throwing: CancellationError())
        }
    }
}

private enum MockGatewayRegistrationError: Error {
    case discoveryUnavailable
}

