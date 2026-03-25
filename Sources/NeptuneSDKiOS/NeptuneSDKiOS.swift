@_exported import Foundation

public struct NeptuneSDKiOS {
    public static func makeExportService() -> NeptuneExportService {
        NeptuneExportService()
    }

    public static func makeExportService(
        storage: NeptuneLogQueue.Storage,
        capacity: Int = NeptuneLogQueue.capacity
    ) throws -> NeptuneExportService {
        try NeptuneExportService(storage: storage, capacity: capacity)
    }

    public static func makeExportHTTPServer(service: NeptuneExportService = NeptuneExportService()) -> NeptuneExportHTTPServer {
        NeptuneExportHTTPServer(service: service)
    }

    public static func makeGatewayDiscoveryClient(
        configuration: NeptuneGatewayDiscoveryConfiguration = .init()
    ) -> NeptuneGatewayDiscoveryClient {
        NeptuneGatewayDiscoveryClient(configuration: configuration)
    }

    public static func makeGatewayWebSocketClient(
        discovery: any NeptuneGatewayDiscovering = NeptuneGatewayDiscoveryClient(),
        transport: any NeptuneGatewayWebSocketTransport = NeptuneURLSessionGatewayWebSocketTransport(),
        configuration: NeptuneGatewayWebSocketConfiguration = .init(),
        output: @escaping @Sendable (String) -> Void = { _ in }
    ) -> NeptuneGatewayWebSocketClient {
        NeptuneGatewayWebSocketClient(
            discovery: discovery,
            transport: transport,
            configuration: configuration,
            output: output
        )
    }

    public static func makeGatewayRegistrationClient(
        discovery: any NeptuneGatewayDiscovering = NeptuneGatewayDiscoveryClient(),
        transport: any NeptuneGatewayRegistrationTransport = NeptuneURLSessionGatewayRegistrationTransport(),
        sleeper: any NeptuneGatewayRegistrationSleeping = NeptuneTaskGatewayRegistrationSleeper(),
        configuration: NeptuneGatewayRegistrationConfiguration
    ) -> NeptuneGatewayRegistrationClient {
        NeptuneGatewayRegistrationClient(
            discovery: discovery,
            transport: transport,
            sleeper: sleeper,
            configuration: configuration
        )
    }
}
