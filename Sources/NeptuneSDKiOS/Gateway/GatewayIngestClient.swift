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

    public static func sendRawViewTree(
        platform: String,
        appId: String,
        sessionId: String,
        deviceId: String,
        snapshot: InspectorSnapshot,
        to gatewayEndpoint: URL
    ) async throws {
        let request = try makeRawViewTreeRequest(
            platform: platform,
            appId: appId,
            sessionId: sessionId,
            deviceId: deviceId,
            snapshot: snapshot,
            gatewayEndpoint: gatewayEndpoint
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw NeptuneGatewayIngestError.invalidHTTPResponse
        }
    }

    static func makeRawViewTreeRequest(
        platform: String,
        appId: String,
        sessionId: String,
        deviceId: String,
        snapshot: InspectorSnapshot,
        gatewayEndpoint: URL
    ) throws -> URLRequest {
        let requestURL = gatewayEndpoint
            .appendingPathComponent("v2")
            .appendingPathComponent("ui-tree")
            .appendingPathComponent("inspector")

        let payload = RawViewTreeIngestPayload(
            platform: platform,
            appId: appId,
            sessionId: sessionId,
            deviceId: deviceId,
            snapshotId: snapshot.snapshotId,
            capturedAt: snapshot.capturedAt,
            payload: snapshot.payload?.prunedForGatewayIngest() ?? .object([:])
        )

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try makeEncoder().encode(payload)
        return request
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private struct RawViewTreeIngestPayload: Codable {
    let platform: String
    let appId: String
    let sessionId: String
    let deviceId: String
    let snapshotId: String
    let capturedAt: String
    let payload: InspectorPayloadValue
}

private extension InspectorPayloadValue {
    func prunedForGatewayIngest(isRoot: Bool = true) -> InspectorPayloadValue? {
        switch self {
        case .null:
            return isRoot ? .object([:]) : nil
        case .bool(let value):
            return value ? .bool(value) : nil
        case .number(let value):
            return value == 0 ? nil : .number(value)
        case .string:
            return self
        case .array(let values):
            let pruned = values.compactMap { $0.prunedForGatewayIngest(isRoot: false) }
            if pruned.isEmpty {
                return isRoot ? .array([]) : nil
            }
            return .array(pruned)
        case .object(let values):
            let pruned = values.reduce(into: [String: InspectorPayloadValue]()) { partialResult, item in
                if let value = item.value.prunedForGatewayIngest(isRoot: false) {
                    partialResult[item.key] = value
                }
            }
            if pruned.isEmpty {
                return isRoot ? .object([:]) : nil
            }
            return .object(pruned)
        }
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
