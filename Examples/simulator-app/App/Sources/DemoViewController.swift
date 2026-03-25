import NeptuneSDKiOS
import UIKit

private let demoGatewayBaseURL = URL(string: "http://127.0.0.1:18765")!
private let demoCallbackHost = "127.0.0.1"
private let demoGatewayRegistrationRenewInterval: TimeInterval = 5

protocol DemoRuntimeManaging: Sendable {
    func ingestOne() async -> NeptuneLogRecord
    func snapshot() async -> (NeptuneMetricsSnapshot, NeptuneLogsPage)
    func startServerIfNeeded() async throws -> UInt16
    func discoverGateway() async throws -> NeptuneGatewayDiscoveryResult
    func ingestGatewayLog(after discovery: NeptuneGatewayDiscoveryResult) async throws
    func startGatewayRegistration(log: @escaping @Sendable (String) -> Void) async
}

private actor DemoRuntime: DemoRuntimeManaging {
    private let service: NeptuneExportService
    private let server: NeptuneExportHTTPServer
    private let discoveryClient: NeptuneGatewayDiscoveryClient
    private var registrationClient: NeptuneGatewayRegistrationClient?
    private var serverStarted = false
    private let preferredPort: UInt16 = 18766

    init() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let dbPath = docs?.appendingPathComponent("neptune-demo.sqlite").path ?? NSTemporaryDirectory() + "/neptune-demo.sqlite"
        service = try NeptuneSDKiOS.makeExportService(storage: .sqlite(path: dbPath), capacity: 2_000)
        server = NeptuneSDKiOS.makeExportHTTPServer(service: service)
        discoveryClient = NeptuneSDKiOS.makeGatewayDiscoveryClient(
            configuration: .init(manualDSN: demoGatewayBaseURL)
        )
    }

    func ingestOne() async -> NeptuneLogRecord {
        let deviceId = await Self.defaultDeviceID()
        return await service.ingest(
            NeptuneIngestLogRecord(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                level: .info,
                message: "demo-log-\(UUID().uuidString.prefix(8))",
                platform: "ios",
                appId: "com.neptunekit.demo.ios",
                sessionId: "simulator-session",
                deviceId: deviceId,
                category: "demo",
                attributes: ["screen": "DemoViewController"],
                source: NeptuneLogSource(sdkName: "neptune-sdk-ios", sdkVersion: "0.1.0")
            )
        )
    }

    func snapshot() async -> (NeptuneMetricsSnapshot, NeptuneLogsPage) {
        async let metrics = service.metrics()
        async let logs = service.logs(cursor: nil, limit: 20)
        return await (metrics, logs)
    }

    func startServerIfNeeded() async throws -> UInt16 {
        if !serverStarted {
            try await server.start(port: preferredPort)
            serverStarted = true
        }
        return await server.listeningPort() ?? preferredPort
    }

    func discoverGateway() async throws -> NeptuneGatewayDiscoveryResult {
        try await discoveryClient.discover()
    }

    func ingestGatewayLog(after discovery: NeptuneGatewayDiscoveryResult) async throws {
        try await NeptuneGatewayIngestClient.send(
            Self.makeGatewayIngestRecord(discovery: discovery),
            to: discovery.endpoint
        )
    }

    func startGatewayRegistration(log: @escaping @Sendable (String) -> Void) async {
        guard registrationClient == nil else {
            return
        }
        let callbackPort: UInt16
        do {
            callbackPort = try await startServerIfNeeded()
        } catch {
            log("gateway registration skipped: failed to start callback server: \(error.localizedDescription)")
            return
        }
        let commandURL = URL(string: "http://\(demoCallbackHost):\(callbackPort)/v2/client/command")!

        let loggingDiscovery = DemoLoggingGatewayDiscoveryClient(
            discovery: discoveryClient,
            log: log
        )
        let loggingTransport = DemoLoggingGatewayRegistrationTransport(
            transport: NeptuneURLSessionGatewayRegistrationTransport(),
            log: log
        )
        let client = NeptuneSDKiOS.makeGatewayRegistrationClient(
            discovery: loggingDiscovery,
            transport: loggingTransport,
            configuration: .init(
                appId: "com.neptunekit.demo.ios",
                sessionId: "simulator-session",
                deviceId: await Self.defaultDeviceID(),
                commandUrl: commandURL,
                renewInterval: demoGatewayRegistrationRenewInterval,
                sdkName: "neptune-sdk-ios",
                sdkVersion: NeptuneExportService.version
            )
        )

        registrationClient = client
        log(DemoGatewayRegistrationOutputFormatter.started(
            commandUrl: commandURL,
            renewInterval: demoGatewayRegistrationRenewInterval
        ))
        await client.start()
    }

    @MainActor
    private static func makeGatewayIngestRecord(discovery: NeptuneGatewayDiscoveryResult) -> NeptuneIngestLogRecord {
        NeptuneIngestLogRecord(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            level: .info,
            message: "discovery-triggered gateway ingest",
            platform: "ios",
            appId: "com.neptunekit.demo.ios",
            sessionId: "simulator-session",
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "simulator",
            category: "gateway-discovery",
            attributes: [
                "screen": "DemoViewController",
                "gatewaySource": discovery.source.rawValue,
                "gatewayVersion": discovery.version,
                "gatewayEndpoint": discovery.endpoint.absoluteString
            ],
            source: NeptuneLogSource(
                sdkName: "neptune-sdk-ios",
                sdkVersion: "0.1.0",
                file: #fileID,
                function: #function,
                line: #line
            )
        )
    }

    @MainActor
    private static func defaultDeviceID() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "simulator"
    }
}

