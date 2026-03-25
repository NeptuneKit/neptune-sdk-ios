import Foundation

public enum NeptuneGatewayRegistrationTransportPreference: String, Codable, Sendable, Equatable {
    case http
    case usbmuxd
}

public struct NeptuneGatewayRegistrationConfiguration: Sendable, Equatable {
    public var platform: String
    public var appId: String
    public var sessionId: String
    public var deviceId: String
    public var preferredTransports: [NeptuneGatewayRegistrationTransportPreference]
    public var usbmuxdHint: String?
    public var callbackEndpoint: URL
    public var renewInterval: TimeInterval
    public var sdkName: String?
    public var sdkVersion: String?

    public init(
        platform: String = "ios",
        appId: String,
        sessionId: String,
        deviceId: String,
        preferredTransports: [NeptuneGatewayRegistrationTransportPreference] = [.http],
        usbmuxdHint: String? = nil,
        callbackEndpoint: URL,
        renewInterval: TimeInterval = 30,
        sdkName: String? = nil,
        sdkVersion: String? = nil
    ) {
        self.platform = platform
        self.appId = appId
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.preferredTransports = preferredTransports
        self.usbmuxdHint = usbmuxdHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.callbackEndpoint = callbackEndpoint
        self.renewInterval = max(0, renewInterval)
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
    }

    var payload: NeptuneGatewayRegistrationPayload {
        NeptuneGatewayRegistrationPayload(
            platform: platform,
            appId: appId,
            sessionId: sessionId,
            deviceId: deviceId,
            preferredTransports: preferredTransports,
            usbmuxdHint: usbmuxdHint,
            callbackEndpoint: callbackEndpoint,
            sdkName: sdkName,
            sdkVersion: sdkVersion
        )
    }
}

public struct NeptuneGatewayRegistrationPayload: Codable, Sendable, Equatable {
    public var platform: String
    public var appId: String
    public var sessionId: String
    public var deviceId: String
    public var preferredTransports: [NeptuneGatewayRegistrationTransportPreference]
    public var usbmuxdHint: String?
    public var callbackEndpoint: URL
    public var sdkName: String?
    public var sdkVersion: String?

    public init(
        platform: String,
        appId: String,
        sessionId: String,
        deviceId: String,
        preferredTransports: [NeptuneGatewayRegistrationTransportPreference] = [.http],
        usbmuxdHint: String? = nil,
        callbackEndpoint: URL,
        sdkName: String? = nil,
        sdkVersion: String? = nil
    ) {
        self.platform = platform
        self.appId = appId
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.preferredTransports = preferredTransports
        self.usbmuxdHint = usbmuxdHint
        self.callbackEndpoint = callbackEndpoint
        self.sdkName = sdkName
        self.sdkVersion = sdkVersion
    }
}

public protocol NeptuneGatewayRegistrationTransport: Sendable {
    func send(payload: NeptuneGatewayRegistrationPayload, to gatewayEndpoint: URL) async throws
}

public struct NeptuneURLSessionGatewayRegistrationTransport: NeptuneGatewayRegistrationTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(payload: NeptuneGatewayRegistrationPayload, to gatewayEndpoint: URL) async throws {
        let request = try Self.makeRequest(payload: payload, gatewayEndpoint: gatewayEndpoint)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw NeptuneGatewayRegistrationTransportError.invalidHTTPResponse
        }
    }

    public static func makeRequest(
        payload: NeptuneGatewayRegistrationPayload,
        gatewayEndpoint: URL
    ) throws -> URLRequest {
        let requestURL = gatewayEndpoint
            .appendingPathComponent("v2")
            .appendingPathComponent("clients:register")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try makeEncoder().encode(payload)
        return request
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public enum NeptuneGatewayRegistrationTransportError: Error, Sendable, Equatable, LocalizedError {
    case invalidHTTPResponse

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "gateway returned a non-2xx response"
        }
    }
}
