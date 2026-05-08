@_exported import AvatarServiceAPI
import Foundation

public typealias AvatarServiceConfiguration = AvatarServiceAPIConfiguration
public typealias AvatarServiceTokenProviding = AvatarBearerTokenProviding
public typealias AvatarServiceClientError = AvatarServiceAPIError
public typealias AvatarParametersJSON = [String: AvatarJSONValue]

public enum AvatarType: String, Codable, Equatable, Sendable {
    case human
    case animal
}

public protocol AvatarServiceClientProtocol {
    func listAvatars() async throws -> [AvatarServiceAvatar]
    func createAvatar(name: String, type: AvatarType, paramsJson: AvatarParametersJSON?) async throws -> AvatarServiceAvatar
    func getAvatar(id: Int64) async throws -> AvatarServiceAvatar
    func updateAvatar(id: Int64, name: String?, type: AvatarType?, paramsJson: AvatarParametersJSON?) async throws -> AvatarServiceAvatar
    func deleteAvatar(id: Int64) async throws
    func analyzeAvatar(_ request: AnalyzeAvatarRequest) async throws -> AnalyzeResponse
    func analyzeAvatarWithImage(_ imageData: Data, fileName: String, mimeType: String) async throws -> AnalyzeResponse
}

public extension AvatarServiceClientProtocol {
    func getAvatars() async throws -> [AvatarServiceAvatar] {
        try await self.listAvatars()
    }
}

public struct AvatarServiceAvatar: Codable, Equatable, Sendable {
    public var id: Int64
    public var userId: Int64
    public var name: String
    public var type: AvatarType
    public var paramsJson: AvatarParametersJSON
    public var images: [AvatarImage]?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: Int64,
        userId: Int64,
        name: String,
        type: AvatarType,
        paramsJson: AvatarParametersJSON = [:],
        images: [AvatarImage]? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.paramsJson = paramsJson
        self.images = images
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AvatarImage: Codable, Equatable, Sendable {
    public var id: Int64
    public var avatarId: Int64
    public var kind: String
    public var s3Key: String
    public var width: Int
    public var height: Int
    public var createdAt: String
}

public struct AnalyzeAvatarRequest: Codable, Equatable, Sendable {
    public var landmarks: [CanonicalLandmark]
    public var morphs: [String: Double]
    public var colors: AvatarAnalysisColors
    public var confidence: Double?
    public var platform: String?
    public var clientLatencyMs: Int?

    public init(
        landmarks: [CanonicalLandmark],
        morphs: [String: Double],
        colors: AvatarAnalysisColors,
        confidence: Double? = nil,
        platform: String? = "ios",
        clientLatencyMs: Int? = nil
    ) {
        self.landmarks = landmarks
        self.morphs = morphs
        self.colors = colors
        self.confidence = confidence
        self.platform = platform
        self.clientLatencyMs = clientLatencyMs
    }
}

public struct CanonicalLandmark: Codable, Equatable, Sendable {
    public var name: String
    public var x: Double
    public var y: Double

    public init(name: String, x: Double, y: Double) {
        self.name = name
        self.x = x
        self.y = y
    }
}

public struct AvatarAnalysisColors: Codable, Equatable, Sendable {
    public var skin: String
    public var hair: String
    public var eye: String

    public init(skin: String, hair: String, eye: String) {
        self.skin = skin
        self.hair = hair
        self.eye = eye
    }
}

public struct AnalyzeResponse: Codable, Equatable, Sendable {
    public var preset: AvatarPreset
    public var confidence: Double
    public var analyzer: String
}

public struct AvatarPreset: Codable, Equatable, Sendable {
    public var type: AvatarType
    public var morphs: [String: Double]
    public var colors: [String: String]
    public var suggestedHairStyleId: String?
}

public final class AvatarServiceHTTPClient: AvatarServiceClientProtocol {
    private struct AvatarListEnvelope: Decodable {
        var avatars: [AvatarServiceAvatar]
    }

    private struct CreateAvatarRequest: Encodable {
        var name: String
        var type: AvatarType
        var paramsJson: AvatarParametersJSON?
    }

    private struct UpdateAvatarRequest: Encodable {
        var name: String?
        var type: AvatarType?
        var paramsJson: AvatarParametersJSON?
    }

    private let api: AvatarServiceAPIClient

    public init(
        configuration: AvatarServiceConfiguration,
        tokenProvider: AvatarServiceTokenProviding? = nil,
        urlSession: URLSession = .shared
    ) {
        self.api = AvatarServiceAPIClient(
            configuration: configuration,
            tokenProvider: tokenProvider,
            urlSession: urlSession
        )
    }

    public func listAvatars() async throws -> [AvatarServiceAvatar] {
        let envelope: AvatarListEnvelope = try await self.api.get("avatars")
        return envelope.avatars
    }

    public func createAvatar(
        name: String,
        type: AvatarType,
        paramsJson: AvatarParametersJSON? = nil
    ) async throws -> AvatarServiceAvatar {
        try await self.api.post(
            "avatars",
            body: CreateAvatarRequest(name: name, type: type, paramsJson: paramsJson)
        )
    }

    public func getAvatar(id: Int64) async throws -> AvatarServiceAvatar {
        try await self.api.get("avatars/\(id)")
    }

    public func updateAvatar(
        id: Int64,
        name: String? = nil,
        type: AvatarType? = nil,
        paramsJson: AvatarParametersJSON? = nil
    ) async throws -> AvatarServiceAvatar {
        try await self.api.put(
            "avatars/\(id)",
            body: UpdateAvatarRequest(name: name, type: type, paramsJson: paramsJson)
        )
    }

    public func deleteAvatar(id: Int64) async throws {
        try await self.api.delete("avatars/\(id)")
    }

    public func analyzeAvatar(_ request: AnalyzeAvatarRequest) async throws -> AnalyzeResponse {
        try await self.api.post("avatars/analyze", body: request)
    }

    public func analyzeAvatarWithImage(
        _ imageData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> AnalyzeResponse {
        try await self.api.postMultipart(
            "avatars/analyze/with-image",
            fieldName: "image",
            fileName: fileName,
            mimeType: mimeType,
            data: imageData,
            timeout: 5.0
        )
    }
}
