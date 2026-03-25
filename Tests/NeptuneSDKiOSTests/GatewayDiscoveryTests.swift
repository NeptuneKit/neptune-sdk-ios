import Foundation
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS Gateway Discovery")
struct GatewayDiscoveryTests {
    @Test("mDNS succeeds before manual DSN fallback")
    func mdnsWinsOverManualDSN() async throws {
        let mdnsURL = URL(string: "http://mdns-gateway.local:18765")!
        let manualURL = URL(string: "http://manual-gateway.local:18765")!
        let discovery = NeptuneGatewayDiscoveryClient(
            configuration: .init(manualDSN: manualURL),
            browser: MockDiscoveryBrowser(candidates: [
                .init(url: mdnsURL, source: .mdns)
            ]),
            transport: MockDiscoveryTransport(responses: [
                mdnsURL: .success(Self.discoveryPayload(host: "127.0.0.1", port: 18765, version: "2.0.0-alpha.1")),
                manualURL: .success(Self.discoveryPayload(host: "127.0.0.1", port: 18765, version: "2.0.0-alpha.1"))
            ])
        )

        let result = try await discovery.discover()

        #expect(result.source == .mdns)
        #expect(result.endpoint.absoluteString == "http://mdns-gateway.local:18765")
    }

    @Test("mDNS failures fall back to manual DSN")
    func mdnsFallsBackToManualDSN() async throws {
        let mdnsURL = URL(string: "http://mdns-gateway.local:18765")!
        let manualURL = URL(string: "http://manual-gateway.local:18765")!
        let discovery = NeptuneGatewayDiscoveryClient(
            configuration: .init(manualDSN: manualURL),
            browser: MockDiscoveryBrowser(candidates: [
                .init(url: mdnsURL, source: .mdns)
            ]),
            transport: MockDiscoveryTransport(responses: [
                mdnsURL: .failure(MockDiscoveryTransport.MockTransportError.unavailable),
                manualURL: .success(Self.discoveryPayload(host: "gateway.local", port: 18766, version: "2.0.0-alpha.1"))
            ])
        )

        let result = try await discovery.discover()

        #expect(result.source == NeptuneGatewayDiscoverySource.manualDSN)
        #expect(result.endpoint.absoluteString == "http://gateway.local:18766")
    }

    @Test("Loopback discovery host falls back to the candidate host")
    func loopbackPayloadHostFallsBackToCandidateHost() async throws {
        let manualURL = URL(string: "http://10.0.2.2:18765")!
        let discovery = NeptuneGatewayDiscoveryClient(
            configuration: .init(manualDSN: manualURL),
            browser: MockDiscoveryBrowser(candidates: []),
            transport: MockDiscoveryTransport(responses: [
                manualURL: .success(Self.discoveryPayload(host: "127.0.0.1", port: 18765, version: "2.0.0-alpha.1"))
            ])
        )

        let result = try await discovery.discover()

        #expect(result.source == .manualDSN)
        #expect(result.endpoint.absoluteString == "http://10.0.2.2:18765")
        #expect(result.host == "127.0.0.1")
        #expect(result.port == 18765)
    }

    @Test("Invalid discovery payloads continue to next candidate")
    func invalidPayloadContinuesToNextCandidate() async throws {
        let firstURL = URL(string: "http://first-gateway.local:18765")!
        let secondURL = URL(string: "http://second-gateway.local:18765")!
        let discovery = NeptuneGatewayDiscoveryClient(
            configuration: .init(),
            browser: MockDiscoveryBrowser(candidates: [
                .init(url: firstURL, source: .mdns),
                .init(url: secondURL, source: .mdns)
            ]),
            transport: MockDiscoveryTransport(responses: [
                firstURL: .success(Data("not-json".utf8)),
                secondURL: .success(Self.discoveryPayload(host: "second-gateway.local", port: 18767, version: "2.0.0-alpha.2"))
            ])
        )

        let result = try await discovery.discover()

        #expect(result.endpoint.absoluteString == "http://second-gateway.local:18767")
        #expect(result.version == "2.0.0-alpha.2")
    }

    @Test("No candidates produces a clear error")
    func noCandidatesProducesClearError() async throws {
        let discovery = NeptuneGatewayDiscoveryClient(
            configuration: .init(),
            browser: MockDiscoveryBrowser(candidates: []),
            transport: MockDiscoveryTransport(responses: [:])
        )

        do {
            _ = try await discovery.discover()
            #expect(Bool(false))
        } catch let error as NeptuneGatewayDiscoveryError {
            #expect(error == .noAvailableCandidates)
        } catch {
            #expect(Bool(false))
        }
    }

    private static func discoveryPayload(host: String, port: Int, version: String) -> Data {
        let payload: [String: Any] = [
            "host": host,
            "port": port,
            "version": version
        ]
        return try! JSONSerialization.data(withJSONObject: payload, options: [])
    }
}

private struct MockDiscoveryBrowser: NeptuneGatewayDiscoveryBrowsing {
    let candidates: [NeptuneGatewayDiscoveryCandidate]

    func candidates() async -> [NeptuneGatewayDiscoveryCandidate] {
        candidates
    }
}

private struct MockDiscoveryTransport: NeptuneGatewayDiscoveryTransport {
    enum MockTransportError: Error, Sendable {
        case unavailable
    }

    enum MockResponse: Sendable {
        case success(Data)
        case failure(MockTransportError)

        func value() throws -> Data {
            switch self {
            case let .success(data):
                return data
            case let .failure(error):
                throw error
            }
        }
    }

    let responses: [URL: MockResponse]

    func fetchDiscoveryPayload(from url: URL, timeout: TimeInterval) async throws -> Data {
        guard let response = responses[url] else {
            throw MockTransportError.unavailable
        }
        return try response.value()
    }
}
