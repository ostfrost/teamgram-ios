import Foundation

public struct AvatarServiceAPIConfiguration: Equatable {
    public var baseURL: URL
    public var defaultHeaders: [String: String]

    public init(baseURL: URL, defaultHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
    }
}

public protocol AvatarBearerTokenProviding: AnyObject {
    func avatarBearerToken() async throws -> String?
}

public enum AvatarServiceAPIError: Error, Equatable {
    case invalidBaseURL
    case invalidResponse
    case unexpectedStatusCode(Int, AvatarProblemDetail?)
    case decodingFailed(String)
    case encodingFailed(String)
    case missingMultipartBoundary
}

public struct AvatarProblemDetail: Codable, Equatable, Sendable {
    public var type: String
    public var title: String
    public var status: Int
    public var detail: String?
    public var instance: String?
}

public enum AvatarJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AvatarJSONValue])
    case object([String: AvatarJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AvatarJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AvatarJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

public final class AvatarServiceAPIClient {
    private let configuration: AvatarServiceAPIConfiguration
    private let tokenProvider: AvatarBearerTokenProviding?
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        configuration: AvatarServiceAPIConfiguration,
        tokenProvider: AvatarBearerTokenProviding? = nil,
        urlSession: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.encoder = encoder
        self.decoder = decoder
    }

    public func get<Response: Decodable>(_ path: String) async throws -> Response {
        var request = try await self.makeRequest(path: path)
        request.httpMethod = "GET"
        return try await self.performJSON(request)
    }

    public func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        var request = try await self.makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try self.encode(body)
        return try await self.performJSON(request)
    }

    public func put<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        var request = try await self.makeRequest(path: path)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try self.encode(body)
        return try await self.performJSON(request)
    }

    public func delete(_ path: String) async throws {
        var request = try await self.makeRequest(path: path)
        request.httpMethod = "DELETE"
        _ = try await self.perform(request, acceptsEmptyResponse: true)
    }

    public func postMultipart<Response: Decodable>(
        _ path: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        data: Data,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        let boundary = "AvatarBoundary-\(UUID().uuidString)"
        var request = try await self.makeRequest(path: path)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout ?? request.timeoutInterval
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fieldName: fieldName,
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        return try await self.performJSON(request)
    }

    private func makeRequest(path: String) async throws -> URLRequest {
        guard var components = URLComponents(url: self.configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw AvatarServiceAPIError.invalidBaseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/"))

        guard let url = components.url else {
            throw AvatarServiceAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in self.configuration.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let bearerToken = try await self.tokenProvider?.avatarBearerToken(), !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func encode<Request: Encodable>(_ body: Request) throws -> Data {
        do {
            return try self.encoder.encode(body)
        } catch {
            throw AvatarServiceAPIError.encodingFailed(String(describing: error))
        }
    }

    private func performJSON<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await self.perform(request, acceptsEmptyResponse: false)
        do {
            return try self.decoder.decode(Response.self, from: data)
        } catch {
            throw AvatarServiceAPIError.decodingFailed(String(describing: error))
        }
    }

    private func perform(_ request: URLRequest, acceptsEmptyResponse: Bool) async throws -> Data {
        let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = self.urlSession.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: AvatarServiceAPIError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AvatarServiceAPIError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw AvatarServiceAPIError.unexpectedStatusCode(httpResponse.statusCode, self.problemDetail(from: data))
        }
        if data.isEmpty && !acceptsEmptyResponse {
            throw AvatarServiceAPIError.invalidResponse
        }
        return data
    }

    private func problemDetail(from data: Data) -> AvatarProblemDetail? {
        guard !data.isEmpty else {
            return nil
        }
        return try? self.decoder.decode(AvatarProblemDetail.self, from: data)
    }

    private static func multipartBody(
        boundary: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
