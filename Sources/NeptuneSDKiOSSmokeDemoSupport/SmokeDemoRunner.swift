import Foundation
import NeptuneSDKiOS

public struct NeptuneSmokeDemoRunner: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var capacity: Int
        public var ingestCount: Int
        public var pageLimit: Int
        public var keepDatabase: Bool

        public init(
            capacity: Int = 4,
            ingestCount: Int = 6,
            pageLimit: Int = 10,
            keepDatabase: Bool = false
        ) {
            self.capacity = capacity
            self.ingestCount = ingestCount
            self.pageLimit = pageLimit
            self.keepDatabase = keepDatabase
        }
    }

    public struct Summary: Sendable, Equatable {
        public var databasePath: String
        public var port: UInt16
        public var ingestedCount: Int
        public var healthStatusCode: Int
        public var health: NeptuneHealthSnapshot
        public var metricsStatusCode: Int
        public var metrics: NeptuneMetricsSnapshot
        public var logsStatusCode: Int
        public var logsPage: NeptuneLogsPage
        public var reopenedMetrics: NeptuneMetricsSnapshot
        public var reopenedLogsPage: NeptuneLogsPage

        public init(
            databasePath: String,
            port: UInt16,
            ingestedCount: Int,
            healthStatusCode: Int,
            health: NeptuneHealthSnapshot,
            metricsStatusCode: Int,
            metrics: NeptuneMetricsSnapshot,
            logsStatusCode: Int,
            logsPage: NeptuneLogsPage,
            reopenedMetrics: NeptuneMetricsSnapshot,
            reopenedLogsPage: NeptuneLogsPage
        ) {
            self.databasePath = databasePath
            self.port = port
            self.ingestedCount = ingestedCount
            self.healthStatusCode = healthStatusCode
            self.health = health
            self.metricsStatusCode = metricsStatusCode
            self.metrics = metrics
            self.logsStatusCode = logsStatusCode
            self.logsPage = logsPage
            self.reopenedMetrics = reopenedMetrics
            self.reopenedLogsPage = reopenedLogsPage
        }
    }

    public enum RunnerError: Error, LocalizedError, Sendable {
        case serverPortUnavailable
        case invalidHTTPResponse
        case healthCheckFailed
        case persistenceValidationFailed
        case logPageValidationFailed

        public var errorDescription: String? {
            switch self {
            case .serverPortUnavailable:
                return "The demo HTTP server did not report a listening port."
            case .invalidHTTPResponse:
                return "The demo HTTP client received a non-HTTP response."
            case .healthCheckFailed:
                return "The demo health endpoint did not return a healthy snapshot."
            case .persistenceValidationFailed:
                return "The reopened SQLite service did not match the HTTP metrics snapshot."
            case .logPageValidationFailed:
                return "The reopened SQLite service did not match the HTTP log page snapshot."
            }
        }
    }

    private struct HTTPJSONResponse<Value: Decodable & Sendable> {
        let statusCode: Int
        let value: Value
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func run() async throws -> Summary {
        let databasePath = Self.makeDatabasePath()

        defer {
            if !configuration.keepDatabase {
                try? FileManager.default.removeItem(atPath: databasePath)
            }
        }

        return try await Self.runSmokeDemo(configuration: configuration, databasePath: databasePath)
    }

    public func render(summary: Summary) -> String {
        let logIDs = summary.logsPage.records.map(\.id).map(String.init).joined(separator: ",")
        let reopenedLogIDs = summary.reopenedLogsPage.records.map(\.id).map(String.init).joined(separator: ",")

        return [
            "Neptune SDK Smoke Demo Summary",
            "databasePath: \(summary.databasePath)",
            "port: \(summary.port)",
            "ingestedCount: \(summary.ingestedCount)",
            "health: status=\(summary.healthStatusCode) ok=\(summary.health.ok) version=\(summary.health.version)",
            "metrics: status=\(summary.metricsStatusCode) totalRecords=\(summary.metrics.totalRecords) droppedOverflow=\(summary.metrics.droppedOverflow) oldestRecordId=\(summary.metrics.oldestRecordId.map(String.init) ?? "nil") newestRecordId=\(summary.metrics.newestRecordId.map(String.init) ?? "nil")",
            "logs: status=\(summary.logsStatusCode) nextCursor=\(summary.logsPage.nextCursor.map(String.init) ?? "nil") hasMore=\(summary.logsPage.hasMore) ids=[\(logIDs)]",
            "reopenedMetrics: totalRecords=\(summary.reopenedMetrics.totalRecords) droppedOverflow=\(summary.reopenedMetrics.droppedOverflow) oldestRecordId=\(summary.reopenedMetrics.oldestRecordId.map(String.init) ?? "nil") newestRecordId=\(summary.reopenedMetrics.newestRecordId.map(String.init) ?? "nil")",
            "reopenedLogs: nextCursor=\(summary.reopenedLogsPage.nextCursor.map(String.init) ?? "nil") hasMore=\(summary.reopenedLogsPage.hasMore) ids=[\(reopenedLogIDs)]",
            "SMOKE_RESULT ok=true port=\(summary.port) ingested=\(summary.ingestedCount) httpTotal=\(summary.metrics.totalRecords) overflow=\(summary.metrics.droppedOverflow) ids=\(logIDs)"
        ]
        .joined(separator: "\n")
    }

    private static func runSmokeDemo(configuration: Configuration, databasePath: String) async throws -> Summary {
        let service = try NeptuneSDKiOS.makeExportService(
            storage: .sqlite(path: databasePath),
            capacity: configuration.capacity
        )
        let records = Self.makeIngestRecords(count: configuration.ingestCount)
        _ = await service.ingest(records)

        let server = NeptuneSDKiOS.makeExportHTTPServer(service: service)

        do {
            try await server.start(port: 0)
            guard let port = await server.listeningPort() else {
                await server.stop()
                throw RunnerError.serverPortUnavailable
            }

            let healthURL = Self.makeURL(port: port, path: "/v2/export/health")
            let metricsURL = Self.makeURL(port: port, path: "/v2/export/metrics")
            let logsURL = Self.makeURL(port: port, path: "/v2/export/logs?cursor=0&limit=\(max(1, configuration.pageLimit))")

            let health = try await Self.fetchJSON(from: healthURL, as: NeptuneHealthSnapshot.self)
            let metrics = try await Self.fetchJSON(from: metricsURL, as: NeptuneMetricsSnapshot.self)
            let logs = try await Self.fetchJSON(from: logsURL, as: NeptuneLogsPage.self)

            await server.stop()

            let reopenedService = try NeptuneSDKiOS.makeExportService(
                storage: .sqlite(path: databasePath),
                capacity: configuration.capacity
            )
            let reopenedMetrics = await reopenedService.metrics()
            let reopenedLogsPage = await reopenedService.logs(cursor: 0, limit: max(1, configuration.pageLimit))

            try Self.validate(health: health, metrics: metrics, logs: logs, reopenedMetrics: reopenedMetrics, reopenedLogsPage: reopenedLogsPage)

            return Summary(
                databasePath: databasePath,
                port: port,
                ingestedCount: records.count,
                healthStatusCode: health.statusCode,
                health: health.value,
                metricsStatusCode: metrics.statusCode,
                metrics: metrics.value,
                logsStatusCode: logs.statusCode,
                logsPage: logs.value,
                reopenedMetrics: reopenedMetrics,
                reopenedLogsPage: reopenedLogsPage
            )
        } catch {
            await server.stop()
            throw error
        }
    }

    private static func validate(
        health: HTTPJSONResponse<NeptuneHealthSnapshot>,
        metrics: HTTPJSONResponse<NeptuneMetricsSnapshot>,
        logs: HTTPJSONResponse<NeptuneLogsPage>,
        reopenedMetrics: NeptuneMetricsSnapshot,
        reopenedLogsPage: NeptuneLogsPage
    ) throws {
        guard health.statusCode == 200, health.value.ok else {
            throw RunnerError.healthCheckFailed
        }
        guard metrics.statusCode == 200, logs.statusCode == 200 else {
            throw RunnerError.invalidHTTPResponse
        }
        guard reopenedMetrics == metrics.value else {
            throw RunnerError.persistenceValidationFailed
        }
        guard reopenedLogsPage == logs.value else {
            throw RunnerError.logPageValidationFailed
        }
    }

    private static func fetchJSON<Value: Decodable & Sendable>(from url: URL, as type: Value.Type) async throws -> HTTPJSONResponse<Value> {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunnerError.invalidHTTPResponse
        }

        let value = try JSONDecoder().decode(Value.self, from: data)
        return HTTPJSONResponse(statusCode: httpResponse.statusCode, value: value)
    }

    private static func makeURL(port: UInt16, path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    private static func makeDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeptuneSDKiOSSmokeDemo", isDirectory: true)
        let fileName = "smoke-\(UUID().uuidString).sqlite"
        return directory.appendingPathComponent(fileName).path
    }

    private static func makeIngestRecords(count: Int) -> [NeptuneIngestLogRecord] {
        let levels: [NeptuneLogLevel] = [.info, .warning, .error, .debug, .notice, .critical]
        return (0..<max(0, count)).map { index in
            NeptuneIngestLogRecord(
                timestamp: "2026-03-24T08:00:\(String(format: "%02d", index % 60))Z",
                level: levels[index % levels.count],
                message: "smoke-log-\(index)",
                platform: "ios",
                appId: "com.neptune.smoke.demo",
                sessionId: "smoke-session",
                deviceId: "smoke-device",
                category: "smoke",
                attributes: [
                    "index": "\(index)",
                    "scenario": "smoke"
                ],
                source: NeptuneLogSource(
                    sdkName: "NeptuneSDKiOS",
                    sdkVersion: NeptuneExportService.version,
                    file: "SmokeDemoRunner.swift",
                    function: "runSmokeDemo()",
                    line: index
                )
            )
        }
    }
}
