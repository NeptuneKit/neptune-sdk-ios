import Foundation
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Gateway Ingest")
struct GatewayIngestClientTests {
    @Test("Gateway ingest request wraps logs in a client_to_cli bus envelope")
    func requestUsesExpectedJSONBody() throws {
        let record = NeptuneIngestLogRecord(
            timestamp: "2026-03-24T10:11:12Z",
            level: .info,
            message: "discovery-triggered gateway ingest",
            platform: "ios",
            appId: "com.neptunekit.demo.ios",
            sessionId: "simulator-session",
            deviceId: "device-1",
            category: "gateway-discovery",
            attributes: [
                "screen": "DemoViewController",
                "gatewaySource": "manualDSN",
                "gatewayVersion": "2.0.0-alpha.1",
                "gatewayEndpoint": "http://127.0.0.1:18765"
            ],
            source: NeptuneLogSource(
                sdkName: "neptune-sdk-ios",
                sdkVersion: "0.1.0",
                file: "DemoViewController.swift",
                function: "ingestGatewayLog(after:)",
                line: 123
            )
        )

        let request = try NeptuneGatewayIngestClient.makeRequest(
            record: record,
            gatewayEndpoint: URL(string: "http://127.0.0.1:18765")!
        )

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString == "http://127.0.0.1:18765/v2/logs:ingest")

        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(BusEnvelope.self, from: body)

        #expect(decoded.direction == .clientToCLI)
        #expect(decoded.kind == .log)
        #expect(decoded.command == nil)
        #expect(decoded.logRecord == record)
    }

    @Test("Gateway raw view tree ingest request uses ui-tree/inspector payload")
    func rawViewTreeRequestUsesExpectedJSONBody() throws {
        let payload: InspectorPayloadValue = .object([
            "roots": .array([
                .object([
                    "id": .string("root"),
                    "name": .string("UIWindow"),
                    "children": .array([]),
                    "visible": .bool(false),
                    "alpha": .number(0)
                ])
            ]),
            "debug": .null
        ])

        let snapshot = InspectorSnapshot(
            snapshotId: "ios-inspector-1",
            capturedAt: "2026-03-27T10:30:00Z",
            platform: "ios",
            available: true,
            payload: payload
        )

        let request = try NeptuneGatewayIngestClient.makeRawViewTreeRequest(
            platform: "ios",
            appId: "com.neptunekit.demo.ios",
            sessionId: "simulator-session",
            deviceId: "device-1",
            snapshot: snapshot,
            gatewayEndpoint: URL(string: "http://127.0.0.1:18765")!
        )

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString == "http://127.0.0.1:18765/v2/ui-tree/inspector")

        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(
            RawViewTreeRequestBody.self,
            from: body
        )

        #expect(decoded == RawViewTreeRequestBody(
            platform: "ios",
            appId: "com.neptunekit.demo.ios",
            sessionId: "simulator-session",
            deviceId: "device-1",
            snapshotId: "ios-inspector-1",
            capturedAt: "2026-03-27T10:30:00Z",
            payload: .object([
                "roots": .array([
                    .object([
                        "id": .string("root"),
                        "name": .string("UIWindow")
                    ])
                ])
            ])
        ))
    }
}

private struct RawViewTreeRequestBody: Codable, Equatable {
    let platform: String
    let appId: String
    let sessionId: String
    let deviceId: String
    let snapshotId: String
    let capturedAt: String
    let payload: InspectorPayloadValue
}
