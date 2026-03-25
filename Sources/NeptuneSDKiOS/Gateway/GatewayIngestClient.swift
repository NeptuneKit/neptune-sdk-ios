import Foundation

public enum NeptuneGatewayIngestClient {
    public static func send(_ record: NeptuneIngestLogRecord, to gatewayEndpoint: URL) async throws {
        let request = try makeRequest(record: record, gatewayEndpoint: gatewayEndpoint)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw NeptuneGatewayIngestError.invalidHTTPResponse
        }
    }

    static func makeRequest(record: NeptuneIngestLogRecord, gatewayEndpoint: URL) throws -> URLRequest {
        let envelope = ClientMessageBus().makeLogEnvelope(record)
        let requestURL = gatewayEndpoint
            .appendingPathComponent("v2")
            .appendingPathComponent("logs:ingest")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try makeEncoder().encode(envelope)
        return request
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public enum NeptuneGatewayIngestError: Error, Sendable, Equatable, LocalizedError {
    case invalidHTTPResponse

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "gateway returned a non-2xx response"
        }
    }
}
