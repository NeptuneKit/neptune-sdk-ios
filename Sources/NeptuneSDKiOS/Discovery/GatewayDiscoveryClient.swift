import Foundation

public struct NeptuneGatewayDiscoveryClient: Sendable {
    private let configuration: NeptuneGatewayDiscoveryConfiguration
    private let browser: any NeptuneGatewayDiscoveryBrowsing
    private let transport: any NeptuneGatewayDiscoveryTransport

    public init(
        configuration: NeptuneGatewayDiscoveryConfiguration = .init(),
        browser: (any NeptuneGatewayDiscoveryBrowsing)? = nil,
        transport: any NeptuneGatewayDiscoveryTransport = NeptuneURLSessionGatewayDiscoveryTransport()
    ) {
        self.configuration = configuration
        self.browser = browser ?? NeptuneBonjourGatewayDiscoveryBrowser(
            serviceType: configuration.mdnsServiceType,
            domain: configuration.mdnsDomain,
            timeout: configuration.timeout,
            maxCandidates: configuration.maxCandidates
        )
        self.transport = transport
    }

    public func discover() async throws -> NeptuneGatewayDiscoveryResult {
        let candidates = await makeCandidates()
        guard !candidates.isEmpty else {
            throw NeptuneGatewayDiscoveryError.noAvailableCandidates
        }

        for candidate in candidates {
            do {
                let data = try await transport.fetchDiscoveryPayload(
                    from: candidate.url,
                    timeout: configuration.timeout
                )
                let decoder = JSONDecoder()
                let payload = try decoder.decode(NeptuneGatewayDiscoveryPayload.self, from: data)
                guard let endpoint = Self.makeEndpointURL(from: candidate.url, host: payload.host, port: payload.port) else {
                    continue
                }

                return NeptuneGatewayDiscoveryResult(
                    endpoint: endpoint,
                    source: candidate.source,
                    host: payload.host,
                    port: payload.port,
                    version: payload.version
                )
            } catch {
                continue
            }
        }

        throw NeptuneGatewayDiscoveryError.noValidGatewayDiscovered
    }

    private func makeCandidates() async -> [NeptuneGatewayDiscoveryCandidate] {
        var resolvedCandidates: [NeptuneGatewayDiscoveryCandidate] = []
        var seen = Set<String>()

        let discoveredCandidates = await browser.candidates()
        for candidate in discoveredCandidates {
            if resolvedCandidates.count >= configuration.maxCandidates {
                break
            }
            append(candidate, into: &resolvedCandidates, seen: &seen)
        }

        if let manualDSN = configuration.manualDSN {
            append(.init(url: manualDSN, source: .manualDSN), into: &resolvedCandidates, seen: &seen)
        }

        return resolvedCandidates
    }

    private func append(
        _ candidate: NeptuneGatewayDiscoveryCandidate,
        into candidates: inout [NeptuneGatewayDiscoveryCandidate],
        seen: inout Set<String>
    ) {
        guard let normalized = Self.normalizeBaseURL(candidate.url) else {
            return
        }

        let key = normalized.absoluteString
        guard !seen.contains(key) else {
            return
        }

        seen.insert(key)
        candidates.append(.init(url: normalized, source: candidate.source))
    }

    private static func normalizeBaseURL(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty,
              let host = components.host, !host.isEmpty else {
            return nil
        }

        var normalized = URLComponents()
        normalized.scheme = scheme
        normalized.host = host
        normalized.port = components.port
        normalized.path = ""
        return normalized.url
    }

    private static func makeEndpointURL(from candidateURL: URL, host: String, port: Int) -> URL? {
        guard port > 0 else {
            return nil
        }

        guard let components = URLComponents(url: candidateURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), !scheme.isEmpty,
              let candidateHost = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidateHost.isEmpty else {
            return nil
        }

        let endpointHost = Self.shouldUseCandidateHost(for: host) ? candidateHost : host
        guard !endpointHost.isEmpty else {
            return nil
        }

        var endpoint = URLComponents()
        endpoint.scheme = scheme
        endpoint.host = endpointHost
        endpoint.port = port
        endpoint.path = ""
        return endpoint.url
    }

    private static func shouldUseCandidateHost(for payloadHost: String) -> Bool {
        switch payloadHost.lowercased() {
        case "127.0.0.1", "localhost", "::1", "::", "0.0.0.0":
            return true
        default:
            return false
        }
    }
}
