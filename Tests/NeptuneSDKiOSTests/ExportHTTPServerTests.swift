import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Export HTTP Server")
struct ExportHTTPServerTests {
    @Test("Server defaults to 0.0.0.0 bind host")
    func serverDefaultsToAllInterfaces() {
        #expect(NeptuneExportHTTPServerConfiguration().hostname == "0.0.0.0")
    }

    @Test("Health endpoint is reachable after server start")
    func healthEndpointIsReachable() async throws {
        let service = NeptuneExportService()
        let server = NeptuneExportHTTPServer(service: service)

        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let url = URL(string: "http://127.0.0.1:\(port)/v2/export/health")!
            let (data, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let snapshot = try JSONDecoder().decode(NeptuneHealthSnapshot.self, from: data)
            #expect(snapshot.ok)
            #expect(snapshot.version == NeptuneExportService.version)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("Client command ping returns a bus ACK on v2")
    func v2ClientCommandPingReturnsAck() async throws {
        let server = NeptuneExportHTTPServer(service: NeptuneExportService())
        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let request = Self.makeV2CommandRequest(
                url: URL(string: "http://127.0.0.1:\(port)/v2/client/command")!,
                requestId: "req-1",
                command: "ping"
            )
            let (data, response) = try await URLSession.shared.upload(for: request, from: request.httpBody ?? Data())

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let ack = try JSONDecoder().decode(BusAck.self, from: data)
            #expect(ack.requestId == "req-1")
            #expect(ack.command == "ping")
            #expect(ack.status == .ok)
            #expect(ack.message == nil)
            #expect(!ack.timestamp.isEmpty)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("Client command ping remains supported on v1")
    func v1ClientCommandPingReturnsAck() async throws {
        let server = NeptuneExportHTTPServer(service: NeptuneExportService())
        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let request = Self.makeV1CommandRequest(
                url: URL(string: "http://127.0.0.1:\(port)/v1/client/command")!,
                requestId: "req-legacy",
                command: "ping"
            )
            let (data, response) = try await URLSession.shared.upload(for: request, from: request.httpBody ?? Data())

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let ack = try JSONDecoder().decode(NeptuneClientCommandAck.self, from: data)
            #expect(ack.requestId == "req-legacy")
            #expect(ack.command == "ping")
            #expect(ack.status == .ok)
            #expect(ack.message == nil)
            #expect(!ack.timestamp.isEmpty)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("Logs endpoint converts cursor and length query parameters")
    func logsEndpointUsesPagingQuery() async throws {
        let service = NeptuneExportService()
        let server = NeptuneExportHTTPServer(service: service)

        for index in 0..<5 {
            _ = await service.ingest(Self.makeRecord(index: index))
        }

        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let url = URL(string: "http://127.0.0.1:\(port)/v2/logs?cursor=2&length=2")!
            let (data, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let page = try JSONDecoder().decode(ExportLogsResponse.self, from: data)
            #expect(page.records.map(\.id) == [3, 4])
            #expect(page.hasMore)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("Metrics endpoint returns queue snapshot")
    func metricsEndpointReturnsSnapshot() async throws {
        let service = NeptuneExportService()
        let server = NeptuneExportHTTPServer(service: service)

        for index in 0..<3 {
            _ = await service.ingest(Self.makeRecord(index: index))
        }

        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let url = URL(string: "http://127.0.0.1:\(port)/v2/export/metrics")!
            let (data, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let snapshot = try JSONDecoder().decode(NeptuneMetricsSnapshot.self, from: data)
            #expect(snapshot.totalRecords == 3)
            #expect(snapshot.droppedOverflow == 0)
            #expect(snapshot.oldestRecordId == 1)
            #expect(snapshot.newestRecordId == 3)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("View tree snapshot endpoint is no longer exposed")
    func viewTreeSnapshotEndpointReturns404() async throws {
        let server = NeptuneExportHTTPServer(
            service: NeptuneExportService(),
            viewTreeCollector: StubViewTreeCollector(
                snapshot: Self.makeCollectedSnapshot(),
                inspectorSnapshot: Self.makeCollectedInspectorSnapshot()
            )
        )
        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let url = URL(string: "http://127.0.0.1:\(port)/v2/ui-tree/snapshot?platform=ios&appId=demo.app&sessionId=s-1&deviceId=d-1")!
            let (_, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("Inspector endpoint returns raw object payload")
    func inspectorEndpointReturnsRawObjectPayload() async throws {
        let server = NeptuneExportHTTPServer(
            service: NeptuneExportService(),
            viewTreeCollector: StubViewTreeCollector(
                snapshot: Self.makeCollectedSnapshot(),
                inspectorSnapshot: Self.makeCollectedInspectorSnapshot()
            )
        )
        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let url = URL(string: "http://127.0.0.1:\(port)/v2/ui-tree/inspector?deviceId=d-1")!
            let (data, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let snapshot = try JSONDecoder().decode(InspectorSnapshot.self, from: data)
            #expect(snapshot.available)

            switch try #require(snapshot.payload) {
            case .object(let payload):
                #expect(payload["kind"] == .string("tree"))
                switch try #require(payload["roots"]) {
                case .array(let roots):
                    #expect(roots.count == 1)
                    switch try #require(roots.first) {
                    case .object(let root):
                        switch try #require(root["style"]) {
                        case .object(let style):
                            #expect(style["typographyUnit"] == .string("dp"))
                            #expect(style["sourceTypographyUnit"] == .string("pt"))
                            #expect(style["platformFontScale"] == .number(1.25))
                            #expect(style["fontSize"] == .number(17))
                            #expect(style["lineHeight"] == .number(20))
                            #expect(style["letterSpacing"] == .number(0.25))
                            #expect(style["fontWeightRaw"] == .string("0.4"))
                        default:
                            Issue.record("Expected inspector root style to be an object")
                        }
                    default:
                        Issue.record("Expected inspector root payload to be an object")
                    }
                default:
                    Issue.record("Expected inspector payload roots to be an array")
                }
            default:
                Issue.record("Expected inspector payload to be a JSON object")
            }
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("Logs endpoint preserves invalid query fallback semantics")
    func logsEndpointPreservesInvalidQueryFallback() async throws {
        let service = NeptuneExportService()
        let server = NeptuneExportHTTPServer(service: service)

        for index in 0..<2 {
            _ = await service.ingest(Self.makeRecord(index: index))
        }

        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let url = URL(string: "http://127.0.0.1:\(port)/v2/logs?cursor=abc&length=-1")!
            let (data, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let page = try JSONDecoder().decode(ExportLogsResponse.self, from: data)
            #expect(page.records.map(\.id) == [1, 2])
            #expect(!page.hasMore)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    private static func makeRecord(index: Int) -> NeptuneIngestLogRecord {
        NeptuneIngestLogRecord(
            timestamp: "2026-03-23T12:34:56Z",
            level: .info,
            message: "message-\(index)",
            platform: "ios",
            appId: "app-1",
            sessionId: "session-1",
            deviceId: "device-1",
            category: "default",
            attributes: ["index": "\(index)"],
            source: NeptuneLogSource(
                sdkName: "sdk",
                sdkVersion: "1.0.0",
                file: "File.swift",
                function: "fn()",
                line: index
            )
        )
    }

    private static func makeV2CommandRequest(url: URL, requestId: String?, command: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONEncoder().encode(
            BusEnvelope(
                requestId: requestId,
                direction: .cliToClient,
                kind: .command,
                command: command
            )
        )
        return request
    }

    private static func makeV1CommandRequest(url: URL, requestId: String?, command: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONEncoder().encode(NeptuneClientCommandRequest(requestId: requestId, command: command))
        return request
    }

    private static func makeCollectedSnapshot() -> NeptuneViewTreeSnapshot {
        let child = NeptuneViewTreeNode(
            id: "label-1",
            parentId: "window-1",
            name: "UILabel",
            frame: .init(x: 12, y: 36, width: 120, height: 20),
            style: .init(
                typographyUnit: "dp",
                sourceTypographyUnit: "pt",
                platformFontScale: 1.25,
                opacity: 1,
                backgroundColor: nil,
                textColor: "#111111",
                fontSize: 17,
                lineHeight: 20,
                letterSpacing: 0.25,
                fontWeight: "semibold",
                fontWeightRaw: "0.4",
                borderRadius: 0,
                borderWidth: 0,
                borderColor: nil,
                zIndex: 0,
                textAlign: "center"
            ),
            text: "Demo Child",
            visible: true,
            children: []
        )
        let root = NeptuneViewTreeNode(
            id: "window-1",
            parentId: nil,
            name: "UIWindow",
            frame: .init(x: 0, y: 0, width: 390, height: 844),
            style: .init(
                typographyUnit: nil,
                sourceTypographyUnit: nil,
                platformFontScale: nil,
                opacity: 1,
                backgroundColor: "#FFFFFF",
                textColor: nil,
                fontSize: nil,
                lineHeight: nil,
                letterSpacing: nil,
                fontWeight: nil,
                fontWeightRaw: nil,
                borderRadius: 0,
                borderWidth: 0,
                borderColor: "#000000",
                zIndex: 0,
                textAlign: nil
            ),
            text: "Demo Root",
            visible: true,
            children: [child]
        )
        return NeptuneViewTreeSnapshot(
            snapshotId: "snapshot-1",
            capturedAt: "2026-03-27T00:00:00Z",
            platform: "ios",
            roots: [root]
        )
    }

    private static func makeCollectedInspectorSnapshot() -> InspectorSnapshot {
        InspectorSnapshot(
            snapshotId: "inspector-1",
            capturedAt: "2026-03-27T00:00:00Z",
            platform: "ios",
            available: true,
            payload: .object([
                "kind": .string("tree"),
                "roots": .array([
                    .object([
                        "id": .string("window-1"),
                        "name": .string("UIWindow"),
                        "style": .object([
                            "typographyUnit": .string("dp"),
                            "sourceTypographyUnit": .string("pt"),
                            "platformFontScale": .number(1.25),
                            "fontSize": .number(17),
                            "lineHeight": .number(20),
                            "letterSpacing": .number(0.25),
                            "fontWeightRaw": .string("0.4")
                        ]),
                        "children": .array([
                            .object([
                                "id": .string("label-1"),
                                "name": .string("UILabel"),
                                "style": .object([
                                    "typographyUnit": .string("dp"),
                                    "sourceTypographyUnit": .string("pt"),
                                    "platformFontScale": .number(1.25),
                                    "fontSize": .number(17),
                                    "lineHeight": .number(20),
                                    "letterSpacing": .number(0.25),
                                    "fontWeightRaw": .string("0.4")
                                ])
                            ])
                        ])
                    ])
                ])
            ]),
            reason: nil
        )
    }
}

private struct StubViewTreeCollector: NeptuneViewTreeCollecting {
    let snapshot: NeptuneViewTreeSnapshot
    let inspectorSnapshot: InspectorSnapshot

    func captureViewTreeSnapshot(platform: String) async -> NeptuneViewTreeSnapshot {
        var snapshot = snapshot
        snapshot.platform = platform
        return snapshot
    }

    func captureInspectorSnapshot(platform: String) async -> InspectorSnapshot {
        var snapshot = inspectorSnapshot
        snapshot.platform = platform
        return snapshot
    }
}

private struct ExportLogsResponse: Codable {
    let records: [NeptuneLogRecord]
    let hasMore: Bool
}
