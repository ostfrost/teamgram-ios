import Foundation

public struct AvatarServiceConfiguration: Equatable {
    public var baseURL: URL
    public var defaultHeaders: [String: String]

    public init(baseURL: URL, defaultHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
    }
}

public protocol AvatarServiceTokenProviding: AnyObject {
    func avatarServiceBearerToken() async throws -> String?
}

public protocol AvatarServiceClientProtocol {
    func getAvatars() async throws -> [AvatarServiceAvatar]
}

public struct AvatarServiceAvatar: Decodable, Equatable, Sendable {
    public var id: String
    public var paramsJSON: String?
    public var displayName: String?
    public var updatedAt: String?

    public init(
        id: String,
        paramsJSON: String? = nil,
        displayName: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.paramsJSON = paramsJSON
        self.displayName = displayName
        self.updatedAt = updatedAt
    }
}

public enum AvatarServiceClientError: Error, Equatable {
    case invalidBaseURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case decodingFailed(String)
}

public final class AvatarServiceHTTPClient: AvatarServiceClientProtocol {
    private struct AvatarListEnvelope: Decodable {
        var avatars: [AvatarServiceAvatar]
    }

    private let configuration: AvatarServiceConfiguration
    private let tokenProvider: AvatarServiceTokenProviding?
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(
        configuration: AvatarServiceConfiguration,
        tokenProvider: AvatarServiceTokenProviding? = nil,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.decoder = decoder
    }

    public func getAvatars() async throws -> [AvatarServiceAvatar] {
        var request = try await self.makeRequest(path: "avatars")
        request.httpMethod = "GET"

        let (data, response) = try await self.perform(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AvatarServiceClientError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw AvatarServiceClientError.unexpectedStatusCode(httpResponse.statusCode)
        }

        return try self.decodeAvatarList(from: data)
    }

    private func makeRequest(path: String) async throws -> URLRequest {
        guard var components = URLComponents(url: self.configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw AvatarServiceClientError.invalidBaseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, path].filter { !$0.isEmpty }.joined(separator: "/"))

        guard let url = components.url else {
            throw AvatarServiceClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in self.configuration.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let bearerToken = try await self.tokenProvider?.avatarServiceBearerToken(), !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.urlSession.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: AvatarServiceClientError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private func decodeAvatarList(from data: Data) throws -> [AvatarServiceAvatar] {
        do {
            return try self.decoder.decode([AvatarServiceAvatar].self, from: data)
        } catch {
            do {
                return try self.decoder.decode(AvatarListEnvelope.self, from: data).avatars
            } catch {
                throw AvatarServiceClientError.decodingFailed(String(describing: error))
            }
        }
    }
}
