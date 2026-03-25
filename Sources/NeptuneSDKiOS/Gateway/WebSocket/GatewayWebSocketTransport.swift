import Foundation

public protocol NeptuneGatewayWebSocketSession: Sendable {
    func send(text: String) async throws
    func receiveText() async throws -> String?
    func cancel()
}

public protocol NeptuneGatewayWebSocketTransport: Sendable {
    func connect(to url: URL) async throws -> any NeptuneGatewayWebSocketSession
}

public struct NeptuneURLSessionGatewayWebSocketTransport: NeptuneGatewayWebSocketTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(to url: URL) async throws -> any NeptuneGatewayWebSocketSession {
        let task = session.webSocketTask(with: url)
        task.resume()
        return NeptuneURLSessionGatewayWebSocketSession(task: task)
    }
}

public enum NeptuneGatewayWebSocketTransportError: Error, Sendable, Equatable {
    case invalidMessageEncoding
    case unsupportedMessageType
}

final class NeptuneURLSessionGatewayWebSocketSession: NeptuneGatewayWebSocketSession, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveText() async throws -> String? {
        let message = try await task.receive()
        switch message {
        case let .string(text):
            return text
        case let .data(data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw NeptuneGatewayWebSocketTransportError.invalidMessageEncoding
            }
            return text
        @unknown default:
            throw NeptuneGatewayWebSocketTransportError.unsupportedMessageType
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

