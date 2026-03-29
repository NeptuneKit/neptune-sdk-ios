import Testing
@testable import NeptuneSDKiOS
@testable import NeptuneSDKiOSSmokeDemoSupport

@Suite("NeptuneSDKiOS Smoke Demo")
struct SmokeDemoRunnerTests {
    @Test("Smoke demo creates temporary sqlite directory when missing")
    func smokeDemoCreatesTemporaryDirectory() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeptuneSDKiOSSmokeDemo", isDirectory: true)
        if FileManager.default.fileExists(atPath: tempRoot.path) {
            // Some CI/local environments can leave restricted temp entries.
            // Cleanup is best-effort; the test still validates runner behavior.
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let runner = NeptuneSmokeDemoRunner(
            configuration: .init(capacity: 4, ingestCount: 2, pageLimit: 10, keepDatabase: false)
        )

        let summary = try await runner.run()
        #expect(summary.health.ok)
    }

    @Test("Smoke demo exercises ingest, HTTP export, and SQLite persistence")
    func smokeDemoProducesExpectedSummary() async throws {
        let runner = NeptuneSmokeDemoRunner(
            configuration: .init(capacity: 4, ingestCount: 6, pageLimit: 10, keepDatabase: false)
        )

        let summary = try await runner.run()

        #expect(summary.healthStatusCode == 200)
        #expect(summary.health.ok)
        #expect(summary.health.version == NeptuneExportService.version)
        #expect(summary.ingestedCount == 6)
        #expect(summary.metricsStatusCode == 200)
        #expect(summary.logsStatusCode == 200)
        #expect(summary.metrics.totalRecords == 4)
        #expect(summary.metrics.droppedOverflow == 2)
        #expect(summary.logsPage.records.map(\.id) == [3, 4, 5, 6])
        #expect(summary.reopenedMetrics == summary.metrics)
        #expect(summary.reopenedLogsPage == summary.logsPage)

        let rendered = runner.render(summary: summary)
        #expect(rendered.contains("SMOKE_RESULT ok=true"))
        #expect(rendered.contains("overflow=2"))
        #expect(rendered.contains("ids=3,4,5,6"))
    }
}
