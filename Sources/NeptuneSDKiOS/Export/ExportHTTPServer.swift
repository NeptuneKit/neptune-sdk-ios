import FlyingFox
import FlyingSocks
import Foundation

public enum NeptuneExportHTTPServerError: Error, Sendable {
    case alreadyStarted
}

public actor NeptuneExportHTTPServer {
    private let service: NeptuneExportService
    private var server: HTTPServer?
    private var runTask: Task<Void, Error>?

    public init(service: NeptuneExportService = NeptuneExportService()) {
        self.service = service
    }

    public func start(port: UInt16) async throws {
        guard server == nil else {
            throw NeptuneExportHTTPServerError.alreadyStarted
        }

        let server = HTTPServer(port: port)
        await configureRoutes(for: server)

        let runTask = Task {
            try await server.run()
        }

        self.server = server
        self.runTask = runTask

        do {
            try await server.waitUntilListening()
        } catch {
            self.server = nil
            self.runTask = nil
            runTask.cancel()
            _ = try? await runTask.value
            throw error
        }
    }

    public func stop() async {
        let server = self.server
        let runTask = self.runTask

        self.server = nil
        self.runTask = nil

        await server?.stop(timeout: 0)
        runTask?.cancel()
        _ = try? await runTask?.value
    }

    public func listeningPort() async -> UInt16? {
        guard let server else {
            return nil
        }

        switch await server.listeningAddress {
        case let .ip4(_, port), let .ip6(_, port):
            return port
        case .unix, .none:
            return nil
        }
    }

    private func configureRoutes(for server: HTTPServer) async {
        let service = self.service

        await server.appendRoute("GET /v2/export/health") { _ in
            try Self.jsonResponse(await service.health())
        }

        await server.appendRoute("GET /v2/export/metrics") { _ in
            try Self.jsonResponse(await service.metrics())
        }

        await server.appendRoute("GET /v2/export/logs") { request in
            let query = Self.parseLogsQuery(
                cursorValue: request.query["cursor"],
                limitValue: request.query["limit"]
            )
            let page = await service.logs(cursor: query.cursor, limit: query.limit)
            return try Self.jsonResponse(page)
        }
    }

    static func parseLogsQuery(cursorValue: String?, limitValue: String?) -> (cursor: Int64?, limit: Int) {
        let cursor = cursorValue.flatMap(Int64.init)
        let limit = limitValue.flatMap(Int.init) ?? 100
        return (cursor: cursor, limit: max(0, limit))
    }

    private static func jsonResponse<T: Encodable>(_ value: T) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        let body = try encoder.encode(value)
        return HTTPResponse(
            statusCode: .ok,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: body
        )
    }
}
