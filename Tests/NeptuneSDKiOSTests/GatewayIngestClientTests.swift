import Foundation
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Gateway Ingest")
struct GatewayIngestClientTests {
    @Test("Gateway ingest request uses JSON body and the expected endpoint")
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
        let decoded = try JSONDecoder().decode(NeptuneIngestLogRecord.self, from: body)

        #expect(decoded == record)
    }
}
