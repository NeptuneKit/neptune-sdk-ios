import Foundation
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Client Message Bus")
struct ClientMessageBusTests {
    @Test("BusEnvelope log payload encoding and decoding stay lossless")
    func busEnvelopeLogRoundTripIsLossless() throws {
        let record = NeptuneIngestLogRecord(
            timestamp: "2026-03-25T09:00:00Z",
            level: .notice,
            message: "bus-roundtrip",
            platform: "ios",
            appId: "com.neptune.demo",
            sessionId: "session-1",
            deviceId: "device-1",
            category: "bus",
            attributes: ["step": "roundtrip"],
            source: NeptuneLogSource(
                sdkName: "neptune-sdk-ios",
                sdkVersion: "2.0.0-alpha.1",
                file: "ClientMessageBusTests.swift",
                function: "busEnvelopeLogRoundTripIsLossless()",
                line: 18
            )
        )
        let bus = ClientMessageBus()
        let envelope = bus.makeLogEnvelope(record, requestId: "req-log-1")

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(BusEnvelope.self, from: data)

        #expect(decoded == envelope)
        #expect(decoded.direction == .clientToCLI)
        #expect(decoded.kind == .log)
        #expect(decoded.requestId == "req-log-1")
        #expect(decoded.logRecord == record)
    }
}
