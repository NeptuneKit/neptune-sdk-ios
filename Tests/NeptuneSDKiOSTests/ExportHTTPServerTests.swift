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

    @Test("Client command ping returns a standard ACK on v2")
    func v2ClientCommandPingReturnsAck() async throws {
        let server = NeptuneExportHTTPServer(service: NeptuneExportService())
        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let request = Self.makeCommandRequest(
                url: URL(string: "http://127.0.0.1:\(port)/v2/client/command")!,
                requestId: "req-1",
                command: "ping"
            )
            let (data, response) = try await URLSession.shared.upload(for: request, from: request.httpBody ?? Data())

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let ack = try JSONDecoder().decode(NeptuneClientCommandAck.self, from: data)
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
            let request = Self.makeCommandRequest(
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

    @Test("Logs endpoint converts cursor and limit query parameters")
    func logsEndpointUsesPagingQuery() async throws {
        let service = NeptuneExportService()
        let server = NeptuneExportHTTPServer(service: service)

        for index in 0..<5 {
            _ = await service.ingest(Self.makeRecord(index: index))
        }

        try await server.start(port: 0)
        let port = try #require(await server.listeningPort())

        do {
            let url = URL(string: "http://127.0.0.1:\(port)/v2/export/logs?cursor=2&limit=2")!
            let (data, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let page = try JSONDecoder().decode(NeptuneLogsPage.self, from: data)
            #expect(page.records.map(\.id) == [3, 4])
            #expect(page.nextCursor == 4)
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
            let url = URL(string: "http://127.0.0.1:\(port)/v2/export/logs?cursor=abc&limit=-1")!
            let (data, response) = try await URLSession.shared.data(from: url)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let page = try JSONDecoder().decode(NeptuneLogsPage.self, from: data)
            #expect(page.records.isEmpty)
            #expect(page.nextCursor == nil)
            #expect(page.hasMore)
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

    private static func makeCommandRequest(url: URL, requestId: String?, command: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONEncoder().encode(NeptuneClientCommandRequest(requestId: requestId, command: command))
        return request
    }
}
