import Foundation
import Vapor

public enum NeptuneExportHTTPServerError: Error, Sendable {
    case alreadyStarted
}

public actor NeptuneExportHTTPServer {
    private let service: NeptuneExportService
    private let configuration: NeptuneExportHTTPServerConfiguration
    private let messageBus: ClientMessageBus
    private let viewTreeCollector: any NeptuneViewTreeCollecting
    private var application: Application?

    public init(
        service: NeptuneExportService = NeptuneExportService(),
        configuration: NeptuneExportHTTPServerConfiguration = .init(),
        messageBus: ClientMessageBus = ClientMessageBus(),
        viewTreeCollector: (any NeptuneViewTreeCollecting)? = nil
    ) {
        self.service = service
        self.configuration = configuration
        self.messageBus = messageBus
        self.viewTreeCollector = viewTreeCollector ?? Self.makeDefaultViewTreeCollector()
    }

    public func start(port: UInt16) async throws {
        guard application == nil else {
            throw NeptuneExportHTTPServerError.alreadyStarted
        }

        let environment = Environment(name: "production", arguments: ["NeptuneExportHTTPServer"])
        let application = try await Application.make(environment)
        application.http.server.configuration.hostname = configuration.hostname
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
        let messageBus = self.messageBus
        let viewTreeCollector = self.viewTreeCollector

        application.get("v2", "export", "health") { _ async throws in
            try Self.jsonResponse(await service.health())
        }

        application.get("v2", "export", "metrics") { _ async throws in
            try Self.jsonResponse(await service.metrics())
        }

        application.get("v2", "logs") { request async throws in
            let parameters = Self.logsQueryParameters(from: request)
            let query = Self.parseLogsQuery(
                cursorValue: parameters.cursor,
                lengthValue: parameters.length,
                limitValue: parameters.limit
            )
            let page = await service.logs(cursor: query.cursor, limit: query.length ?? .max)
            return try Self.jsonResponse(NeptuneExportLogsResponse(page: page))
        }

        application.get("v2", "ui-tree", "inspector") { request async throws in
            let query = Self.viewTreeQueryParameters(from: request)
            return try Self.jsonResponse(await Self.makeInspectorSnapshot(
                query: query,
                collector: viewTreeCollector
            ))
        }

        application.post("v2", "client", "command") { request async throws in
            let envelope = try request.content.decode(BusEnvelope.self)
            return try Self.jsonResponse(messageBus.acknowledgeInboundCommand(envelope))
        }

        application.post("v1", "client", "command") { request async throws in
            let command = try request.content.decode(NeptuneClientCommandRequest.self)
            return try Self.jsonResponse(Self.handleLegacyClientCommand(command))
        }
    }

    static func parseLogsQuery(cursorValue: String?, lengthValue: String?, limitValue: String?) -> (cursor: Int64?, length: Int?) {
        let cursor = cursorValue.flatMap(Int64.init)
        let normalizedLengthValue = lengthValue ?? limitValue
        let length = normalizedLengthValue.flatMap(Int.init).flatMap { parsed in
            parsed > 0 ? parsed : nil
        }
        return (cursor: cursor, length: length)
    }

    private static func logsQueryParameters(from request: Request) -> (cursor: String?, length: String?, limit: String?) {
        guard let components = URLComponents(string: "http://127.0.0.1\(request.url.string)") else {
            return (cursor: nil, length: nil, limit: nil)
        }

        let items = components.queryItems ?? []
        return (
            cursor: items.first(where: { $0.name == "cursor" })?.value,
            length: items.first(where: { $0.name == "length" })?.value,
            limit: items.first(where: { $0.name == "limit" })?.value
        )
    }

    private static func viewTreeQueryParameters(from request: Request) -> (
        platform: String?,
        appId: String?,
        sessionId: String?,
        deviceId: String?
    ) {
        guard let components = URLComponents(string: "http://127.0.0.1\(request.url.string)") else {
            return (platform: nil, appId: nil, sessionId: nil, deviceId: nil)
        }
        let items = components.queryItems ?? []
        return (
            platform: items.first(where: { $0.name == "platform" })?.value,
            appId: items.first(where: { $0.name == "appId" })?.value,
            sessionId: items.first(where: { $0.name == "sessionId" })?.value,
            deviceId: items.first(where: { $0.name == "deviceId" })?.value
        )
    }

    private static func makeInspectorSnapshot(
        query: (platform: String?, appId: String?, sessionId: String?, deviceId: String?),
        collector: any NeptuneViewTreeCollecting
    ) async -> InspectorSnapshot {
        let platform = normalizePlatform(query.platform, fallback: "ios")
        return await collector.captureInspectorSnapshot(platform: platform)
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

    private static func handleLegacyClientCommand(_ command: NeptuneClientCommandRequest) -> NeptuneClientCommandAck {
        guard command.command == "ping" else {
            return NeptuneClientCommandAck(
                requestId: command.requestId,
                command: command.command,
                status: .error,
                message: "v1 only supports ping",
                timestamp: Self.timestampString()
            )
        }

        return NeptuneClientCommandAck(
            requestId: command.requestId,
            command: command.command,
            status: .ok,
            message: nil,
            timestamp: Self.timestampString()
        )
    }

    private static func makeDefaultViewTreeCollector() -> any NeptuneViewTreeCollecting {
        #if canImport(UIKit)
        return NeptuneUIKitViewTreeCollectorBridge()
        #else
        return NeptuneFallbackViewTreeCollector()
        #endif
    }

    private static func timestampString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func normalizeText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizePlatform(_ value: String?, fallback: String) -> String {
        guard let normalized = normalizeText(value)?.lowercased() else {
            return fallback
        }
        switch normalized {
        case "ios", "android", "harmony", "web":
            return normalized
        default:
            return fallback
        }
    }
}

private struct NeptuneExportLogsResponse: Codable, Sendable, Equatable {
    let records: [NeptuneLogRecord]
    let nextCursor: Int64?
    let hasMore: Bool

    init(page: NeptuneLogsPage) {
        self.records = page.records
        self.nextCursor = page.nextCursor
        self.hasMore = page.hasMore
    }
}
