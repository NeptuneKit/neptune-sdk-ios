@_exported import Foundation

public struct NeptuneSDKiOS {
    public static func makeExportService() -> NeptuneExportService {
        NeptuneExportService()
    }

    public static func makeExportHTTPServer(service: NeptuneExportService = NeptuneExportService()) -> NeptuneExportHTTPServer {
        NeptuneExportHTTPServer(service: service)
    }
}
