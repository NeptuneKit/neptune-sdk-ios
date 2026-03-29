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
    func ingestGatewayRawViewTree(after discovery: NeptuneGatewayDiscoveryResult) async throws
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

    func ingestGatewayRawViewTree(after discovery: NeptuneGatewayDiscoveryResult) async throws {
        let collector = NeptuneUIKitViewTreeCollectorBridge()
        let inspectorSnapshot = await collector.captureInspectorSnapshot(platform: "ios")
        guard inspectorSnapshot.available, inspectorSnapshot.payload != nil else {
            throw DemoRuntimeError.inspectorUnavailable
        }

        try await NeptuneGatewayIngestClient.sendRawViewTree(
            platform: "ios",
            appId: "com.neptunekit.demo.ios",
            sessionId: "simulator-session",
            deviceId: await Self.defaultDeviceID(),
            snapshot: inspectorSnapshot,
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
        let callbackEndpoint = URL(string: "http://\(demoCallbackHost):\(callbackPort)/v2/client/command")!

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
                preferredTransports: [.http],
                callbackEndpoint: callbackEndpoint,
                renewInterval: demoGatewayRegistrationRenewInterval,
                sdkName: "neptune-sdk-ios",
                sdkVersion: NeptuneExportService.version
            )
        )

        registrationClient = client
        log(DemoGatewayRegistrationOutputFormatter.started(
            callbackEndpoint: callbackEndpoint,
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

private enum DemoRuntimeError: LocalizedError {
    case inspectorUnavailable

    var errorDescription: String? {
        switch self {
        case .inspectorUnavailable:
            return "inspector payload unavailable"
        }
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
                callbackEndpoint: payload.callbackEndpoint
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
    static func started(callbackEndpoint: URL, renewInterval: TimeInterval) -> String {
        "gateway registration started: POST /v2/clients:register callbackEndpoint=\(callbackEndpoint.absoluteString) renewInterval=\(formatSeconds(renewInterval))s"
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

    static func registrationSuccess(gatewayEndpoint: URL, callbackEndpoint: URL) -> String {
        "gateway registration success: POST /v2/clients:register gatewayEndpoint=\(gatewayEndpoint.absoluteString) callbackEndpoint=\(callbackEndpoint.absoluteString)"
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

enum DemoGatewayViewTreeIngestOutputFormatter {
    static func success(endpoint: URL) -> String {
        "gateway ui-tree raw ingest success: endpoint=\(endpoint.absoluteString)"
    }

    static func failure(_ error: Error) -> String {
        "gateway ui-tree raw ingest failure: \(error.localizedDescription)"
    }
}

@MainActor
final class DemoViewController: UIViewController {
    static let actionButtonTitles: [String] = ["写入日志批次", "发现并上报", "刷新快照"]

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let bannerLabel = UILabel()
    private let batchLabel = UILabel()
    private let discoverySummaryLabel = UILabel()
    private let ingestSummaryLabel = UILabel()
    private let metricsLabel = UILabel()
    private let sourcesLabel = UILabel()
    private let outputView = UITextView()
    private let ingestButton = UIButton(type: .system)
    private let snapshotButton = UIButton(type: .system)
    private let discoveryButton = UIButton(type: .system)
    private let deepDiveButton = UIButton(type: .system)

    private let runtime: (any DemoRuntimeManaging)?
    private let runtimeError: String?
    private var didTriggerAutoGatewayRegistration = false
    private var batchCount = 0

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
        view.backgroundColor = UIColor(red: 0.024, green: 0.063, blue: 0.102, alpha: 1)
        setupViews()
        appendLine("Simulator demo ready")
        if let runtimeError {
            appendLine(runtimeError)
        }
        Task { await refreshSnapshotDashboard() }
        triggerAutoGatewayRegistrationIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        triggerAutoGatewayRegistrationIfNeeded()
    }

    private func setupViews() {
        ingestButton.setTitle(Self.actionButtonTitles[0], for: .normal)
        discoveryButton.setTitle(Self.actionButtonTitles[1], for: .normal)
        snapshotButton.setTitle(Self.actionButtonTitles[2], for: .normal)
        deepDiveButton.setTitle("进入复杂二级页", for: .normal)

        ingestButton.addTarget(self, action: #selector(onIngestTap), for: .touchUpInside)
        snapshotButton.addTarget(self, action: #selector(onSnapshotTap), for: .touchUpInside)
        discoveryButton.addTarget(self, action: #selector(onDiscoveryTap), for: .touchUpInside)
        deepDiveButton.addTarget(self, action: #selector(onDeepDiveTap), for: .touchUpInside)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        outputView.backgroundColor = .clear
        outputView.textColor = UIColor(red: 0.97, green: 0.98, blue: 1, alpha: 0.92)

        let heroCard = makeCard()
        let heroTitle = makeLabel(text: "Neptune SDK iOS Demo", size: 28, weight: .bold)
        heroTitle.numberOfLines = 2
        let heroSubtitle = makeLabel(
            text: "点击下方按钮，把日志写入 Runtime，并同步观察 gateway discovery、metrics 与 recent logs。",
            size: 14,
            weight: .regular,
            color: UIColor(red: 0.62, green: 0.70, blue: 0.78, alpha: 1)
        )
        heroSubtitle.numberOfLines = 0

        bannerLabel.text = "ready"
        batchLabel.text = "batch #0"
        styleChip(bannerLabel, background: UIColor(red: 0.14, green: 0.29, blue: 0.42, alpha: 1), textColor: .white)
        styleChip(batchLabel, background: UIColor(white: 1, alpha: 0.12), textColor: UIColor(red: 0.78, green: 0.83, blue: 0.90, alpha: 1))

        let chipRow = UIStackView(arrangedSubviews: [bannerLabel, batchLabel])
        chipRow.axis = .horizontal
        chipRow.spacing = 8

        let heroContent = UIStackView(arrangedSubviews: [heroTitle, heroSubtitle, chipRow])
        heroContent.axis = .vertical
        heroContent.spacing = 10
        heroCard.addSubview(heroContent)
        heroContent.translatesAutoresizingMaskIntoConstraints = false

        let discoveryCard = makeCard()
        let discoveryTitle = makeLabel(text: "Gateway Discovery", size: 18, weight: .bold)
        discoverySummaryLabel.text = "status=not-run"
        ingestSummaryLabel.text = "ingest status=not-run"
        [discoverySummaryLabel, ingestSummaryLabel].forEach {
            $0.numberOfLines = 0
            $0.font = .systemFont(ofSize: 13, weight: .regular)
            $0.textColor = UIColor(red: 0.66, green: 0.75, blue: 0.85, alpha: 1)
        }
        let discoveryContent = UIStackView(arrangedSubviews: [discoveryTitle, discoverySummaryLabel, ingestSummaryLabel])
        discoveryContent.axis = .vertical
        discoveryContent.spacing = 8
        discoveryCard.addSubview(discoveryContent)
        discoveryContent.translatesAutoresizingMaskIntoConstraints = false

        [ingestButton, discoveryButton, snapshotButton].forEach(stylePrimaryButton(_:))
        let controls = UIStackView(arrangedSubviews: [ingestButton, discoveryButton, snapshotButton])
        controls.axis = .vertical
        controls.spacing = 12

        let deepDiveCard = makeCard()
        let deepDiveTitle = makeLabel(text: "Neptune Deep Dive", size: 18, weight: .bold)
        let deepDiveSubtitle = makeLabel(
            text: "复杂二级页包含标签切换、指标矩阵、时间轴和诊断卡片，用于验证真实视图树采集。",
            size: 13,
            weight: .regular,
            color: UIColor(red: 0.66, green: 0.75, blue: 0.85, alpha: 1)
        )
        deepDiveSubtitle.numberOfLines = 0
        let deepDiveContent = UIStackView(arrangedSubviews: [deepDiveTitle, deepDiveSubtitle, deepDiveButton])
        deepDiveContent.axis = .vertical
        deepDiveContent.spacing = 10
        deepDiveCard.addSubview(deepDiveContent)
        deepDiveContent.translatesAutoresizingMaskIntoConstraints = false
        deepDiveButton.configuration = .filled()
        deepDiveButton.configuration?.baseBackgroundColor = UIColor(red: 0.46, green: 0.83, blue: 0.97, alpha: 1)
        deepDiveButton.configuration?.baseForegroundColor = UIColor(red: 0.02, green: 0.07, blue: 0.11, alpha: 1)
        deepDiveButton.configuration?.cornerStyle = .capsule
        deepDiveButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        deepDiveButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)

        let metricsCard = makeCard()
        let metricsTitle = makeLabel(text: "Metrics", size: 18, weight: .bold)
        metricsLabel.numberOfLines = 0
        metricsLabel.font = .systemFont(ofSize: 13, weight: .regular)
        metricsLabel.textColor = UIColor(red: 0.66, green: 0.75, blue: 0.85, alpha: 1)
        let metricsContent = UIStackView(arrangedSubviews: [metricsTitle, metricsLabel])
        metricsContent.axis = .vertical
        metricsContent.spacing = 10
        metricsCard.addSubview(metricsContent)
        metricsContent.translatesAutoresizingMaskIntoConstraints = false

        let sourcesCard = makeCard()
        let sourcesTitle = makeLabel(text: "Sources", size: 18, weight: .bold)
        sourcesLabel.numberOfLines = 0
        sourcesLabel.font = .systemFont(ofSize: 13, weight: .regular)
        sourcesLabel.textColor = UIColor(red: 0.66, green: 0.75, blue: 0.85, alpha: 1)
        sourcesLabel.text = "no source yet"
        let sourcesContent = UIStackView(arrangedSubviews: [sourcesTitle, sourcesLabel])
        sourcesContent.axis = .vertical
        sourcesContent.spacing = 10
        sourcesCard.addSubview(sourcesContent)
        sourcesContent.translatesAutoresizingMaskIntoConstraints = false

        let logsCard = makeCard()
        let logsTitle = makeLabel(text: "Recent logs", size: 18, weight: .bold)
        let logsContent = UIStackView(arrangedSubviews: [logsTitle, outputView])
        logsContent.axis = .vertical
        logsContent.spacing = 10
        logsCard.addSubview(logsContent)
        logsContent.translatesAutoresizingMaskIntoConstraints = false

        [heroCard, discoveryCard, controls, deepDiveCard, metricsCard, sourcesCard, logsCard].forEach(contentStack.addArrangedSubview(_:))

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),

            heroContent.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 20),
            heroContent.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 20),
            heroContent.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -20),
            heroContent.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: -20),
            bannerLabel.heightAnchor.constraint(equalToConstant: 28),
            batchLabel.heightAnchor.constraint(equalToConstant: 28),
            bannerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68),
            batchLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),

            discoveryContent.topAnchor.constraint(equalTo: discoveryCard.topAnchor, constant: 20),
            discoveryContent.leadingAnchor.constraint(equalTo: discoveryCard.leadingAnchor, constant: 20),
            discoveryContent.trailingAnchor.constraint(equalTo: discoveryCard.trailingAnchor, constant: -20),
            discoveryContent.bottomAnchor.constraint(equalTo: discoveryCard.bottomAnchor, constant: -20),

            deepDiveContent.topAnchor.constraint(equalTo: deepDiveCard.topAnchor, constant: 20),
            deepDiveContent.leadingAnchor.constraint(equalTo: deepDiveCard.leadingAnchor, constant: 20),
            deepDiveContent.trailingAnchor.constraint(equalTo: deepDiveCard.trailingAnchor, constant: -20),
            deepDiveContent.bottomAnchor.constraint(equalTo: deepDiveCard.bottomAnchor, constant: -20),

            metricsContent.topAnchor.constraint(equalTo: metricsCard.topAnchor, constant: 20),
            metricsContent.leadingAnchor.constraint(equalTo: metricsCard.leadingAnchor, constant: 20),
            metricsContent.trailingAnchor.constraint(equalTo: metricsCard.trailingAnchor, constant: -20),
            metricsContent.bottomAnchor.constraint(equalTo: metricsCard.bottomAnchor, constant: -20),

            sourcesContent.topAnchor.constraint(equalTo: sourcesCard.topAnchor, constant: 20),
            sourcesContent.leadingAnchor.constraint(equalTo: sourcesCard.leadingAnchor, constant: 20),
            sourcesContent.trailingAnchor.constraint(equalTo: sourcesCard.trailingAnchor, constant: -20),
            sourcesContent.bottomAnchor.constraint(equalTo: sourcesCard.bottomAnchor, constant: -20),

            logsContent.topAnchor.constraint(equalTo: logsCard.topAnchor, constant: 20),
            logsContent.leadingAnchor.constraint(equalTo: logsCard.leadingAnchor, constant: 20),
            logsContent.trailingAnchor.constraint(equalTo: logsCard.trailingAnchor, constant: -20),
            logsContent.bottomAnchor.constraint(equalTo: logsCard.bottomAnchor, constant: -20),
            outputView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    @objc private func onIngestTap() {
        guard let runtime else { return }
        Task {
            let records = [
                await runtime.ingestOne(),
                await runtime.ingestOne(),
                await runtime.ingestOne()
            ]
            self.batchCount += 1
            let ids = records.map(\.id).map(String.init).joined(separator: ",")
            await MainActor.run {
                self.appendLine("write batch size=3 ids=[\(ids)]")
            }
            await refreshSnapshotDashboard()
        }
    }

    @objc private func onSnapshotTap() {
        guard runtime != nil else { return }
        Task {
            await refreshSnapshotDashboard(appendSummary: true)
        }
    }

    @objc private func onDiscoveryTap() {
        guard runtime != nil else { return }
        Task { await runDiscoveryFlow() }
    }

    @objc private func onDeepDiveTap() {
        openDeepDivePage()
    }

    func openDeepDivePage() {
        let deepDive = DeepDiveViewController()
        navigationController?.pushViewController(deepDive, animated: true)
    }

    private func triggerAutoGatewayRegistrationIfNeeded() {
        guard !didTriggerAutoGatewayRegistration else { return }
        guard let runtime else { return }
        didTriggerAutoGatewayRegistration = true
        Task { [weak self] in
            await runtime.startGatewayRegistration(log: { [weak self] text in
                DispatchQueue.main.async { [weak self] in
                    self?.appendLine(text)
                }
            })
            // Bootstrap one discovery+ingest cycle so gateway has real logs and ui-tree data
            // before the user manually taps "发现并上报".
            await self?.runDiscoveryFlow()
        }
    }

    private func runDiscoveryFlow() async {
        guard let runtime else { return }
        do {
            let result = try await runtime.discoverGateway()
            await MainActor.run {
                self.appendLine(DemoDiscoveryOutputFormatter.success(result))
                self.bannerLabel.text = "discover ok"
                self.discoverySummaryLabel.text = "status=ok source=\(result.source.rawValue) host=\(result.host) port=\(result.port) version=\(result.version)"
                self.sourcesLabel.text = "source=\(result.source.rawValue) host=\(result.host):\(result.port)"
            }
            do {
                try await runtime.ingestGatewayLog(after: result)
                await MainActor.run {
                    self.appendLine(DemoGatewayIngestOutputFormatter.success(endpoint: result.endpoint))
                    self.ingestSummaryLabel.text = "ingest status=ok endpoint=\(result.endpoint.absoluteString)"
                }
            } catch {
                await MainActor.run {
                    self.appendLine(DemoGatewayIngestOutputFormatter.failure(error))
                    self.ingestSummaryLabel.text = "ingest status=error error=\(error.localizedDescription)"
                }
            }
            do {
                try await runtime.ingestGatewayRawViewTree(after: result)
                await MainActor.run {
                    self.appendLine(DemoGatewayViewTreeIngestOutputFormatter.success(endpoint: result.endpoint))
                }
            } catch {
                await MainActor.run {
                    self.appendLine(DemoGatewayViewTreeIngestOutputFormatter.failure(error))
                }
            }
        } catch {
            await MainActor.run {
                self.appendLine(DemoDiscoveryOutputFormatter.failure(error))
                self.bannerLabel.text = "discover failed"
                self.discoverySummaryLabel.text = "status=error error=\(error.localizedDescription)"
                self.sourcesLabel.text = "no source yet"
            }
        }
    }

    private func refreshSnapshotDashboard(appendSummary: Bool = false) async {
        guard let runtime else { return }
        let (metrics, page) = await runtime.snapshot()
        let ids = page.records.map(\.id).map(String.init).joined(separator: ",")

        await MainActor.run {
            self.batchLabel.text = "batch #\(self.batchCount)"
            self.metricsLabel.text = """
            queueSize=\(metrics.totalRecords)
            totalIngested=\(metrics.totalRecords)
            droppedOverflow=\(metrics.droppedOverflow)
            totalExported=\(metrics.totalRecords)
            """
            if appendSummary {
                self.appendLine("metrics total=\(metrics.totalRecords) dropped=\(metrics.droppedOverflow) latest=\(metrics.newestRecordId.map(String.init) ?? "nil")")
                self.appendLine("logs count=\(page.records.count) ids=[\(ids)]")
            }
        }
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.035, green: 0.071, blue: 0.122, alpha: 0.95)
        card.layer.cornerRadius = 24
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.41, green: 0.56, blue: 0.69, alpha: 0.25).cgColor
        return card
    }

    private func makeLabel(text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor = UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1)) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func styleChip(_ label: UILabel, background: UIColor, textColor: UIColor) {
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = textColor
        label.backgroundColor = background
        label.layer.cornerRadius = 999
        label.clipsToBounds = true
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
    }

    private func stylePrimaryButton(_ button: UIButton) {
        button.configuration = .filled()
        button.configuration?.baseBackgroundColor = UIColor(red: 0.46, green: 0.83, blue: 0.97, alpha: 1)
        button.configuration?.baseForegroundColor = UIColor(red: 0.02, green: 0.07, blue: 0.11, alpha: 1)
        button.configuration?.cornerStyle = .capsule
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
    }

    private func appendLine(_ text: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(text)\n"
        print(text)
        outputView.text = outputView.text + line
        let range = NSRange(location: max(outputView.text.count - 1, 0), length: 1)
        outputView.scrollRangeToVisible(range)
    }
}
