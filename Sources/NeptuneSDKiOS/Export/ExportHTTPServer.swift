import Foundation
import Vapor

public enum NeptuneExportHTTPServerError: Error, Sendable {
    case alreadyStarted
}

public actor NeptuneExportHTTPServer {
    private let service: NeptuneExportService
    private var application: Application?

    public init(service: NeptuneExportService = NeptuneExportService()) {
        self.service = service
    }

    public func start(port: UInt16) async throws {
        guard application == nil else {
            throw NeptuneExportHTTPServerError.alreadyStarted
        }

        let environment = Environment(name: "production", arguments: ["NeptuneExportHTTPServer"])
        let application = try await Application.make(environment)
        application.http.server.configuration.hostname = "127.0.0.1"
        application.http.server.configuration.port = Int(port)
        configureRoutes(on: application)

        do {
            try await application.startup()
            self.application = application
        } catch {
            try? await application.asyncShutdown()
            throw error
        }
    }

    public func stop() async {
        let application = self.application
        self.application = nil
        try? await application?.asyncShutdown()
    }

    public func listeningPort() async -> UInt16? {
        application?.http.server.shared.localAddress?.port.flatMap(UInt16.init(exactly:))
    }

    private func configureRoutes(on application: Application) {
        let service = self.service

        application.get("v2", "export", "health") { _ async throws in
            try Self.jsonResponse(await service.health())
        }

        application.get("v2", "export", "metrics") { _ async throws in
            try Self.jsonResponse(await service.metrics())
        }

        application.get("v2", "export", "logs") { request async throws in
            let parameters = Self.logsQueryParameters(from: request)
            let query = Self.parseLogsQuery(
                cursorValue: parameters.cursor,
                limitValue: parameters.limit
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

    private static func logsQueryParameters(from request: Request) -> (cursor: String?, limit: String?) {
        guard let components = URLComponents(string: "http://127.0.0.1\(request.url.string)") else {
            return (cursor: nil, limit: nil)
        }

        let items = components.queryItems ?? []
        return (
            cursor: items.first(where: { $0.name == "cursor" })?.value,
            limit: items.first(where: { $0.name == "limit" })?.value
        )
    }

    private static func jsonResponse<T: Encodable>(_ value: T) throws -> Response {
        let encoder = JSONEncoder()
        let body = try encoder.encode(value)
        var headers = HTTPHeaders()
        headers.contentType = .json
        return Response(
            status: .ok,
            headers: headers,
            body: .init(data: body)
        )
    }
}
