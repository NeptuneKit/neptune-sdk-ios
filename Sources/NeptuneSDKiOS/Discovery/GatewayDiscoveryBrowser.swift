import Foundation

public protocol NeptuneGatewayDiscoveryBrowsing: Sendable {
    func candidates() async -> [NeptuneGatewayDiscoveryCandidate]
}

public final class NeptuneBonjourGatewayDiscoveryBrowser: NSObject, NeptuneGatewayDiscoveryBrowsing, @unchecked Sendable {
    private let serviceType: String
    private let domain: String
    private let timeout: TimeInterval
    private let maxCandidates: Int

    public init(
        serviceType: String = "_neptune._tcp.",
        domain: String = "local.",
        timeout: TimeInterval = 3.0,
        maxCandidates: Int = 8
    ) {
        self.serviceType = serviceType
        self.domain = domain
        self.timeout = timeout
        self.maxCandidates = max(1, maxCandidates)
    }

    public func candidates() async -> [NeptuneGatewayDiscoveryCandidate] {
        await Task.detached(priority: .utility) { [serviceType, domain, timeout, maxCandidates] in
            Self.resolveCandidates(
                serviceType: serviceType,
                domain: domain,
                timeout: timeout,
                maxCandidates: maxCandidates
            )
        }.value
    }

    private static func resolveCandidates(
        serviceType: String,
        domain: String,
        timeout: TimeInterval,
        maxCandidates: Int
    ) -> [NeptuneGatewayDiscoveryCandidate] {
        let session = BrowserSession(
            serviceType: serviceType,
            domain: domain,
            timeout: timeout,
            maxCandidates: maxCandidates
        )
        return session.run()
    }
}

private final class BrowserSession: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private let serviceType: String
    private let domain: String
    private let timeout: TimeInterval
    private let maxCandidates: Int
    private var services: [NetService] = []
    private var pendingResolutions = 0
    private var browserCompleted = false
    private var finished = false
    private var candidates: [NeptuneGatewayDiscoveryCandidate] = []
    private var seenKeys: Set<String> = []

    init(serviceType: String, domain: String, timeout: TimeInterval, maxCandidates: Int) {
        self.serviceType = serviceType
        self.domain = domain
        self.timeout = timeout
        self.maxCandidates = maxCandidates
    }

    func run() -> [NeptuneGatewayDiscoveryCandidate] {
        browser.delegate = self
        browser.schedule(in: .current, forMode: .default)
        browser.searchForServices(ofType: serviceType, inDomain: domain)

        let deadline = Date().addingTimeInterval(timeout)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }

        finish()
        return candidates
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !finished else {
            return
        }

        services.append(service)
        pendingResolutions += 1
        service.delegate = self
        service.schedule(in: .current, forMode: .default)
        service.resolve(withTimeout: timeout)

        if !moreComing {
            browserCompleted = true
            finishIfPossible()
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        browserCompleted = true
        finishIfPossible()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        browserCompleted = true
        finishIfPossible()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard !finished, let host = sender.hostName, !host.isEmpty else {
            pendingResolutions = max(0, pendingResolutions - 1)
            finishIfPossible()
            return
        }

        let port = Int(sender.port)
        guard port > 0 else {
            pendingResolutions = max(0, pendingResolutions - 1)
            finishIfPossible()
            return
        }

        let key = "\(host.lowercased()):\(port)"
        if !seenKeys.contains(key), let url = Self.makeBaseURL(host: host, port: port) {
            seenKeys.insert(key)
            candidates.append(.init(url: url, source: .mdns))
        }

        pendingResolutions = max(0, pendingResolutions - 1)
        finishIfPossible()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        pendingResolutions = max(0, pendingResolutions - 1)
        finishIfPossible()
    }

    private func finishIfPossible() {
        if candidates.count >= maxCandidates {
            finish()
            return
        }

        if browserCompleted && pendingResolutions == 0 {
            finish()
        }
    }

    private func finish() {
        guard !finished else {
            return
        }

        finished = true
        browser.stop()
        browser.remove(from: .current, forMode: .default)

        for service in services {
            service.stop()
            service.remove(from: .current, forMode: .default)
        }
    }

    private static func makeBaseURL(host: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = ""
        return components.url
    }
}

