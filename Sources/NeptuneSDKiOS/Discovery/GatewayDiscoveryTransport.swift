import Foundation

public protocol NeptuneGatewayDiscoveryTransport: Sendable {
    func fetchDiscoveryPayload(from url: URL, timeout: TimeInterval) async throws -> Data
}

public struct NeptuneURLSessionGatewayDiscoveryTransport: NeptuneGatewayDiscoveryTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchDiscoveryPayload(from url: URL, timeout: TimeInterval) async throws -> Data {
        let requestURL = Self.discoveryURL(for: url)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NeptuneGatewayDiscoveryTransportError.invalidHTTPResponse
        }

        return data
    }

    private static func discoveryURL(for baseURL: URL) -> URL {
        baseURL
            .appendingPathComponent("v2")
            .appendingPathComponent("gateway")
            .appendingPathComponent("discovery")
    }
}

public enum NeptuneGatewayDiscoveryTransportError: Error, Sendable, Equatable {
    case invalidHTTPResponse
}