private struct DemoLoggingGatewayDiscoveryClient: NeptuneGatewayDiscovering {
    let discovery: any NeptuneGatewayDiscovering
    let log: @Sendable (String) -> Void

    func discover() async throws -> NeptuneGatewayDiscoveryResult {
        log(DemoGatewayRegistrationOutputFormatter.discoveryAttempt())

        do {
            let result = try await discovery.discover()
            log(DemoGatewayRegistrationOutputFormatter.discoverySuccess(result))
            return result
        } catch {
            log(DemoGatewayRegistrationOutputFormatter.discoveryFailure(error))
            throw error
        }
    }
}

private struct DemoLoggingGatewayRegistrationTransport: NeptuneGatewayRegistrationTransport {
    let transport: any NeptuneGatewayRegistrationTransport
    let log: @Sendable (String) -> Void

    func send(payload: NeptuneGatewayRegistrationPayload, to gatewayEndpoint: URL) async throws {
        do {
            try await transport.send(payload: payload, to: gatewayEndpoint)
            log(DemoGatewayRegistrationOutputFormatter.registrationSuccess(
                gatewayEndpoint: gatewayEndpoint,
                commandUrl: payload.commandUrl
            ))
        } catch {
            log(DemoGatewayRegistrationOutputFormatter.registrationFailure(
                error,
                gatewayEndpoint: gatewayEndpoint
            ))
            throw error
        }
    }
}

enum DemoDiscoveryOutputFormatter {
    static func success(_ result: NeptuneGatewayDiscoveryResult) -> String {
        "discovery success: source=\(result.source.rawValue) host=\(result.host) port=\(result.port) version=\(result.version) endpoint=\(result.endpoint.absoluteString)"
    }

    static func failure(_ error: Error) -> String {
        "discovery failure: \(error.localizedDescription)"
    }
}

enum DemoGatewayRegistrationOutputFormatter {
    static func started(commandUrl: URL, renewInterval: TimeInterval) -> String {
        "gateway registration started: POST /v2/clients:register commandUrl=\(commandUrl.absoluteString) renewInterval=\(formatSeconds(renewInterval))s"
    }

    static func discoveryAttempt() -> String {
        "gateway registration discovery attempt"
    }

    static func discoverySuccess(_ result: NeptuneGatewayDiscoveryResult) -> String {
        "gateway registration discovery success: source=\(result.source.rawValue) host=\(result.host) port=\(result.port) version=\(result.version) endpoint=\(result.endpoint.absoluteString)"
    }

    static func discoveryFailure(_ error: Error) -> String {
        "gateway registration discovery failure: \(error.localizedDescription)"
    }

    static func registrationSuccess(gatewayEndpoint: URL, commandUrl: URL) -> String {
        "gateway registration success: POST /v2/clients:register gatewayEndpoint=\(gatewayEndpoint.absoluteString) commandUrl=\(commandUrl.absoluteString)"
    }

    static func registrationFailure(_ error: Error, gatewayEndpoint: URL) -> String {
        "gateway registration failure: gatewayEndpoint=\(gatewayEndpoint.absoluteString) error=\(error.localizedDescription)"
    }

    private static func formatSeconds(_ value: TimeInterval) -> String {
        guard value.rounded() != value else {
            return String(Int(value))
        }
        return String(value)
    }
}

enum DemoGatewayIngestOutputFormatter {
    static func success(endpoint: URL) -> String {
        "gateway ingest success: endpoint=\(endpoint.absoluteString)"
    }

    static func failure(_ error: Error) -> String {
        "gateway ingest failure: \(error.localizedDescription)"
    }
}

