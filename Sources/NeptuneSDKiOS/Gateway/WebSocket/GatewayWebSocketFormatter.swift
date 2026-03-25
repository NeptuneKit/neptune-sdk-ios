import Foundation

public enum NeptuneGatewayWebSocketOutputFormatter {
    public static func connected(endpoint: URL) -> String {
        "ws connected endpoint=\(endpoint.absoluteString)"
    }

    public static func helloSent(endpoint: URL) -> String {
        "ws hello sent role=sdk endpoint=\(endpoint.absoluteString)"
    }

    public static func heartbeatSent(timestamp: String) -> String {
        "ws heartbeat sent timestamp=\(timestamp)"
    }

    public static func commandDispatchPingAck(timestamp: String) -> String {
        "ws command.dispatch ping -> command.ack status=ok timestamp=\(timestamp)"
    }

    public static func endpointChanged(from: URL, to: URL) -> String {
        "ws discovery endpoint changed from=\(from.absoluteString) to=\(to.absoluteString)"
    }

    public static func reconnectScheduled(after seconds: TimeInterval, reason: String) -> String {
        "ws reconnect scheduled after=\(format(seconds)) reason=\(reason)"
    }

    public static func connectFailed(endpoint: URL, error: Error) -> String {
        "ws connect failed endpoint=\(endpoint.absoluteString) error=\(error.localizedDescription)"
    }

    public static func discoveryCheckFailed(error: Error) -> String {
        "ws discovery check failed error=\(error.localizedDescription)"
    }

    private static func format(_ seconds: TimeInterval) -> String {
        if seconds.rounded(.towardZero) == seconds {
            return "\(Int(seconds))s"
        }

        return "\(String(format: "%.3g", seconds))s"
    }
}

