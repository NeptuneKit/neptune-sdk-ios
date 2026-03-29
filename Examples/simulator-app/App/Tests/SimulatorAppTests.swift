import XCTest
import NeptuneSDKiOS
@testable import SimulatorApp

@MainActor
final class SimulatorAppTests: XCTestCase {
    func testDemoPlaceholder() {
        XCTAssertTrue(true)
    }

    func testDiscoveryOutputFormatterIncludesGatewayFields() {
        let result = NeptuneGatewayDiscoveryResult(
            endpoint: URL(string: "http://127.0.0.1:18765")!,
            source: .manualDSN,
            host: "127.0.0.1",
            port: 18765,
            version: "2.0.0-alpha.1"
        )

        XCTAssertEqual(
            DemoDiscoveryOutputFormatter.success(result),
            "discovery success: source=manualDSN host=127.0.0.1 port=18765 version=2.0.0-alpha.1 endpoint=http://127.0.0.1:18765"
        )
    }

    func testDiscoveryOutputFormatterIncludesFailureMessage() {
        let error = NSError(
            domain: "NeptuneGatewayDiscovery",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "gateway unavailable"]
        )

        XCTAssertEqual(
            DemoDiscoveryOutputFormatter.failure(error),
            "discovery failure: gateway unavailable"
        )
    }

    func testAutoGatewayRegistrationStartsOnInitialLoad() async throws {
        let runtime = DemoRuntimeSpy()
        let controller = await MainActor.run {
            DemoViewController(runtime: runtime)
        }

        await MainActor.run {
            controller.loadViewIfNeeded()
        }

        let started = await eventually(timeout: 1) {
            await runtime.startGatewayRegistrationCount() == 1
        }
        XCTAssertTrue(started)

        await MainActor.run {
            controller.viewDidAppear(false)
        }

        let count = await runtime.startGatewayRegistrationCount()
        XCTAssertEqual(count, 1)
    }

    func testGatewayRegistrationOutputFormatterIncludesClientsRegister() {
        let callbackEndpoint = URL(string: "http://127.0.0.1:18766/v2/client/command")!

        XCTAssertEqual(
            DemoGatewayRegistrationOutputFormatter.started(
                callbackEndpoint: callbackEndpoint,
                renewInterval: 5
            ),
            "gateway registration started: POST /v2/clients:register callbackEndpoint=http://127.0.0.1:18766/v2/client/command renewInterval=5s"
        )

        XCTAssertEqual(
            DemoGatewayRegistrationOutputFormatter.discoveryAttempt(),
            "gateway registration discovery attempt"
        )

        XCTAssertEqual(
            DemoGatewayRegistrationOutputFormatter.registrationSuccess(
                gatewayEndpoint: URL(string: "http://127.0.0.1:18765")!,
                callbackEndpoint: callbackEndpoint
            ),
            "gateway registration success: POST /v2/clients:register gatewayEndpoint=http://127.0.0.1:18765 callbackEndpoint=http://127.0.0.1:18766/v2/client/command"
        )
    }

    func testWebSocketOutputFormatterIncludesPingAck() {
        XCTAssertEqual(
            NeptuneGatewayWebSocketOutputFormatter.commandDispatchPingAck(timestamp: "2026-03-24T10:11:12Z"),
            "ws command.dispatch ping -> command.ack status=ok timestamp=2026-03-24T10:11:12Z"
        )
    }

    func testActionButtonsUseUnifiedThreeActionModel() {
        XCTAssertEqual(
            DemoViewController.actionButtonTitles,
            ["写入日志批次", "发现并上报", "刷新快照"]
        )
    }

    func testDeepDiveEntryPushesComplexPage() {
        let controller = DemoViewController(runtime: DemoRuntimeSpy())
        let navigationController = UINavigationController(rootViewController: controller)

        controller.loadViewIfNeeded()
        controller.openDeepDivePage()

        XCTAssertTrue(navigationController.topViewController is DeepDiveViewController)
    }

    func testDeepDiveEntryButtonHasTouchableFrame() {
        let controller = DemoViewController(runtime: DemoRuntimeSpy())
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()

        let button = try? XCTUnwrap(controller.view.findButton(withTitle: "进入复杂二级页"))
        XCTAssertNotNil(button)
        XCTAssertGreaterThan(button?.bounds.height ?? 0, 30)
        XCTAssertGreaterThan(button?.bounds.width ?? 0, 80)
    }

    func testDeepDiveViewControllerBuildsRichHierarchy() {
        let controller = DeepDiveViewController()
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.title, "Neptune Deep Dive")
        XCTAssertGreaterThanOrEqual(controller.view.recursiveSubviewCount(of: UILabel.self), 20)
        XCTAssertEqual(controller.view.recursiveSubviewCount(of: UIButton.self), 3)
        XCTAssertGreaterThanOrEqual(controller.view.recursiveSubviewCount(of: UIStackView.self), 8)
    }
}

private actor DemoRuntimeSpy: DemoRuntimeManaging {
    private var startGatewayRegistrationCountValue = 0

    func ingestOne() async -> NeptuneLogRecord {
        NeptuneLogRecord(
            id: 1,
            ingest: NeptuneIngestLogRecord(
                timestamp: "2026-03-25T00:00:00Z",
                level: .info,
                message: "stub",
                platform: "ios",
                appId: "com.neptune.demo",
                sessionId: "session-1",
                deviceId: "device-1",
                category: "demo",
                attributes: [:],
                source: NeptuneLogSource(sdkName: "neptune-sdk-ios", sdkVersion: "0.1.0")
            )
        )
    }

    func snapshot() async -> (NeptuneMetricsSnapshot, NeptuneLogsPage) {
        (
            NeptuneMetricsSnapshot(
                totalRecords: 0,
                droppedOverflow: 0,
                oldestRecordId: nil,
                newestRecordId: nil
            ),
            NeptuneLogsPage(records: [], nextCursor: nil, hasMore: false)
        )
    }

    func startServerIfNeeded() async throws -> UInt16 {
        18765
    }

    func discoverGateway() async throws -> NeptuneGatewayDiscoveryResult {
        NeptuneGatewayDiscoveryResult(
            endpoint: URL(string: "http://127.0.0.1:18765")!,
            source: .manualDSN,
            host: "127.0.0.1",
            port: 18765,
            version: "2.0.0-alpha.1"
        )
    }

    func ingestGatewayLog(after discovery: NeptuneGatewayDiscoveryResult) async throws {
        _ = discovery
    }

    func ingestGatewayRawViewTree(after discovery: NeptuneGatewayDiscoveryResult) async throws {
        _ = discovery
    }

    func startGatewayRegistration(log: @escaping @Sendable (String) -> Void) async {
        startGatewayRegistrationCountValue += 1
        log("spy gateway registration started")
    }

    func startGatewayRegistrationCount() -> Int {
        startGatewayRegistrationCountValue
    }
}

private func eventually(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.01,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }

        let nanos = UInt64(max(pollInterval, 0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    return await condition()
}

private extension UIView {
    func recursiveSubviewCount<T: UIView>(of type: T.Type) -> Int {
        subviews.reduce(0) { partialResult, subview in
            let nested = subview.recursiveSubviewCount(of: type)
            return partialResult + (subview is T ? 1 : 0) + nested
        }
    }

    func findButton(withTitle title: String) -> UIButton? {
        if let button = self as? UIButton, button.currentTitle == title {
            return button
        }
        for subview in subviews {
            if let matched = subview.findButton(withTitle: title) {
                return matched
            }
        }
        return nil
    }
}