@MainActor
final class DemoViewController: UIViewController {
    private let outputView = UITextView()
    private let ingestButton = UIButton(type: .system)
    private let metricsButton = UIButton(type: .system)
    private let serverButton = UIButton(type: .system)
    private let discoveryButton = UIButton(type: .system)

    private let runtime: (any DemoRuntimeManaging)?
    private let runtimeError: String?
    private var didTriggerAutoGatewayRegistration = false

    init(
        runtime: (any DemoRuntimeManaging)? = nil,
        runtimeError: String? = nil
    ) {
        if let runtime {
            self.runtime = runtime
            self.runtimeError = runtimeError
        } else {
            do {
                self.runtime = try DemoRuntime()
                self.runtimeError = nil
            } catch {
                self.runtime = nil
                self.runtimeError = "Runtime 初始化失败: \(error.localizedDescription)"
            }
        }
        super.init(nibName: nil, bundle: nil)
        title = "Neptune iOS Demo"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViews()
        appendLine("Simulator demo ready")
        if let runtimeError {
            appendLine(runtimeError)
        }
        triggerAutoGatewayRegistrationIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        triggerAutoGatewayRegistrationIfNeeded()
    }

    private func setupViews() {
        ingestButton.setTitle("Ingest 1 Log", for: .normal)
        metricsButton.setTitle("Show Metrics", for: .normal)
        serverButton.setTitle("Start Export Server", for: .normal)
        discoveryButton.setTitle("Discover Gateway", for: .normal)

        ingestButton.addTarget(self, action: #selector(onIngestTap), for: .touchUpInside)
        metricsButton.addTarget(self, action: #selector(onMetricsTap), for: .touchUpInside)
        serverButton.addTarget(self, action: #selector(onServerTap), for: .touchUpInside)
        discoveryButton.addTarget(self, action: #selector(onDiscoveryTap), for: .touchUpInside)

        let controls = UIStackView(arrangedSubviews: [ingestButton, metricsButton, serverButton, discoveryButton])
        controls.axis = .vertical
        controls.spacing = 12

        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        let stack = UIStackView(arrangedSubviews: [controls, outputView])
        stack.axis = .vertical
        stack.spacing = 16

        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    @objc private func onIngestTap() {
        guard let runtime else { return }
        Task {
            let record = await runtime.ingestOne()
            await MainActor.run {
                self.appendLine("ingest id=\(record.id) level=\(record.level.rawValue) msg=\(record.message)")
            }
        }
    }

    @objc private func onMetricsTap() {
        guard let runtime else { return }
        Task {
            let (metrics, page) = await runtime.snapshot()
            let ids = page.records.map(\.id).map(String.init).joined(separator: ",")
            await MainActor.run {
                self.appendLine("metrics total=\(metrics.totalRecords) dropped=\(metrics.droppedOverflow) latest=\(metrics.newestRecordId.map(String.init) ?? "nil")")
                self.appendLine("logs count=\(page.records.count) ids=[\(ids)]")
            }
        }
    }

    @objc private func onServerTap() {
        guard let runtime else { return }
        Task {
            do {
                let port = try await runtime.startServerIfNeeded()
                await MainActor.run {
                    self.appendLine("server listening at http://127.0.0.1:\(port)/v2/export/health")
                }
            } catch {
                await MainActor.run {
                    self.appendLine("server start failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func onDiscoveryTap() {
        guard let runtime else { return }
        Task { await runDiscoveryFlow() }
    }

    private func triggerAutoGatewayRegistrationIfNeeded() {
        guard !didTriggerAutoGatewayRegistration else { return }
        guard let runtime else { return }
        didTriggerAutoGatewayRegistration = true
        Task {
            await runtime.startGatewayRegistration(log: { [weak self] text in
                DispatchQueue.main.async { [weak self] in
                    self?.appendLine(text)
                }
            })
        }
    }

    private func runDiscoveryFlow() async {
        guard let runtime else { return }
        do {
            let result = try await runtime.discoverGateway()
            await MainActor.run {
                self.appendLine(DemoDiscoveryOutputFormatter.success(result))
            }
            do {
                try await runtime.ingestGatewayLog(after: result)
                await MainActor.run {
                    self.appendLine(DemoGatewayIngestOutputFormatter.success(endpoint: result.endpoint))
                }
            } catch {
                await MainActor.run {
                    self.appendLine(DemoGatewayIngestOutputFormatter.failure(error))
                }
            }
        } catch {
            await MainActor.run {
                self.appendLine(DemoDiscoveryOutputFormatter.failure(error))
            }
        }
    }

    private func appendLine(_ text: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(text)\n"
        print(text)
        outputView.text = outputView.text + line
        let range = NSRange(location: max(outputView.text.count - 1, 0), length: 1)
        outputView.scrollRangeToVisible(range)
    }
}
