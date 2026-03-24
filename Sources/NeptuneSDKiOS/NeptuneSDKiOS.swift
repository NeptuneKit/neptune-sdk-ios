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
}
