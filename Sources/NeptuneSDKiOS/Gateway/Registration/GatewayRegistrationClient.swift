import Foundation

public protocol NeptuneGatewayRegistrationSleeping: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

public struct NeptuneTaskGatewayRegistrationSleeper: NeptuneGatewayRegistrationSleeping, Sendable {
    public init() {}

    public func sleep(for seconds: TimeInterval) async throws {
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}

public actor NeptuneGatewayRegistrationClient {
    private let discovery: any NeptuneGatewayDiscovering
    private let transport: any NeptuneGatewayRegistrationTransport
    private let sleeper: any NeptuneGatewayRegistrationSleeping
    private let configuration: NeptuneGatewayRegistrationConfiguration
    private var runTask: Task<Void, Never>?

    public init(
        discovery: any NeptuneGatewayDiscovering = NeptuneGatewayDiscoveryClient(),
        transport: any NeptuneGatewayRegistrationTransport = NeptuneURLSessionGatewayRegistrationTransport(),
        sleeper: any NeptuneGatewayRegistrationSleeping = NeptuneTaskGatewayRegistrationSleeper(),
        configuration: NeptuneGatewayRegistrationConfiguration
    ) {
        self.discovery = discovery
        self.transport = transport
        self.sleeper = sleeper
        self.configuration = configuration
    }

    public func start() {
        guard runTask == nil else {
            return
        }

        runTask = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }
    }

    public func stop() async {
        let task = runTask
        runTask = nil
        task?.cancel()
        await task?.value
    }

    public func registerNow() async {
        await registerOnce()
    }

    private func run() async {
        await registerOnce()

        guard configuration.renewInterval > 0 else {
            return
        }

        while !Task.isCancelled {
            do {
                try await sleeper.sleep(for: configuration.renewInterval)
            } catch {
                return
            }

            if Task.isCancelled {
                return
            }

            await registerOnce()
        }
    }

    private func registerOnce() async {
        do {
            try Task.checkCancellation()
            let gateway = try await discovery.discover()
            try Task.checkCancellation()
            try await transport.send(payload: configuration.payload, to: gateway.endpoint)
        } catch {
            return
        }
    }
}

