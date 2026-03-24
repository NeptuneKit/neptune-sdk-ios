import NeptuneSDKiOS
import UIKit

private actor DemoRuntime {
    private let service: NeptuneExportService
    private let server: NeptuneExportHTTPServer
    private var serverStarted = false
    private let preferredPort: UInt16 = 18765

    init() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let dbPath = docs?.appendingPathComponent("neptune-demo.sqlite").path ?? NSTemporaryDirectory() + "/neptune-demo.sqlite"
        service = try NeptuneSDKiOS.makeExportService(storage: .sqlite(path: dbPath), capacity: 2_000)
        server = NeptuneSDKiOS.makeExportHTTPServer(service: service)
    }

    func ingestOne() async -> NeptuneLogRecord {
        await service.ingest(
            NeptuneIngestLogRecord(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                level: .info,
                message: "demo-log-\(UUID().uuidString.prefix(8))",
                platform: "ios",
                appId: "com.neptunekit.demo.ios",
                sessionId: "simulator-session",
                deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "simulator",
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
}

final class DemoViewController: UIViewController {
    private let outputView = UITextView()
    private let ingestButton = UIButton(type: .system)
    private let metricsButton = UIButton(type: .system)
    private let serverButton = UIButton(type: .system)

    private let runtime: DemoRuntime?
    private let runtimeError: String?

    init() {
        do {
            runtime = try DemoRuntime()
            runtimeError = nil
        } catch {
            runtime = nil
            runtimeError = "Runtime 初始化失败: \(error.localizedDescription)"
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
    }

    private func setupViews() {
        ingestButton.setTitle("Ingest 1 Log", for: .normal)
        metricsButton.setTitle("Show Metrics", for: .normal)
        serverButton.setTitle("Start Export Server", for: .normal)

        ingestButton.addTarget(self, action: #selector(onIngestTap), for: .touchUpInside)
        metricsButton.addTarget(self, action: #selector(onMetricsTap), for: .touchUpInside)
        serverButton.addTarget(self, action: #selector(onServerTap), for: .touchUpInside)

        let controls = UIStackView(arrangedSubviews: [ingestButton, metricsButton, serverButton])
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

    private func appendLine(_ text: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(text)\n"
        outputView.text = outputView.text + line
        let range = NSRange(location: max(outputView.text.count - 1, 0), length: 1)
        outputView.scrollRangeToVisible(range)
    }
}
