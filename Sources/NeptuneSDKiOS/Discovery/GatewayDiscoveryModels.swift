import Foundation

public struct NeptuneGatewayDiscoveryConfiguration: Sendable, Equatable {
    public var manualDSN: URL?
    public var mdnsServiceType: String
    public var mdnsDomain: String
    public var timeout: TimeInterval
    public var maxCandidates: Int

    public init(
        manualDSN: URL? = nil,
        mdnsServiceType: String = "_neptune._tcp.",
        mdnsDomain: String = "local.",
        timeout: TimeInterval = 3.0,
        maxCandidates: Int = 8
    ) {
        self.manualDSN = manualDSN
        self.mdnsServiceType = mdnsServiceType
        self.mdnsDomain = mdnsDomain
        self.timeout = timeout
        self.maxCandidates = max(1, maxCandidates)
    }
}

public enum NeptuneGatewayDiscoverySource: String, Codable, Sendable, Equatable {
    case mdns
    case manualDSN
}

public struct NeptuneGatewayDiscoveryCandidate: Sendable, Equatable {
    public var url: URL
    public var source: NeptuneGatewayDiscoverySource

    public init(url: URL, source: NeptuneGatewayDiscoverySource) {
        self.url = url
        self.source = source
    }
}

public struct NeptuneGatewayDiscoveryResult: Sendable, Equatable {
    public var endpoint: URL
    public var source: NeptuneGatewayDiscoverySource
    public var host: String
    public var port: Int
    public var version: String

    public init(
        endpoint: URL,
        source: NeptuneGatewayDiscoverySource,
        host: String,
        port: Int,
        version: String
    ) {
        self.endpoint = endpoint
        self.source = source
        self.host = host
        self.port = port
        self.version = version
    }
}

public enum NeptuneGatewayDiscoveryError: Error, Sendable, Equatable, LocalizedError {
    case noAvailableCandidates
    case noValidGatewayDiscovered

    public var errorDescription: String? {
        switch self {
        case .noAvailableCandidates:
            return "No gateway candidates were discovered."
        case .noValidGatewayDiscovered:
            return "No discovered gateway returned a valid /v2/gateway/discovery payload."
        }
    }
}

struct NeptuneGatewayDiscoveryPayload: Codable, Sendable, Equatable {
    var host: String
    var port: Int
    var version: String
}

