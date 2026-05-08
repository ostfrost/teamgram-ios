import AvatarServiceAPI
import Foundation

public struct AvatarAuthConfiguration: Equatable {
    public var baseURL: URL
    public var defaultHeaders: [String: String]

    public init(baseURL: URL, defaultHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
    }
}

public protocol AvatarAuthClientProtocol {
    func sendCode(phoneNumber: String) async throws -> AvatarSendCodeResult
    func signIn(phoneNumber: String, phoneCodeHash: String, phoneCode: String) async throws -> AvatarAuthStep
    func signUp(phoneNumber: String, phoneCodeHash: String, phoneCode: String, firstName: String, lastName: String?) async throws -> AvatarAuthorizedSession
    func checkPassword(phoneNumber: String, password: String) async throws -> AvatarAuthorizedSession
}

public struct AvatarSendCodeResult: Codable, Equatable, Sendable {
    public var phoneCodeHash: String

    public init(phoneCodeHash: String) {
        self.phoneCodeHash = phoneCodeHash
    }
}

public enum AvatarAuthStep: Equatable, Sendable {
    case authorized(AvatarAuthorizedSession)
    case signUpRequired(phoneCodeHash: String)
    case passwordRequired(passwordHash: String, userId: Int64?)
}

public struct AvatarAuthorizedSession: Codable, Equatable, Sendable {
    public var token: String
    public var expiresIn: Int
    public var userId: Int64

    public init(token: String, expiresIn: Int, userId: Int64) {
        self.token = token
        self.expiresIn = expiresIn
        self.userId = userId
    }
}

public enum AvatarAuthClientError: Error, Equatable {
    case unexpectedStatus(String)
    case missingAuthorizedSession
}

public final class AvatarAuthHTTPClient: AvatarAuthClientProtocol {
    private struct SendCodeRequest: Encodable {
        var phoneNumber: String
    }

    private struct SignInRequest: Encodable {
        var phoneNumber: String
        var phoneCodeHash: String
        var phoneCode: String
    }

    private struct SignUpRequest: Encodable {
        var phoneNumber: String
        var phoneCodeHash: String
        var phoneCode: String
        var firstName: String
        var lastName: String?
    }

    private struct CheckPasswordRequest: Encodable {
        var phoneNumber: String
        var password: String
    }

    private struct AuthEnvelope: Decodable {
        var status: String
        var token: String?
        var expiresIn: Int?
        var userId: Int64?
        var phoneCodeHash: String?
        var passwordHash: String?
    }

    private let api: AvatarServiceAPIClient

    public init(
        configuration: AvatarAuthConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.api = AvatarServiceAPIClient(
            configuration: AvatarServiceAPIConfiguration(
                baseURL: configuration.baseURL,
                defaultHeaders: configuration.defaultHeaders
            ),
            urlSession: urlSession
        )
    }

    public func sendCode(phoneNumber: String) async throws -> AvatarSendCodeResult {
        try await self.api.post("auth/send-code", body: SendCodeRequest(phoneNumber: phoneNumber))
    }

    public func signIn(phoneNumber: String, phoneCodeHash: String, phoneCode: String) async throws -> AvatarAuthStep {
        let envelope: AuthEnvelope = try await self.api.post(
            "auth/sign-in",
            body: SignInRequest(phoneNumber: phoneNumber, phoneCodeHash: phoneCodeHash, phoneCode: phoneCode)
        )
        return try Self.mapAuthStep(envelope)
    }

    public func signUp(
        phoneNumber: String,
        phoneCodeHash: String,
        phoneCode: String,
        firstName: String,
        lastName: String?
    ) async throws -> AvatarAuthorizedSession {
        let envelope: AuthEnvelope = try await self.api.post(
            "auth/sign-up",
            body: SignUpRequest(
                phoneNumber: phoneNumber,
                phoneCodeHash: phoneCodeHash,
                phoneCode: phoneCode,
                firstName: firstName,
                lastName: lastName
            )
        )
        guard case let .authorized(session) = try Self.mapAuthStep(envelope) else {
            throw AvatarAuthClientError.missingAuthorizedSession
        }
        return session
    }

    public func checkPassword(phoneNumber: String, password: String) async throws -> AvatarAuthorizedSession {
        let envelope: AuthEnvelope = try await self.api.post(
            "auth/check-password",
            body: CheckPasswordRequest(phoneNumber: phoneNumber, password: password)
        )
        guard case let .authorized(session) = try Self.mapAuthStep(envelope) else {
            throw AvatarAuthClientError.missingAuthorizedSession
        }
        return session
    }

    private static func mapAuthStep(_ envelope: AuthEnvelope) throws -> AvatarAuthStep {
        switch envelope.status {
        case "authorized":
            guard let token = envelope.token, let expiresIn = envelope.expiresIn, let userId = envelope.userId else {
                throw AvatarAuthClientError.missingAuthorizedSession
            }
            return .authorized(AvatarAuthorizedSession(token: token, expiresIn: expiresIn, userId: userId))
        case "sign_up_required":
            return .signUpRequired(phoneCodeHash: envelope.phoneCodeHash ?? "")
        case "password_required":
            return .passwordRequired(passwordHash: envelope.passwordHash ?? "", userId: envelope.userId)
        default:
            throw AvatarAuthClientError.unexpectedStatus(envelope.status)
        }
    }
}
